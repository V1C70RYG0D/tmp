// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@aave/core-v3/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";

import "../../protocols/gmxv2/Deposit.sol" as GDeposit;
import "../../protocols/gmxv2/EventUtils.sol";
import "../../protocols/gmxv2/IRoleStore.sol";

import "./IGMXv2strategyReader.sol";

import "../../base/FijaStrategy.sol";
import "./GMXv2strategyBase.sol";

import "./GMXv2Lib.sol";

import "./errors.sol";

///
/// @title GMXv2 Strategy
/// @author Fija
/// @notice Main contract used for asset management
/// @dev supports adding and removing liquidity from the GMX market, harvesting and rebalancing assets
///
contract GMXv2strategy is
    IFijaStrategy,
    IFlashLoanSimpleReceiver,
    FijaStrategy,
    GMXv2strategyBase
{
    using Math for uint256;

    ///
    /// @dev mapping by tx key, to data required in 2nd tx for GMX callbacks
    ///
    mapping(bytes32 => GMXv2Type.CallbackData) internal _callbackDataMap;

    ///
    /// @dev mapping by tx key, to vault and strategy calldata
    ///
    mapping(bytes32 => GMXv2Type.TxParamsWrapper) internal _txParamsWrapperMap;

    ///
    /// @dev reference to strategy data used by external library
    ///
    GMXv2Type.StrategyData internal _strategyData;

    ///
    /// @dev reference to strategy metadata shared with external library
    ///
    GMXv2Type.StrategyMetadata internal _strategyMetadata;

    ///
    /// @dev reference to periphery contract used for read-only operations
    ///
    address internal PERIPHERY;

    ///
    /// @dev GMX keeper execution fee
    ///
    uint256 internal _executionFee;

    ///
    /// @dev unique key used for storing of _callbackDataMap and
    /// _txParamsWrapperMap for special case Tlong == 0
    ///
    uint256 internal _localKey;

    ///
    /// @dev Throws if emergency mode is in progress
    ///
    modifier emergencyModeInProgress() {
        _emergencyModeInProgress();
        _;
    }

    ///
    /// @dev Throws if harvest is in progress
    ///
    modifier harvestInProgress() {
        _harvestInProgress();
        _;
    }

    ///
    /// @dev Throws if rebalance is in progress
    ///
    modifier rebalanceInProgress() {
        _rebalanceInProgress();
        _;
    }

    constructor(
        address depositCcy_,
        address governance_,
        string memory tokenName_,
        string memory tokenSymbol_,
        uint256 maxTicketSize_,
        uint256 maxVaultValue_,
        ConstructorData memory data_
    )
        GMXv2strategyBase(data_, depositCcy_)
        FijaStrategy(
            IERC20(depositCcy_),
            governance_,
            tokenName_,
            tokenSymbol_,
            maxTicketSize_,
            maxVaultValue_
        )
    {
        _strategyMetadata.lastHarvestTime = block.timestamp;
        _strategyMetadata.emergencyModeStartTime = type(uint64).max;
        _strategyMetadata.harvestModeStartTime = type(uint64).max;
        _strategyMetadata.rebalanceModeStartTime = type(uint64).max;

        _strategyData = GMXv2Type.StrategyData(
            address(0),
            GM_POOL,
            SEC_CCY,
            DEPOSIT_CCY,
            UNISWAP_DEP_SEC_POOL,
            UNISWAP_NATIVE_DEP_POOL,
            WETH,
            DEP_CCY_DECIMALS,
            SEC_CCY_DECIMALS,
            LONG_PRICE_DECIMALS,
            SHORT_PRICE_DECIMALS
        );

        // validate market
        Market.Props memory market = IReader(data_.contracts.reader).getMarket(
            data_.contracts.datastore,
            GM_POOL
        );
        if (
            !(market.longToken == DEPOSIT_CCY && market.shortToken == SEC_CCY)
        ) {
            if (
                !(market.longToken == SEC_CCY &&
                    market.shortToken == DEPOSIT_CCY)
            ) {
                revert FijaInvalidStrategyParams();
            }
        }
    }

    ///
    /// @dev Throws if caller doesn't have GMX `controller` role
    ///
    modifier controllerOnly() {
        _controllerOnly();
        _;
    }

    ///
    /// @dev Throws if caller is not self or AAVE pool
    ///
    modifier selfAaveOnly(address initiator) {
        _selfAaveOnly(initiator);
        _;
    }

    ///
    /// @dev sets periphery contract address
    /// @param periphery address of read-only periphery contract
    ///
    function initialize(address periphery) external onlyOwner {
        PERIPHERY = periphery;
        _strategyData.PERIPHERY = periphery;
    }

    ///
    /// NOTE: uses periphery contract to query total assets under management
    /// @inheritdoc IERC4626
    ///
    function totalAssets() public view virtual override returns (uint256) {
        uint256 assets = IGMXv2strategyReader(PERIPHERY).assetsOnly() -
            _strategyMetadata.flashLoanAmount -
            _executionFee;

        uint256 supply = totalSupply();

        if (supply == 0) {
            return assets;
        }

        uint256 currentTokenPrice = (assets * 10 ** DEP_CCY_DECIMALS) / supply;

        return assets - _profitShare(currentTokenPrice);
    }

    ///
    /// @dev calculates amount of tokens receiver will get based on asset deposit.
    /// @param assets amount of assets caller wants to deposit
    /// @param receiver address of the owner of deposit once deposit completes, this address will receive tokens.
    /// @return amount of tokens receiver will receive
    /// NOTE: executes deposits to GMX market and mints strategy tokens to the caller
    /// Caller and receiver must be whitelisted
    /// Cannot deposit in emergency mode
    /// Emits IERC4626.Deposit
    ///
    function deposit(
        uint256 assets,
        address receiver
    )
        public
        payable
        virtual
        override(FijaStrategy, IERC4626)
        emergencyModeRestriction
        onlyWhitelisted
        nonZeroAmount(assets)
        onlyReceiverWhitelisted(receiver)
        returns (uint256)
    {
        uint256 tokens;
        uint256 balance;

        if (asset() == ETH) {
            _executionFee = msg.value - assets;
            uint256 totalAssetBeforeDeposit = totalAssets() - assets;

            require(
                assets <= _maxDeposit(receiver, totalAssetBeforeDeposit),
                "ERC4626: deposit more than max"
            );

            uint256 supply = totalSupply();
            tokens = (assets == 0 || supply == 0)
                ? _initialConvertToShares(assets, Math.Rounding.Down)
                : assets.mulDiv(
                    supply,
                    totalAssetBeforeDeposit,
                    Math.Rounding.Down
                );

            _mint(receiver, tokens);

            // convert all ETH to WETH to prepare for deposit
            IWETH(WETH).deposit{value: address(this).balance - _executionFee}();
            balance = IERC20(WETH).balanceOf(address(this));
        } else {
            tokens = ERC4626.deposit(assets, receiver);
            balance = IERC20(asset()).balanceOf(address(this));
        }

        // store vault and strategy calldata
        TxParams memory vaultParams = IFijaVault2Txn(receiver).txParams();
        GMXv2Type.TxParamsWrapper memory txParamsWrapper = GMXv2Type
            .TxParamsWrapper(
                TxParams(assets, 0, receiver, address(0), TxType.DEPOSIT),
                vaultParams
            );

        // create main input params to pass to investment logic
        GMXv2Type.InvestLogicData memory investData = GMXv2Type.InvestLogicData(
            int256(balance),
            _executionFee == 0 ? msg.value : _executionFee,
            txParamsWrapper
        );

        // call main investment logic and deposit assets to strategy
        GMXv2Lib.genericInvestmentLogic(
            _strategyData,
            _contracts,
            _callbackDataMap,
            _txParamsWrapperMap,
            investData
        );

        // signal vault strategy investment process is complete
        IFijaVault2Txn(receiver).afterDeposit(
            vaultParams.assets,
            vaultParams.tokens,
            vaultParams.receiver,
            true
        );
        _executionFee = 0;

        emit Deposit(msg.sender, receiver, assets, tokens);

        return tokens;
    }

    ///
    /// @dev Burns tokens from owner and sends exact number of assets to receiver
    /// @param assets amount of assets caller wants to withdraw
    /// @param receiver address of the asset receiver
    /// @param owner address of the owner of tokens
    /// @return amount of tokens burnt based on exact assets requested
    /// NOTE: executes withdrawal from GMX, sending assets to the caller
    /// Caller, receiver and owner must be whitelisted
    /// Emits IERC4626.Withdraw
    ///
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    )
        public
        payable
        virtual
        override
        onlyWhitelisted
        nonZeroAmount(assets)
        onlyReceiverOwnerWhitelisted(receiver, owner)
        returns (uint256)
    {
        // strategy calls itself directly to burn the strategy tokens and give back assets to the vault
        if (msg.sender == address(this)) {
            return super.withdraw(assets, receiver, owner);
        }

        require(
            assets <= maxWithdraw(owner),
            "ERC4626: withdraw more than max"
        );

        uint256 currentBalance;
        uint256 wethBalance;

        if (asset() == ETH) {
            _executionFee = msg.value;

            wethBalance = IERC20(WETH).balanceOf(address(this));

            currentBalance = address(this).balance - msg.value + wethBalance;
        } else {
            currentBalance = IERC20(asset()).balanceOf(address(this));
        }
        uint256 tokensToReturn;
        if (assets > currentBalance) {
            // store vault and strategy calldata
            GMXv2Type.TxParamsWrapper memory txParams = GMXv2Type
                .TxParamsWrapper(
                    TxParams(assets, 0, receiver, owner, TxType.WITHDRAW),
                    IFijaVault2Txn(owner).txParams()
                );

            // create main input params to pass to investment logic
            GMXv2Type.InvestLogicData memory investData = GMXv2Type
                .InvestLogicData(
                    int256(currentBalance) - int256(assets),
                    msg.value,
                    txParams
                );

            // withdraw from GMX required asset amount
            GMXv2Lib.genericInvestmentLogic(
                _strategyData,
                _contracts,
                _callbackDataMap,
                _txParamsWrapperMap,
                investData
            );

            tokensToReturn = 0;
        } else {
            // withdraw directly from strategy
            if (asset() == ETH && wethBalance > 0) {
                IWETH(WETH).withdraw(wethBalance);
            }
            tokensToReturn = super.withdraw(assets, receiver, owner);

            TxParams memory vaultParams = IFijaVault2Txn(owner).txParams();

            // signal vault, strategy withdraw process completed
            IFijaVault2Txn(owner).afterWithdraw(
                vaultParams.assets,
                vaultParams.receiver,
                vaultParams.owner,
                true
            );
        }
        _executionFee = 0;

        return tokensToReturn;
    }

    ///
    /// @dev Burns exact number of tokens from owner and sends assets to receiver.
    /// @param tokens amount of tokens caller wants to redeem
    /// @param receiver address of the asset receiver
    /// @param owner address of the owner of tokens
    /// @return amount of assets receiver will receive based on exact burnt tokens
    /// NOTE: executes redeem from GMX, sending assets to the caller
    /// Caller, receiver and owner must be whitelisted
    /// Emits IERC4626.Withdraw
    ///
    function redeem(
        uint256 tokens,
        address receiver,
        address owner
    )
        public
        payable
        virtual
        override
        onlyWhitelisted
        nonZeroAmount(tokens)
        onlyReceiverOwnerWhitelisted(receiver, owner)
        returns (uint256)
    {
        // strategy calls itself directly to burn the strategy tokens and give back assets to the vault
        if (msg.sender == address(this)) {
            return super.redeem(tokens, receiver, owner);
        }

        require(tokens <= maxRedeem(owner), "ERC4626: redeem more than max");

        uint256 assets;
        uint256 currentBalance;
        uint256 wethBalance;

        if (asset() == ETH) {
            _executionFee = msg.value;

            assets = previewRedeem(tokens);
            wethBalance = IERC20(WETH).balanceOf(address(this));

            currentBalance = address(this).balance - msg.value + wethBalance;
        } else {
            assets = previewRedeem(tokens);
            currentBalance = IERC20(asset()).balanceOf(address(this));
        }

        uint256 assetsToReturn;
        if (assets > currentBalance) {
            // store vault and strategy calldata
            GMXv2Type.TxParamsWrapper memory txParams = GMXv2Type
                .TxParamsWrapper(
                    TxParams(0, tokens, receiver, owner, TxType.REDEEM),
                    IFijaVault2Txn(owner).txParams()
                );

            // create main input params to pass to investment logic
            GMXv2Type.InvestLogicData memory investData = GMXv2Type
                .InvestLogicData(
                    int256(currentBalance) - int256(assets),
                    msg.value,
                    txParams
                );

            // withdraw from GMX required asset amount
            GMXv2Lib.genericInvestmentLogic(
                _strategyData,
                _contracts,
                _callbackDataMap,
                _txParamsWrapperMap,
                investData
            );

            assetsToReturn = 0;
        } else {
            // redeem directly from strategy
            if (asset() == ETH && wethBalance > 0) {
                IWETH(WETH).withdraw(wethBalance);
            }
            assetsToReturn = super.redeem(tokens, receiver, owner);

            TxParams memory vaultParams = IFijaVault2Txn(owner).txParams();

            // signal vault, strategy redeem process completed
            IFijaVault2Txn(owner).afterRedeem(
                vaultParams.tokens,
                vaultParams.receiver,
                vaultParams.owner,
                true
            );
        }
        _executionFee = 0;

        return assetsToReturn;
    }

    ///
    /// NOTE: rebalance is performed based on health factor
    /// @inheritdoc IFijaStrategy
    ///
    function needRebalance()
        external
        view
        virtual
        override(FijaStrategy, IFijaStrategy)
        returns (bool)
    {
        uint256 hf = IGMXv2strategyReader(PERIPHERY).h();
        if (hf < HF_LOW_THR) {
            return true;
        }
        if (hf > HF_HIGH_THR) {
            return true;
        }

        uint256 imbalanceBps = IGMXv2strategyReader(PERIPHERY).imbalanceBps();

        if (imbalanceBps > IMBALANCE_THR_BPS) {
            return true;
        }
        return false;
    }

    ///
    /// NOTE: Only governance access
    /// Restricted in emergency mode
    /// emits IFijaStrategy.Rebalance (2nd Tx)
    /// @inheritdoc IFijaStrategy
    ///
    function rebalance()
        public
        payable
        virtual
        override(FijaStrategy, IFijaStrategy)
        onlyGovernance
        emergencyModeRestriction
        rebalanceInProgress
    {
        GMXv2Type.TxParamsWrapper memory txParams = GMXv2Type.TxParamsWrapper(
            TxParams(0, 0, address(0), address(0), TxType.REBALANCE),
            TxParams(0, 0, address(0), address(0), TxType.REBALANCE)
        );

        GMXv2Type.InvestLogicData memory investData = GMXv2Type.InvestLogicData(
            0,
            msg.value,
            txParams
        );

        _strategyMetadata.rebalanceModeStartTime = block.timestamp;
        _strategyMetadata.isRebalanceInProgress = true;

        GMXv2Lib.genericInvestmentLogic(
            _strategyData,
            _contracts,
            _callbackDataMap,
            _txParamsWrapperMap,
            investData
        );
    }

    ///
    /// NOTE: harvest is scheduled weekly
    /// @inheritdoc IFijaStrategy
    ///
    function needHarvest()
        external
        view
        virtual
        override(FijaStrategy, IFijaStrategy)
        returns (bool)
    {
        // check weekly
        if (block.timestamp >= (_strategyMetadata.lastHarvestTime + 604800)) {
            return true;
        }

        return false;
    }

    ///
    /// NOTE: Only governance access
    /// Restricted in emergency mode
    /// emits IFijaStrategy.Harvest
    /// @inheritdoc IFijaStrategy
    ///
    function harvest()
        external
        payable
        virtual
        override(FijaStrategy, IFijaStrategy)
        onlyGovernance
        emergencyModeRestriction
        harvestInProgress
    {
        // convert all native tokens to deposit ccy
        GMXv2Lib.convertNativeToDeposit(_strategyData);

        uint256 supply = totalSupply();

        if (supply == 0) {
            _strategyMetadata.lastHarvestTime = block.timestamp;
            _strategyMetadata.tokenMintedLastHarvest = supply;

            emit FijaStrategyEvents.Harvest(block.timestamp, 0, 0, asset(), "");
            return;
        }
        uint256 assetsOnly = IGMXv2strategyReader(PERIPHERY).assetsOnly() -
            _strategyMetadata.flashLoanAmount -
            _executionFee;
        uint256 currentTokenPrice = (assetsOnly * 10 ** DEP_CCY_DECIMALS) /
            supply;

        // decrease in price
        if (currentTokenPrice <= _strategyMetadata.tokenPriceLastHarvest) {
            _strategyMetadata.lastHarvestTime = block.timestamp;
            _strategyMetadata.tokenMintedLastHarvest = supply;

            emit FijaStrategyEvents.Harvest(block.timestamp, 0, 0, asset(), "");
        } else {
            // increase in price
            uint256 profitShare = _profitShare(currentTokenPrice);

            uint256 currentBalance;
            if (asset() == ETH) {
                uint256 wethBalance = IERC20(WETH).balanceOf(address(this));

                if (wethBalance > 0) {
                    IWETH(WETH).withdraw(wethBalance);
                }

                currentBalance = address(this).balance - msg.value;
            } else {
                currentBalance = IERC20(DEPOSIT_CCY).balanceOf(address(this));
            }
            if (currentBalance >= profitShare) {
                _strategyMetadata.lastHarvestTime = block.timestamp;
                _strategyMetadata.tokenPriceLastHarvest = currentTokenPrice;
                _strategyMetadata.tokenMintedLastHarvest = supply;

                if (asset() == ETH) {
                    (bool success, ) = payable(governance()).call{
                        value: profitShare
                    }("");
                    if (!success) {
                        revert TransferFailed();
                    }
                } else {
                    IERC20(DEPOSIT_CCY).transfer(governance(), profitShare);
                }

                emit FijaStrategyEvents.Harvest(
                    block.timestamp,
                    4 * profitShare,
                    profitShare,
                    asset(),
                    ""
                );
            } else {
                // using GMXv2Type.TxParamsWrapper placeholders for vault/strategy calldata to pass profitShare,
                // supply and currentTokenPrice to GMX withdraw callback
                GMXv2Type.TxParamsWrapper memory params = GMXv2Type
                    .TxParamsWrapper(
                        TxParams(
                            profitShare,
                            0,
                            address(0),
                            address(0),
                            TxType.HARVEST
                        ),
                        TxParams(
                            currentTokenPrice,
                            supply,
                            address(0),
                            address(0),
                            TxType.HARVEST
                        )
                    );

                // create main input params for harvesting
                GMXv2Type.InvestLogicData memory investData = GMXv2Type
                    .InvestLogicData(
                        int256(currentBalance) - int256(profitShare),
                        msg.value,
                        params
                    );

                _strategyMetadata.harvestModeStartTime = block.timestamp;
                _strategyMetadata.isHarvestInProgress = true;

                // withdraw from GMX assets for harvest
                GMXv2Lib.genericInvestmentLogic(
                    _strategyData,
                    _contracts,
                    _callbackDataMap,
                    _txParamsWrapperMap,
                    investData
                );
            }
        }
    }

    ///
    /// @inheritdoc IFijaStrategy
    ///
    function emergencyMode()
        external
        view
        virtual
        override(FijaStrategy, IFijaStrategy)
        returns (bool)
    {
        return _strategyMetadata.isEmergencyMode;
    }

    ///
    /// NOTE: Only governance access
    /// emits IFijaStrategy.EmergencyMode (2nd Tx)
    /// @inheritdoc IFijaStrategy
    ///
    function setEmergencyMode(
        bool turnOn
    )
        external
        payable
        override(FijaStrategy, IFijaStrategy)
        onlyGovernance
        emergencyModeInProgress
    {
        if (turnOn) {
            // enter emergency mode

            // store vault and strategy calldata for entering emergency mode
            _strategyMetadata.isEmergencyMode = true;
            GMXv2Type.TxParamsWrapper memory txParams = GMXv2Type
                .TxParamsWrapper(
                    TxParams(
                        0,
                        0,
                        address(0),
                        address(0),
                        TxType.EMERGENCY_MODE_WITHDRAW
                    ),
                    TxParams(
                        0,
                        0,
                        address(0),
                        address(0),
                        TxType.EMERGENCY_MODE_WITHDRAW
                    )
                );
            uint256 currentBalance;
            if (asset() == ETH) {
                // convert ETH to WETH
                IWETH(WETH).deposit{value: address(this).balance - msg.value}();
                currentBalance = IERC20(WETH).balanceOf(address(this));
            } else {
                currentBalance = IERC20(DEPOSIT_CCY).balanceOf(address(this));
            }

            int256 t = int256(currentBalance) - int256(totalAssets());

            // create main input params to pass to enter emergency mode
            GMXv2Type.InvestLogicData memory investData = GMXv2Type
                .InvestLogicData(t, msg.value, txParams);

            _strategyMetadata.emergencyModeStartTime = block.timestamp;
            _strategyMetadata.isEmergencyModeInProgress = true;

            // execute emergency mode
            GMXv2Lib.genericInvestmentLogic(
                _strategyData,
                _contracts,
                _callbackDataMap,
                _txParamsWrapperMap,
                investData
            );
        } else {
            // exit emergency mode

            // store vault and strategy calldata for exiting emergency mode
            GMXv2Type.TxParamsWrapper memory txParams = GMXv2Type
                .TxParamsWrapper(
                    TxParams(
                        0,
                        0,
                        address(0),
                        address(0),
                        TxType.EMERGENCY_MODE_DEPOSIT
                    ),
                    TxParams(
                        0,
                        0,
                        address(0),
                        address(0),
                        TxType.EMERGENCY_MODE_DEPOSIT
                    )
                );
            uint256 currentBalance;
            if (asset() == ETH) {
                // convert ETH to WETH to prepare for deposit when exiting emergency mode
                IWETH(WETH).deposit{value: address(this).balance - msg.value}();
                currentBalance = IERC20(WETH).balanceOf(address(this));
            } else {
                currentBalance = IERC20(DEPOSIT_CCY).balanceOf(address(this));
            }

            // create main input params to pass for exiting emergency mode
            GMXv2Type.InvestLogicData memory investData = GMXv2Type
                .InvestLogicData(int256(currentBalance), msg.value, txParams);

            _strategyMetadata.emergencyModeStartTime = block.timestamp;
            _strategyMetadata.isEmergencyModeInProgress = true;

            // exit emergency mode
            GMXv2Lib.genericInvestmentLogic(
                _strategyData,
                _contracts,
                _callbackDataMap,
                _txParamsWrapperMap,
                investData
            );
        }
    }

    ///
    /// NOTE: uses periphery contract to query status()
    /// @inheritdoc IFijaStrategy
    ///
    function status()
        external
        view
        virtual
        override(FijaStrategy, IFijaStrategy)
        returns (string memory)
    {
        return IGMXv2strategyReader(PERIPHERY).status();
    }

    ///
    /// @dev called after a GMX withdrawal execution
    /// @param key the key of the `Withdrawal`
    /// NOTE: only `Controller` access
    ///
    function afterWithdrawalExecution(
        bytes32 key,
        Withdrawal.Props calldata /*withdrawal*/,
        EventUtils.EventLogData calldata /*eventData*/
    ) external controllerOnly {
        try
            GMXv2Lib.withdrawHelper(
                _strategyData,
                _callbackDataMap[key],
                _txParamsWrapperMap[key],
                key
            )
        {} catch {
            GMXv2Lib.errorHandler(_txParamsWrapperMap[key], _strategyMetadata);
        }

        delete _callbackDataMap[key];
        delete _txParamsWrapperMap[key];
    }

    ///
    /// @dev called after a withdrawal cancellation
    /// @param key the key of the `Withdrawal`
    /// NOTE: only `Controller` access
    ///
    function afterWithdrawalCancellation(
        bytes32 key,
        Withdrawal.Props calldata /*withdrawal*/,
        EventUtils.EventLogData calldata /*eventData*/
    ) external controllerOnly {
        GMXv2Lib.errorHandler(_txParamsWrapperMap[key], _strategyMetadata);

        delete _callbackDataMap[key];
        delete _txParamsWrapperMap[key];
    }

    ///
    /// @dev called after a deposit execution
    /// @param key the key of the `Deposit`
    /// NOTE: only `Controller` access
    ///
    function afterDepositExecution(
        bytes32 key,
        GDeposit.Deposit.Props calldata /* deposit*/,
        EventUtils.EventLogData calldata /*eventData*/
    ) external controllerOnly {
        try
            GMXv2Lib.depositHelper(
                _strategyData,
                _txParamsWrapperMap[key],
                _strategyMetadata
            )
        {} catch {
            GMXv2Lib.errorHandler(_txParamsWrapperMap[key], _strategyMetadata);
        }

        delete _callbackDataMap[key];
        delete _txParamsWrapperMap[key];
    }

    ///
    /// @dev called after a deposit cancellation
    /// @param key the key of the `Deposit`
    /// NOTE: only `Controller` access
    ///
    function afterDepositCancellation(
        bytes32 key,
        GDeposit.Deposit.Props calldata /* deposit */,
        EventUtils.EventLogData calldata /*eventData*/
    ) external controllerOnly {
        GMXv2Lib.errorHandler(_txParamsWrapperMap[key], _strategyMetadata);

        delete _callbackDataMap[key];
        delete _txParamsWrapperMap[key];
    }

    ///
    /// @inheritdoc IFlashLoanSimpleReceiver
    ///
    function executeOperation(
        address flashloanAsset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata flashloanParams
    ) external selfAaveOnly(initiator) returns (bool) {
        IPool pool = IPool(GMXv2Keys.AAVE_IPoolAddressesProvider.getPool());

        if (flashloanAsset == DEPOSIT_CCY) {
            _strategyMetadata.flashLoanAmount = amount + premium;
        } else {
            _strategyMetadata.flashLoanAmount = 0;
        }

        // compact data to avoid stack too deep and pass it to executeOperationHelper for processing
        GMXv2Type.FlashloanCallbackWrapper memory flashCbWrapper;
        {
            GMXv2Type.CallbackData memory callbackData;
            GMXv2Type.TxParamsWrapper memory txParamsWrapper;
            GMXv2Type.FlashloanCallbackMetadata memory metadata;

            (callbackData, txParamsWrapper, metadata) = abi.decode(
                flashloanParams,
                (
                    GMXv2Type.CallbackData,
                    GMXv2Type.TxParamsWrapper,
                    GMXv2Type.FlashloanCallbackMetadata
                )
            );

            flashCbWrapper = GMXv2Type.FlashloanCallbackWrapper(
                callbackData,
                txParamsWrapper,
                metadata,
                amount,
                premium,
                callbackData.t - callbackData.Tlong
            );
        }

        GMXv2Lib.executeOperationHelper(
            _strategyData,
            _contracts,
            _callbackDataMap,
            _txParamsWrapperMap,
            _strategyMetadata,
            flashCbWrapper
        );

        if (flashCbWrapper.callbackData.Tlong == 0) {
            // introduce new key as replacement for GMX tx key for storage level mappings,
            // there is no GMX deposit/withdraw tx active here, so GMX tx key is not generated
            _localKey += 1;
            bytes32 key = bytes32(_localKey);

            _callbackDataMap[key] = GMXv2Type.CallbackData(
                flashCbWrapper.callbackData.Tlong,
                flashCbWrapper.callbackData.Lshort,
                flashCbWrapper.callbackData.t
            );

            _txParamsWrapperMap[key] = flashCbWrapper.txParamsWrapper;

            try
                GMXv2Lib.depositHelper(
                    _strategyData,
                    _txParamsWrapperMap[key],
                    _strategyMetadata
                )
            {} catch {
                GMXv2Lib.errorHandler(
                    _txParamsWrapperMap[key],
                    _strategyMetadata
                );
            }

            delete _callbackDataMap[key];
            delete _txParamsWrapperMap[key];
        }

        uint256 payback = amount + premium;
        if (
            flashCbWrapper.callbackData.Lshort < flashCbWrapper.metadata.lshort
        ) {
            // withdraw collateral from AAVE to repay flashloan
            pool.withdraw(DEPOSIT_CCY, payback, address(this));

            // prepare approval to repay flashloan
            SafeERC20.forceApprove(IERC20(DEPOSIT_CCY), address(pool), payback);
        } else if (
            flashCbWrapper.callbackData.Lshort > flashCbWrapper.metadata.lshort
        ) {
            // borrow variable interest secondary ccy from AAVE to repay flashloan
            pool.borrow(SEC_CCY, payback, 2, 0, address(this));

            // prepare approval to repay flashloan
            SafeERC20.forceApprove(IERC20(SEC_CCY), address(pool), payback);
        }

        _strategyMetadata.flashLoanAmount = 0;
        return true;
    }

    ///
    /// @dev sets GMX contract address by key for case when contract address change
    /// @param key contract key
    /// @param value contract address
    ///
    function setContract(
        string memory key,
        address value
    ) external onlyGovernance {
        // validate key exists
        if (_contracts[keccak256(abi.encode(key))] == address(0)) {
            revert FijaSetContractWrongKey();
        }
        _contracts[keccak256(abi.encode(key))] = value;
        // propage change to periphery contract
        IGMXv2strategyReader(PERIPHERY).setContract(key, value);
    }

    ///
    /// @dev helper to calculate governance profit share
    /// @param currentTokenPrice price of the 1 strategy token in asset currency
    ///
    function _profitShare(
        uint256 currentTokenPrice
    ) private view returns (uint256) {
        if (currentTokenPrice <= _strategyMetadata.tokenPriceLastHarvest) {
            return 0;
        }
        uint256 profitShare = ((currentTokenPrice -
            _strategyMetadata.tokenPriceLastHarvest) *
            _strategyMetadata.tokenMintedLastHarvest) /
            (10 ** DEP_CCY_DECIMALS);
        profitShare = (profitShare * 2500) / GMXv2Keys.BASIS_POINTS_DIVISOR;

        return profitShare;
    }

    ///
    /// @dev modifier helper to evaluate if the caller has GMX `Controller` role
    ///
    function _controllerOnly() internal view {
        if (
            !IRoleStore(_contracts[GMXv2Keys.ROLE_STORE]).hasRole(
                msg.sender,
                GMXv2Keys.CONTROLLER
            )
        ) {
            revert FijaCallbackUnauthorized();
        }
    }

    ///
    /// @dev modifier helper to evaluate if the caller is AAVE pool or self
    ///
    function _selfAaveOnly(address initiator) internal view {
        address pool = GMXv2Keys.AAVE_IPoolAddressesProvider.getPool();
        if (
            !(initiator == address(this) &&
                (msg.sender == address(this) || msg.sender == pool))
        ) {
            revert FijaUnauthorizedFlash();
        }
    }

    ///
    /// @dev modifier helper to evaluate if the strategy is in emergency mode
    ///
    function _emergencyModeRestriction() internal view virtual override {
        if (_strategyMetadata.isEmergencyMode) {
            revert FijaInEmergencyMode();
        }
    }

    ///
    /// @dev modifier helper to evaluate if the emergency mode is in progress
    ///
    function _emergencyModeInProgress() internal virtual {
        // check if 5min is elapsed then reset
        if (block.timestamp > _strategyMetadata.emergencyModeStartTime + 300) {
            _strategyMetadata.emergencyModeStartTime = type(uint64).max;
            _strategyMetadata.isEmergencyModeInProgress = false;
        } else {
            if (_strategyMetadata.isEmergencyModeInProgress) {
                revert FijaEmeregencyModeInProgress();
            }
        }
    }

    ///
    /// @dev modifier helper to evaluate if the harvest is in progress
    ///
    function _harvestInProgress() internal virtual {
        // check if 5min is elapsed then reset
        if (block.timestamp > _strategyMetadata.harvestModeStartTime + 300) {
            _strategyMetadata.harvestModeStartTime = type(uint64).max;
            _strategyMetadata.isHarvestInProgress = false;
        } else {
            if (_strategyMetadata.isHarvestInProgress) {
                revert FijaHarvestInProgress();
            }
        }
    }

    ///
    /// @dev modifier helper to evaluate if the rebalance is in progress
    ///
    function _rebalanceInProgress() internal virtual {
        // check if 5min is elapsed then reset
        if (block.timestamp > _strategyMetadata.rebalanceModeStartTime + 300) {
            _strategyMetadata.harvestModeStartTime = type(uint64).max;
            _strategyMetadata.isRebalanceInProgress = false;
        } else {
            if (_strategyMetadata.isRebalanceInProgress) {
                revert FijaRebalanceInProgress();
            }
        }
    }

    ///
    /// @dev required method by AAVE to support flashloans
    /// @return IPoolAddressesProvider
    ///
    function ADDRESSES_PROVIDER()
        external
        pure
        virtual
        override
        returns (IPoolAddressesProvider)
    {
        return GMXv2Keys.AAVE_IPoolAddressesProvider;
    }

    ///
    /// @dev required method by AAVE to support flashloans
    /// @return IPool
    ///
    function POOL() external view virtual override returns (IPool) {
        return IPool(GMXv2Keys.AAVE_IPoolAddressesProvider.getPool());
    }

    receive() external payable override {}
}

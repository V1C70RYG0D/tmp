// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@aave/core-v3/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@aave/periphery-v3/contracts/misc/interfaces/IWETH.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "../../protocols/gmxv2/IExchangeRouter.sol";
import "../../protocols/gmxv2/IReader.sol";
import "../../protocols/gmxv2/Withdrawal.sol";

import "../../base/FijaStrategyEvents.sol";

import "../../interfaces/IFijaVault2Txn.sol";
import "../../interfaces/IFijaStrategy.sol";
import "./IGMXv2strategyReader.sol";

import "../../base/errors.sol";

import "./GMXv2Type.sol";
import "./GMXv2Keys.sol";
import "./GMXv2Helpers.sol";

///
/// @title Main GMXv2 library
/// @notice used to offload core strategy contract and limit it's size
/// @dev supports all main functions for strategy investment procedures,
/// creating GMX deposits and withdrawals and handling GMX and AAVE callbacks
///
library GMXv2Lib {
    ///
    /// @dev entry for strategy's interaction with GMX protocol,
    /// main function is to route into deposit or withdraw branch based on calculated Tlong
    /// @param strategyData holds reference to strategy data - GMXv2Type.StrategyData
    /// @param contracts mapping holding GMX contract references
    /// @param callbackDataMap holds by tx key, references to data required in 2nd tx for GMX callbacks - GMXv2Type.CallbackData
    /// @param txParamsWrapperMap holds by tx key, references to vault and strategy calldata - GMXv2Type.TxParamsWrapper
    /// @param investLogicData holds values for strategy investment - GMXv2Type.InvestLogicData
    ///
    function genericInvestmentLogic(
        GMXv2Type.StrategyData storage strategyData,
        mapping(bytes32 => address) storage contracts,
        mapping(bytes32 => GMXv2Type.CallbackData) storage callbackDataMap,
        mapping(bytes32 => GMXv2Type.TxParamsWrapper)
            storage txParamsWrapperMap,
        GMXv2Type.InvestLogicData memory investLogicData
    ) external {
        IGMXv2strategyReader.TlongLshort memory p = IGMXv2strategyReader(
            strategyData.PERIPHERY
        ).getTlongLshort(investLogicData.t);

        // withdraw assets from GMX
        if (p.Tlong < 0) {
            Withdrawal.CreateWithdrawalParams memory withdrawReqParams;
            uint256 GMtokens;
            {
                IGMXv2strategyReader.WithdrawCalcParams
                    memory c = IGMXv2strategyReader(strategyData.PERIPHERY)
                        .withdrawCalcParams();

                // calculate GM token amount to withdraw and unwind to Tlong
                uint256 GMtokensTemp = ((c.eGsellShort * c.rShort) /
                    GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION);

                GMtokensTemp = GMXv2Helpers.adjustForDecimals(
                    GMtokensTemp,
                    strategyData.SEC_CCY_DECIMALS,
                    strategyData.DEP_CCY_DECIMALS
                );
                GMtokens =
                    (uint256(-p.Tlong) *
                        (10 ** strategyData.DEP_CCY_DECIMALS)) /
                    (c.eGsellLong + GMtokensTemp);

                GMtokens = GMXv2Helpers.adjustForDecimals(
                    GMtokens,
                    strategyData.DEP_CCY_DECIMALS,
                    GMXv2Keys.GM_TOKEN_DECIMALS
                );

                // TODO do we include slippage here and for what exactly for uniswap or gmx swap? or both
                GMtokens =
                    (GMtokens *
                        (GMXv2Keys.BASIS_POINTS_DIVISOR + GMXv2Keys.SLIPPAGE)) /
                    GMXv2Keys.BASIS_POINTS_DIVISOR;

                uint256 minLongTokenAmount;
                uint256 minShortTokenAmount;
                {
                    // calculate market components we should receive when we burn GM tokens
                    // deposit ccy + secondary ccy
                    minLongTokenAmount =
                        (GMtokens * c.eGsellLong) /
                        GMXv2Keys.GM_TOKEN_PRECISION;
                    minShortTokenAmount =
                        (GMtokens * c.eGsellShort) /
                        GMXv2Keys.GM_TOKEN_PRECISION;

                    Market.Props memory market = IReader(
                        contracts[GMXv2Keys.READER]
                    ).getMarket(
                            contracts[GMXv2Keys.DATASTORE],
                            strategyData.GM_POOL
                        );

                    if (market.longToken != strategyData.DEPOSIT_CCY) {
                        uint256 temp = minLongTokenAmount;
                        minLongTokenAmount = minShortTokenAmount;
                        minShortTokenAmount = temp;
                    }
                }
                // create withdraw order
                withdrawReqParams = Withdrawal.CreateWithdrawalParams({
                    receiver: address(this),
                    callbackContract: address(this),
                    uiFeeReceiver: address(0),
                    market: strategyData.GM_POOL,
                    longTokenSwapPath: new address[](0),
                    shortTokenSwapPath: new address[](0),
                    minLongTokenAmount: minLongTokenAmount,
                    minShortTokenAmount: minShortTokenAmount,
                    shouldUnwrapNativeToken: false,
                    executionFee: investLogicData.executionFee,
                    callbackGasLimit: IGMXv2strategyReader(
                        strategyData.PERIPHERY
                    ).callbackGasLimit(
                            investLogicData
                                .txParamsWrapper
                                .strategyParams
                                .txType
                        )
                });
            }
            IExchangeRouter exchangeRouter = IExchangeRouter(
                contracts[GMXv2Keys.EXCHANGE_ROUTER]
            );
            address withdrawVault = contracts[GMXv2Keys.WITHDRAW_VAULT];
            {
                // send execution fee to GMX vault
                exchangeRouter.sendWnt{value: investLogicData.executionFee}(
                    withdrawVault,
                    investLogicData.executionFee
                );

                SafeERC20.forceApprove(
                    IERC20(strategyData.GM_POOL),
                    contracts[GMXv2Keys.ROUTER],
                    GMtokens
                );
                uint256 gmTokensLeft = IERC20(strategyData.GM_POOL).balanceOf(
                    address(this)
                );
                if (gmTokensLeft < GMtokens) {
                    GMtokens = gmTokensLeft;
                }
            }
            // send GM tokens to GMX
            exchangeRouter.sendTokens(
                strategyData.GM_POOL,
                withdrawVault,
                GMtokens
            );
            // triggers callback in 2nd tx when withdraw completes
            bytes32 key = exchangeRouter.createWithdrawal(withdrawReqParams);

            // store calculated params for callbacks
            callbackDataMap[key] = GMXv2Type.CallbackData(
                p.Tlong,
                p.Lshort,
                investLogicData.t
            );

            // store strategy and vault calldata for callbacks
            txParamsWrapperMap[key] = investLogicData.txParamsWrapper;
        } else {
            // prepare to deposit assets to GMX
            GMXv2Type.CallbackData memory callbackData = GMXv2Type.CallbackData(
                p.Tlong,
                p.Lshort,
                investLogicData.t
            );

            _executeFlashloan(
                strategyData,
                callbackData,
                investLogicData.txParamsWrapper,
                investLogicData.executionFee,
                ""
            );
        }
    }

    ///
    /// @dev helper to offload flashloan callback
    /// @param strategyData holds reference to strategy data - GMXv2Type.StrategyData
    /// @param contracts mapping holding GMX contract references
    /// @param callbackDataMap holds by tx key, references to data required in 2nd tx for GMX callbacks - GMXv2Type.CallbackData
    /// @param txParamsWrapperMap holds by tx key, references to vault and strategy calldata - GMXv2Type.TxParamsWrapper
    /// @param strategyMetadata holds reference to strategy metadata - GMXv2Type.StrategyMetadata
    /// @param flashCbWrapper container used by core strategy to pass necessary values to it's helper - GMXv2Type.FlashloanCallbackWrapper
    ///
    function executeOperationHelper(
        GMXv2Type.StrategyData storage strategyData,
        mapping(bytes32 => address) storage contracts,
        mapping(bytes32 => GMXv2Type.CallbackData) storage callbackDataMap,
        mapping(bytes32 => GMXv2Type.TxParamsWrapper)
            storage txParamsWrapperMap,
        GMXv2Type.StrategyMetadata storage strategyMetadata,
        GMXv2Type.FlashloanCallbackWrapper memory flashCbWrapper
    ) external {
        IPool pool = IPool(GMXv2Keys.AAVE_IPoolAddressesProvider.getPool());

        if (flashCbWrapper.Tshort > 0) {
            SafeERC20.forceApprove(
                IERC20(strategyData.DEPOSIT_CCY),
                address(pool),
                uint256(flashCbWrapper.Tshort)
            );

            // deposit collateral to AAVE
            pool.supply(
                strategyData.DEPOSIT_CCY,
                uint256(flashCbWrapper.Tshort),
                address(this),
                0
            );
        }
        if (
            flashCbWrapper.callbackData.Lshort < flashCbWrapper.metadata.lshort
        ) {
            // calculate minOut for flashloan to secondary ccy swap
            uint256 minOutSec = (flashCbWrapper.amount *
                GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION) /
                IGMXv2strategyReader(strategyData.PERIPHERY).r_short();

            minOutSec = GMXv2Helpers.adjustForDecimals(
                minOutSec,
                strategyData.DEP_CCY_DECIMALS,
                strategyData.SEC_CCY_DECIMALS
            );

            minOutSec =
                (minOutSec *
                    (GMXv2Keys.BASIS_POINTS_DIVISOR - GMXv2Keys.SLIPPAGE)) /
                GMXv2Keys.BASIS_POINTS_DIVISOR;

            ISwapRouter.ExactInputSingleParams memory swapInput = ISwapRouter
                .ExactInputSingleParams(
                    strategyData.DEPOSIT_CCY,
                    strategyData.SEC_CCY,
                    IUniswapV3Pool(strategyData.UNISWAP_DEP_SEC_POOL).fee(),
                    address(this),
                    block.timestamp + 120,
                    flashCbWrapper.amount,
                    minOutSec,
                    0
                );

            SafeERC20.forceApprove(
                IERC20(strategyData.DEPOSIT_CCY),
                address(GMXv2Keys.Uniswap_ISwapRouter),
                flashCbWrapper.amount
            );
            {
                uint256 beforeSwap = IERC20(strategyData.SEC_CCY).balanceOf(
                    address(this)
                );

                // swap flashloan to secondary ccy
                GMXv2Keys.Uniswap_ISwapRouter.exactInputSingle(swapInput);

                uint256 afterSwap = IERC20(strategyData.SEC_CCY).balanceOf(
                    address(this)
                );

                uint256 diff = afterSwap - beforeSwap;

                SafeERC20.forceApprove(
                    IERC20(strategyData.SEC_CCY),
                    address(pool),
                    diff
                );

                // Note that we may be repaying more loan here than we actually have --
                // however Aave will only takes repayment up to the loan value,
                // and the remaining SEC_CCY will remain on the strategy contract

                // repay (part) of AAVE loan
                pool.repay(strategyData.SEC_CCY, diff, 2, address(this));
            }
        } else if (
            flashCbWrapper.callbackData.Lshort > flashCbWrapper.metadata.lshort
        ) {
            // include all secondary ccy we have on strategy
            uint256 secCcyBalance = IERC20(strategyData.SEC_CCY).balanceOf(
                address(this)
            );
            // calculate minOut for flashloan to deposit ccy swap
            uint256 minOutDep = (secCcyBalance *
                IGMXv2strategyReader(strategyData.PERIPHERY).r_short()) /
                GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION;

            minOutDep = GMXv2Helpers.adjustForDecimals(
                minOutDep,
                strategyData.SEC_CCY_DECIMALS,
                strategyData.DEP_CCY_DECIMALS
            );

            minOutDep =
                (minOutDep *
                    (GMXv2Keys.BASIS_POINTS_DIVISOR - GMXv2Keys.SLIPPAGE)) /
                GMXv2Keys.BASIS_POINTS_DIVISOR;

            ISwapRouter.ExactInputSingleParams memory swapInput = ISwapRouter
                .ExactInputSingleParams(
                    strategyData.SEC_CCY,
                    strategyData.DEPOSIT_CCY,
                    IUniswapV3Pool(strategyData.UNISWAP_DEP_SEC_POOL).fee(),
                    address(this),
                    block.timestamp + 120,
                    secCcyBalance,
                    minOutDep,
                    0
                );

            SafeERC20.forceApprove(
                IERC20(strategyData.SEC_CCY),
                address(GMXv2Keys.Uniswap_ISwapRouter),
                secCcyBalance
            );
            {
                // swap secondary to deposit ccy
                GMXv2Keys.Uniswap_ISwapRouter.exactInputSingle(swapInput);

                // TODO we do not clear this anywhere?
                strategyMetadata.flashLoanAmount =
                    flashCbWrapper.amount +
                    flashCbWrapper.premium;

                uint256 collateral = (flashCbWrapper.amount *
                    IGMXv2strategyReader(strategyData.PERIPHERY).r_short()) /
                    GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION;

                collateral = GMXv2Helpers.adjustForDecimals(
                    collateral,
                    strategyData.SEC_CCY_DECIMALS,
                    strategyData.DEP_CCY_DECIMALS
                );

                collateral =
                    (collateral *
                        (GMXv2Keys.BASIS_POINTS_DIVISOR - GMXv2Keys.SLIPPAGE)) /
                    GMXv2Keys.BASIS_POINTS_DIVISOR;

                SafeERC20.forceApprove(
                    IERC20(strategyData.DEPOSIT_CCY),
                    address(pool),
                    collateral
                );

                // deposit collateral to AAVE
                pool.supply(
                    strategyData.DEPOSIT_CCY,
                    collateral,
                    address(this),
                    0
                );
            }
        }

        if (flashCbWrapper.Tshort < 0) {
            uint256 loan;
            uint256 cShort = IGMXv2strategyReader(strategyData.PERIPHERY)
                .c_short();
            uint256 Tshort = uint256(flashCbWrapper.Tshort * -1);

            if (
                flashCbWrapper.callbackData.Lshort <
                flashCbWrapper.metadata.lshort
            ) {
                // loan is in deposit ccy, include loan in collateral reduction calculation
                loan = flashCbWrapper.amount + flashCbWrapper.premium;
            }

            // remove collateral from AAVE
            if (cShort < loan + Tshort) {
                pool.withdraw(
                    strategyData.DEPOSIT_CCY,
                    cShort - loan,
                    address(this)
                );
            } else {
                pool.withdraw(strategyData.DEPOSIT_CCY, Tshort, address(this));
            }
        }
        if (flashCbWrapper.callbackData.Tlong < 0) {
            // exchange assets and tokens between strategy and vault
            _settle(
                strategyData,
                txParamsWrapperMap[flashCbWrapper.metadata.key],
                strategyMetadata
            );

            delete callbackDataMap[flashCbWrapper.metadata.key];
            delete txParamsWrapperMap[flashCbWrapper.metadata.key];
        } else if (flashCbWrapper.callbackData.Tlong > 0) {
            // deposit assets to GMX
            uint256 _Tlong = uint256(flashCbWrapper.callbackData.Tlong);

            Deposit.CreateDepositParams memory depositReqParams;
            {
                uint256 minGMOut = (_Tlong *
                    IGMXv2strategyReader(strategyData.PERIPHERY).e_gbuy()) /
                    (10 ** strategyData.DEP_CCY_DECIMALS);

                minGMOut =
                    (minGMOut *
                        (GMXv2Keys.BASIS_POINTS_DIVISOR - GMXv2Keys.SLIPPAGE)) /
                    GMXv2Keys.BASIS_POINTS_DIVISOR;

                Market.Props memory market = IReader(
                    contracts[GMXv2Keys.READER]
                ).getMarket(
                        contracts[GMXv2Keys.DATASTORE],
                        strategyData.GM_POOL
                    );

                uint256 initialLongTokenAmount;
                uint256 initialShortTokenAmount;

                // TODO is t here always > 0
                // do we deposit here t or T_long
                if (market.longToken == strategyData.DEPOSIT_CCY) {
                    initialLongTokenAmount = uint256(
                        flashCbWrapper.callbackData.t
                    );
                } else {
                    initialShortTokenAmount = uint256(
                        flashCbWrapper.callbackData.t
                    );
                }

                // create deposit order
                depositReqParams = Deposit.CreateDepositParams({
                    receiver: address(this),
                    callbackContract: address(this),
                    uiFeeReceiver: address(0),
                    market: strategyData.GM_POOL,
                    initialLongToken: market.longToken,
                    initialShortToken: market.shortToken,
                    longTokenSwapPath: new address[](0),
                    shortTokenSwapPath: new address[](0),
                    minMarketTokens: minGMOut,
                    shouldUnwrapNativeToken: IERC4626(address(this)).asset() ==
                        GMXv2Keys.ETH
                        ? true
                        : false, // TODO check for pure ETH what to do if it is cancelled
                    executionFee: flashCbWrapper.metadata.executionFee,
                    callbackGasLimit: IGMXv2strategyReader(
                        strategyData.PERIPHERY
                    ).callbackGasLimit(
                            flashCbWrapper.txParamsWrapper.strategyParams.txType
                        )
                });
            }

            IExchangeRouter exchangeRouter = IExchangeRouter(
                contracts[GMXv2Keys.EXCHANGE_ROUTER]
            );
            {
                address depositVault = contracts[GMXv2Keys.DEPOSIT_VAULT];

                // send execution fee to GMX
                exchangeRouter.sendWnt{
                    value: flashCbWrapper.metadata.executionFee
                }(depositVault, flashCbWrapper.metadata.executionFee);

                SafeERC20.forceApprove(
                    IERC20(strategyData.DEPOSIT_CCY),
                    contracts[GMXv2Keys.ROUTER],
                    _Tlong
                );

                // send deposit ccy to GMX
                exchangeRouter.sendTokens(
                    strategyData.DEPOSIT_CCY,
                    depositVault,
                    _Tlong
                );
            }
            // send deposit order
            bytes32 key = exchangeRouter.createDeposit(depositReqParams);

            // store calculated input params for callbacks
            callbackDataMap[key] = GMXv2Type.CallbackData(
                flashCbWrapper.callbackData.Tlong,
                flashCbWrapper.callbackData.Lshort,
                flashCbWrapper.callbackData.t
            );
            // store strategy and vault calldata for callbacks
            txParamsWrapperMap[key] = flashCbWrapper.txParamsWrapper;
        }
    }

    ///
    /// @dev helper for handling GMX deposit callback and special case when Tlong == 0
    /// @param strategyData holds reference to strategy data - GMXv2Type.StrategyData
    /// @param txParamsWrapper holds reference to vault and strategy calldata - GMXv2Type.TxParamsWrapper
    /// @param strategyMetadata holds reference to strategy metadata - GMXv2Type.StrategyMetadata
    ///
    function depositHelper(
        GMXv2Type.StrategyData storage strategyData,
        GMXv2Type.TxParamsWrapper storage txParamsWrapper,
        GMXv2Type.StrategyMetadata storage strategyMetadata
    ) external {
        _settle(strategyData, txParamsWrapper, strategyMetadata);
    }

    ///
    /// @dev handles GMX withdraw callback processing - flashloan execution, AAVE collateral and borrow operations,
    /// triggers asset and token exchange between strategy and vault, signals vault withdraw/redeem operation is done on
    /// strategy level
    /// @param strategyData holds reference to strategy data - GMXv2Type.StrategyData
    /// @param callbackData holds reference to data required in 2nd tx for GMX callbacks - GMXv2Type.CallbackData
    /// @param txParamsWrapper holds reference to vault and strategy calldata - GMXv2Type.TxParamsWrapper
    /// @param key GMX tx unique key, used to track deposit/withdraw requests across 2 tx
    ///
    function withdrawHelper(
        GMXv2Type.StrategyData storage strategyData,
        GMXv2Type.CallbackData storage callbackData,
        GMXv2Type.TxParamsWrapper storage txParamsWrapper,
        bytes32 key
    ) external {
        // include all secondary ccy on strategy and convert it to deposit ccy
        uint256 totalSecCcy = IERC20(strategyData.SEC_CCY).balanceOf(
            address(this)
        );

        uint256 minOut = (totalSecCcy *
            IGMXv2strategyReader(strategyData.PERIPHERY).r_short()) /
            GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION;

        minOut = GMXv2Helpers.adjustForDecimals(
            minOut,
            strategyData.SEC_CCY_DECIMALS,
            strategyData.DEP_CCY_DECIMALS
        );

        minOut =
            (minOut * (GMXv2Keys.BASIS_POINTS_DIVISOR - GMXv2Keys.SLIPPAGE)) /
            GMXv2Keys.BASIS_POINTS_DIVISOR;

        ISwapRouter.ExactInputSingleParams memory swapInput = ISwapRouter
            .ExactInputSingleParams(
                strategyData.SEC_CCY,
                strategyData.DEPOSIT_CCY,
                IUniswapV3Pool(strategyData.UNISWAP_DEP_SEC_POOL).fee(),
                address(this),
                block.timestamp + 120,
                totalSecCcy,
                minOut,
                0
            );

        SafeERC20.forceApprove(
            IERC20(strategyData.SEC_CCY),
            address(GMXv2Keys.Uniswap_ISwapRouter),
            IERC20(strategyData.SEC_CCY).balanceOf(address(this))
        );

        // swap secondary currency to deposit currency
        GMXv2Keys.Uniswap_ISwapRouter.exactInputSingle(swapInput);

        _executeFlashloan(strategyData, callbackData, txParamsWrapper, 0, key);
    }

    ///
    /// @dev handles errors generated by strategy and GMX cancellation callbacks,
    /// executes vault callbacks to notify and resets contract level flags
    /// @param txParamsWrapper holds reference to vault and strategy calldata - GMXv2Type.TxParamsWrapper
    /// @param strategyMetadata holds reference to strategy metadata - GMXv2Type.StrategyMetadata
    ///
    function errorHandler(
        GMXv2Type.TxParamsWrapper storage txParamsWrapper,
        GMXv2Type.StrategyMetadata storage strategyMetadata
    ) external {
        TxParams memory strategyParams = txParamsWrapper.strategyParams;
        TxParams memory vaultParams = txParamsWrapper.vaultParams;
        if (strategyParams.txType == TxType.REDEEM) {
            IFijaVault2Txn(strategyParams.owner).afterRedeem(
                vaultParams.tokens,
                vaultParams.receiver,
                vaultParams.owner,
                false
            );
        } else if (strategyParams.txType == TxType.WITHDRAW) {
            IFijaVault2Txn(strategyParams.owner).afterWithdraw(
                vaultParams.assets,
                vaultParams.receiver,
                vaultParams.owner,
                false
            );
        } else if (strategyParams.txType == TxType.DEPOSIT) {
            IFijaVault2Txn(strategyParams.receiver).afterDeposit(
                vaultParams.assets,
                vaultParams.tokens,
                vaultParams.receiver,
                false
            );
        } else if (strategyParams.txType == TxType.HARVEST) {
            strategyMetadata.harvestModeStartTime = type(uint64).max;
            strategyMetadata.isHarvestInProgress = false;
        } else if (
            strategyParams.txType == TxType.EMERGENCY_MODE_WITHDRAW ||
            strategyParams.txType == TxType.EMERGENCY_MODE_DEPOSIT
        ) {
            strategyMetadata.emergencyModeStartTime = type(uint64).max;
            strategyMetadata.isEmergencyModeInProgress = false;
        } else if (strategyParams.txType == TxType.REBALANCE) {
            strategyMetadata.rebalanceModeStartTime = type(uint64).max;
            strategyMetadata.isRebalanceInProgress = false;
        }
    }

    ///
    /// @dev converts all native ccy to deposit ccy
    /// @param strategyData holds reference to strategy data - GMXv2Type.StrategyData
    ///
    function convertNativeToDeposit(
        GMXv2Type.StrategyData storage strategyData
    ) external {
        if (
            strategyData.DEPOSIT_CCY != strategyData.WETH &&
            strategyData.SEC_CCY != strategyData.WETH
        ) {
            uint256 nativeTokenBalance = address(this).balance - msg.value;
            if (nativeTokenBalance > 0) {
                IWETH(strategyData.WETH).deposit{value: nativeTokenBalance}();

                uint256 weth = IERC20(strategyData.WETH).balanceOf(
                    address(this)
                );

                uint256 minOut = (weth *
                    IGMXv2strategyReader(strategyData.PERIPHERY)
                        .nativeDepositRate()) /
                    GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION;

                minOut = GMXv2Helpers.adjustForDecimals(
                    minOut,
                    18,
                    strategyData.DEP_CCY_DECIMALS
                );

                minOut =
                    (minOut *
                        (GMXv2Keys.BASIS_POINTS_DIVISOR - GMXv2Keys.SLIPPAGE)) /
                    GMXv2Keys.BASIS_POINTS_DIVISOR;

                ISwapRouter.ExactInputSingleParams
                    memory swapInput = ISwapRouter.ExactInputSingleParams(
                        strategyData.WETH,
                        strategyData.DEPOSIT_CCY,
                        IUniswapV3Pool(strategyData.UNISWAP_NATIVE_DEP_POOL)
                            .fee(),
                        address(this),
                        block.timestamp + 120,
                        weth,
                        minOut,
                        0
                    );

                SafeERC20.forceApprove(
                    IERC20(strategyData.WETH),
                    address(GMXv2Keys.Uniswap_ISwapRouter),
                    weth
                );

                // swap WETH to deposit ccy
                GMXv2Keys.Uniswap_ISwapRouter.exactInputSingle(swapInput);
            }
        }
    }

    ///
    /// @dev helper to prepare and execute AAVE flashloan
    /// @param strategyData holds reference to strategy data - GMXv2Type.StrategyData
    /// @param callbackData holds reference to data required in 2nd tx for GMX callbacks - GMXv2Type.CallbackData
    /// @param txParamsWrapper holds reference to vault and strategy calldata - GMXv2Type.TxParamsWrapper
    /// @param executionFee GMX keeper execution fee
    /// @param key GMX tx unique key, used to track deposit/withdraw requests across 2 tx
    ///
    function _executeFlashloan(
        GMXv2Type.StrategyData storage strategyData,
        GMXv2Type.CallbackData memory callbackData,
        GMXv2Type.TxParamsWrapper memory txParamsWrapper,
        uint256 executionFee,
        bytes32 key
    ) internal {
        uint256 Lshort = callbackData.Lshort;
        uint256 lshort = IGMXv2strategyReader(strategyData.PERIPHERY).l_short();

        IPool pool = IPool(GMXv2Keys.AAVE_IPoolAddressesProvider.getPool());

        GMXv2Type.FlashloanCallbackMetadata memory metadata = GMXv2Type
            .FlashloanCallbackMetadata(executionFee, key, lshort);

        // prepare necessary data to be available in flashloan callback
        bytes memory encodedData = abi.encode(
            callbackData,
            txParamsWrapper,
            metadata
        );

        if (Lshort < lshort) {
            // calculate flashloan needed to reduce AAVE loan
            uint256 depositCCyForFlash = ((lshort - Lshort) *
                IGMXv2strategyReader(strategyData.PERIPHERY).r_short()) /
                GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION;

            depositCCyForFlash = GMXv2Helpers.adjustForDecimals(
                depositCCyForFlash,
                strategyData.SEC_CCY_DECIMALS,
                strategyData.DEP_CCY_DECIMALS
            );

            depositCCyForFlash =
                (depositCCyForFlash *
                    (GMXv2Keys.BASIS_POINTS_DIVISOR + GMXv2Keys.SLIPPAGE)) /
                GMXv2Keys.BASIS_POINTS_DIVISOR;

            pool.flashLoanSimple(
                address(this),
                strategyData.DEPOSIT_CCY,
                depositCCyForFlash,
                encodedData,
                0
            );
        } else if (Lshort > lshort) {
            // calculate flashloan needed to increase AAVE loan
            pool.flashLoanSimple(
                address(this),
                strategyData.SEC_CCY,
                ((Lshort - lshort) *
                    (GMXv2Keys.BASIS_POINTS_DIVISOR -
                        IGMXv2strategyReader(strategyData.PERIPHERY)
                            .g_flash())) / GMXv2Keys.BASIS_POINTS_DIVISOR,
                encodedData,
                0
            );
        } else {
            IFlashLoanSimpleReceiver(address(this)).executeOperation(
                address(0),
                0,
                0,
                address(this),
                encodedData
            );
        }
    }

    ///
    /// @dev executes assets and strategy tokens exchange between vault and strategy, invokes vault callbacks
    /// to signal exchange is done on strategy level so vault can proceed to settle with caller
    /// @param strategyData holds reference to strategy data - GMXv2Type.StrategyData
    /// @param txParamsWrapper holds reference to vault and strategy calldata - GMXv2Type.TxParamsWrapper
    /// @param strategyMetadata holds reference to strategy metadata - GMXv2Type.StrategyMetadata
    ///
    function _settle(
        GMXv2Type.StrategyData storage strategyData,
        GMXv2Type.TxParamsWrapper storage txParamsWrapper,
        GMXv2Type.StrategyMetadata storage strategyMetadata
    ) internal {
        TxParams memory strategyParams = txParamsWrapper.strategyParams;
        TxParams memory vaultParams = txParamsWrapper.vaultParams;

        if (strategyParams.txType == TxType.WITHDRAW) {
            // send assets to vault, burn tokens

            if (IERC4626(address(this)).asset() == GMXv2Keys.ETH) {
                // convert WETH to native ETH for withdrawal
                IWETH(strategyData.WETH).withdraw(
                    IERC20(strategyData.WETH).balanceOf(address(this))
                );
            }

            // settle assets and strategy tokens between strategy and vault
            IERC4626(address(this)).withdraw(
                strategyParams.assets,
                strategyParams.receiver,
                strategyParams.owner
            );

            // invoke vault callback so it can proceed to settle with it's caller
            IFijaVault2Txn(strategyParams.owner).afterWithdraw(
                vaultParams.assets,
                vaultParams.receiver,
                vaultParams.owner,
                true
            );
        } else if (strategyParams.txType == TxType.REDEEM) {
            // send assets to vault, burn tokens

            if (IERC4626(address(this)).asset() == GMXv2Keys.ETH) {
                // convert WETH to native ETH for redeem
                IWETH(strategyData.WETH).withdraw(
                    IERC20(strategyData.WETH).balanceOf(address(this))
                );
            }

            // settle assets and strategy tokens between strategy and vault
            IERC4626(address(this)).redeem(
                strategyParams.tokens,
                strategyParams.receiver,
                strategyParams.owner
            );

            // invoke vault callback so it can proceed to settle with it's caller
            IFijaVault2Txn(strategyParams.owner).afterRedeem(
                vaultParams.tokens,
                vaultParams.receiver,
                vaultParams.owner,
                true
            );
        } else if (strategyParams.txType == TxType.HARVEST) {
            // harvest completed, transfer to governance
            strategyMetadata.lastHarvestTime = block.timestamp;

            // using vault `GMXv2Type.TxParams.assets` to fetch currentTokenPrice assigned in 1tx for harvest call
            uint256 currentTokenPrice = vaultParams.assets;

            // using vault `GMXv2Type.TxParams.tokens` to fetch supply assigned in 1tx for harvest call
            uint256 supply = vaultParams.tokens;

            // using strategy `GMXv2Type.TxParams.assets` to fetch profitShare assigned in 1tx for harvest call
            uint256 profitShare = strategyParams.assets;

            strategyMetadata.tokenPriceLastHarvest = currentTokenPrice;
            strategyMetadata.tokenMintedLastHarvest = supply;

            if (IERC4626(address(this)).asset() == GMXv2Keys.ETH) {
                // convert WETH to native ETH for sending to governance
                IWETH(strategyData.WETH).withdraw(
                    IERC20(strategyData.WETH).balanceOf(address(this))
                );

                // send profit share to governance
                (bool success, ) = payable(
                    IFijaStrategy(address(this)).governance()
                ).call{value: profitShare}("");

                if (!success) {
                    revert TransferFailed();
                }
            } else {
                // send profit share to governance
                IERC20(strategyData.DEPOSIT_CCY).transfer(
                    IFijaStrategy(address(this)).governance(),
                    profitShare
                );
            }

            emit FijaStrategyEvents.Harvest(
                block.timestamp,
                4 * profitShare,
                profitShare,
                IERC4626(address(this)).asset(),
                ""
            );

            // reset flags
            strategyMetadata.harvestModeStartTime = type(uint64).max;
            strategyMetadata.isHarvestInProgress = false;
        } else if (strategyParams.txType == TxType.EMERGENCY_MODE_WITHDRAW) {
            // reset flags
            strategyMetadata.emergencyModeStartTime = type(uint64).max;
            strategyMetadata.isEmergencyModeInProgress = false;

            emit FijaStrategyEvents.EmergencyMode(block.timestamp, true);
        } else if (strategyParams.txType == TxType.EMERGENCY_MODE_DEPOSIT) {
            // end of emergency mode
            strategyMetadata.isEmergencyMode = false;
            // reset flags
            strategyMetadata.emergencyModeStartTime = type(uint64).max;
            strategyMetadata.isEmergencyModeInProgress = false;

            emit FijaStrategyEvents.EmergencyMode(block.timestamp, false);
        } else if (strategyParams.txType == TxType.DEPOSIT) {
            // no action
        } else if (strategyParams.txType == TxType.REBALANCE) {
            // reset flags
            strategyMetadata.rebalanceModeStartTime = type(uint64).max;
            strategyMetadata.isRebalanceInProgress = false;

            string memory imbalance = string(
                abi.encodePacked(
                    "|imbalanceBps=",
                    Strings.toString(
                        IGMXv2strategyReader(strategyData.PERIPHERY)
                            .imbalanceBps()
                    )
                )
            );
            emit FijaStrategyEvents.Rebalance(block.timestamp, imbalance);
        }
    }
}

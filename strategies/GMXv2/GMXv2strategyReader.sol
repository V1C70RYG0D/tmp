// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/utils/Strings.sol";

import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "../../protocols/gmxv2/IDatastore.sol";
import "../../protocols/gmxv2/IReader.sol";
import "../../protocols/gmxv2/Precision.sol";

import "../../interfaces/IERC4626.sol";

import "./GMXv2strategyBase.sol";
import "./IGMXv2strategyReader.sol";

import "./GMXv2Helpers.sol";

import "../../base/errors.sol";
import "./errors.sol";

import "../../base/types.sol";

///
/// @title GMXv2StrategyReader
/// @author Fija
/// @notice view methods to support core strategy contract operations
/// @dev offloads size and heavy view methods for off-chain usage
///
contract GMXv2strategyReader is IGMXv2strategyReader, GMXv2strategyBase {
    ///
    /// @dev underlying token address
    ///
    address internal immutable _asset;

    ///
    /// @dev reference to main strategy contract address
    ///
    address internal immutable CORE_STRATEGY;

    ///
    /// @dev gas limit for GMX deposit use-case
    ///
    uint256 internal constant CALLBACK_GAS_LIMIT_DEPOSIT = 65_000;

    ///
    /// @dev gas limit for GMX withdrawal use-case
    ///
    uint256 internal constant CALLBACK_GAS_LIMIT_WITHDRAWAL = 2_000_000;

    ///
    /// @dev gas limit for GMX enter emergency mode use-case
    ///
    uint256 internal constant CALLBACK_GAS_LIMIT_EME_ENTER = 950_000;

    ///
    /// @dev gas limit for GMX exit emergency mode use-case
    ///
    uint256 internal constant CALLBACK_GAS_LIMIT_EME_EXIT = 70_000;

    ///
    /// @dev gas limit for GMX rebalance mode use-case
    ///
    uint256 internal constant CALLBACK_GAS_LIMIT_REBALANCE = 1_200_000;

    ///
    /// @dev gas limit for GMX harvest mode use-case
    ///
    uint256 internal constant CALLBACK_GAS_LIMIT_HARVEST = 1_050_000;

    constructor(
        ConstructorData memory data_,
        address coreStrategy_,
        address asset_
    ) GMXv2strategyBase(data_, asset_) {
        _asset = asset_;
        CORE_STRATEGY = coreStrategy_;
    }

    ///
    /// @inheritdoc IGMXv2strategyReader
    ///
    function getTlongLshort(
        int256 t
    ) external view returns (IGMXv2strategyReader.TlongLshort memory) {
        int256 Tlong = _T_long(t);
        uint256 Lshort = _L_short(t, Tlong);

        IGMXv2strategyReader.TlongLshort memory tuple = IGMXv2strategyReader
            .TlongLshort(Tlong, Lshort);

        return tuple;
    }

    ///
    /// @inheritdoc IGMXv2strategyReader
    ///
    function withdrawCalcParams()
        external
        view
        returns (IGMXv2strategyReader.WithdrawCalcParams memory)
    {
        IGMXv2strategyReader.WithdrawCalcParams
            memory tuple = IGMXv2strategyReader.WithdrawCalcParams(
                _e_gsellShort(),
                _e_gsellLong(),
                r_short()
            );

        return tuple;
    }

    ///
    /// NOTE: only core contract access
    /// @inheritdoc IGMXv2strategyReader
    ///
    function setContract(string memory key, address value) external {
        if (msg.sender != CORE_STRATEGY) {
            revert ACLNotOwner();
        }
        // validate key exists
        if (_contracts[keccak256(abi.encode(key))] == address(0)) {
            revert FijaSetContractWrongKey();
        }
        _contracts[keccak256(abi.encode(key))] = value;
    }

    ///
    /// @dev returns the address of the underlying token used for the depositing, and withdrawing
    /// @return address of underlying token
    ///
    function asset() public view returns (address) {
        return _asset;
    }

    ///
    /// @inheritdoc IGMXv2strategyReader
    ///
    function status() external view returns (string memory) {
        uint256 vTotal = IERC4626(CORE_STRATEGY).totalAssets();

        string memory str1 = string(
            abi.encodePacked(
                "v=",
                Strings.toString(vTotal),
                "|v_long=",
                Strings.toString(_v_long()),
                "|v_short=",
                Strings.toString(_v_short()),
                "|v_short_ccy=",
                Strings.toString(_v_short_ccy()),
                "|v_dep_ccy=",
                Strings.toString(_v_dep_ccy()),
                "|c_long=",
                Strings.toString(_c_long()),
                "|c_short=",
                Strings.toString(c_short())
            )
        );

        string memory str2 = string(
            abi.encodePacked(
                "|h=",
                Strings.toString(h()),
                "|l_short=",
                Strings.toString(l_short()),
                "|imbalanceBps=",
                Strings.toString(imbalanceBps())
            )
        );
        return string(abi.encodePacked(str1, str2));
    }

    ///
    /// @inheritdoc IGMXv2strategyReader
    ///
    function getExecutionGasLimit(
        TxType txType
    ) external view override returns (uint256) {
        if (
            txType == TxType.WITHDRAW ||
            txType == TxType.REDEEM ||
            txType == TxType.EMERGENCY_MODE_WITHDRAW ||
            txType == TxType.HARVEST ||
            txType == TxType.REBALANCE
        ) {
            // withdraw execution fee
            return _estimateExecuteWithdrawalGasLimit(txType);
        } else {
            // deposit execution fee
            return _estimateExecuteDepositGasLimit(txType);
        }
    }

    ///
    /// @dev calculates gas necessary for GMX deposits
    /// @return gas amount for deposits
    ///
    function _estimateExecuteDepositGasLimit(
        TxType txType
    ) private view returns (uint256) {
        IDatastore datastore = IDatastore(_contracts[GMXv2Keys.DATASTORE]);
        uint256 estimatedGasLimit = IDatastore(_contracts[GMXv2Keys.DATASTORE])
            .getUint(GMXv2Keys.depositGasLimitKey(true)) +
            callbackGasLimit(txType);

        return _adjustGasLimitForEstimate(datastore, estimatedGasLimit);
    }

    ///
    /// @dev calculates gas necessary for GMX withdrawals
    /// @return gas amount for withdrawals
    ///
    function _estimateExecuteWithdrawalGasLimit(
        TxType txType
    ) private view returns (uint256) {
        IDatastore datastore = IDatastore(_contracts[GMXv2Keys.DATASTORE]);
        uint256 estimatedGasLimit = datastore.getUint(
            GMXv2Keys.withdrawalGasLimitKey()
        ) + callbackGasLimit(txType);

        return _adjustGasLimitForEstimate(datastore, estimatedGasLimit);
    }

    ///
    /// @inheritdoc IGMXv2strategyReader
    ///
    function callbackGasLimit(
        TxType txType
    ) public pure override returns (uint256) {
        if (txType == TxType.WITHDRAW || txType == TxType.REDEEM) {
            return CALLBACK_GAS_LIMIT_WITHDRAWAL;
        } else if (txType == TxType.EMERGENCY_MODE_WITHDRAW) {
            return CALLBACK_GAS_LIMIT_EME_ENTER;
        } else if (txType == TxType.HARVEST) {
            return CALLBACK_GAS_LIMIT_HARVEST;
        } else if (txType == TxType.REBALANCE) {
            return CALLBACK_GAS_LIMIT_REBALANCE;
        } else if (txType == TxType.EMERGENCY_MODE_DEPOSIT) {
            return CALLBACK_GAS_LIMIT_EME_EXIT;
        } else {
            return CALLBACK_GAS_LIMIT_DEPOSIT;
        }
    }

    ///
    /// @dev helper method to calculate gas limit
    /// @return gas amount
    ///
    function _adjustGasLimitForEstimate(
        IDatastore dataStore,
        uint256 estimatedGasLimit
    ) private view returns (uint256) {
        uint256 baseGasLimit = dataStore.getUint(
            GMXv2Keys.ESTIMATED_GAS_FEE_BASE_AMOUNT
        );
        uint256 multiplierFactor = dataStore.getUint(
            GMXv2Keys.ESTIMATED_GAS_FEE_MULTIPLIER_FACTOR
        );
        uint256 gasLimit = baseGasLimit +
            Precision.applyFactor(estimatedGasLimit, multiplierFactor);
        return gasLimit;
    }

    ///
    /// @dev Retrieves swap fee for used Uniswap pool
    /// @return swap fee in bps
    ///
    function _g_swap() private view returns (uint256) {
        uint256 fee = IUniswapV3Pool(UNISWAP_DEP_SEC_POOL).fee();

        return
            GMXv2Helpers.adjustForDecimals(
                fee,
                GMXv2Keys.UNISWAP_FEE_DECIMALS,
                4
            );
    }

    ///
    /// @dev gets GMX tokens supply of GMX market used in the strategy
    /// @return total supply of used GMX tokens
    ///
    function _c_long_total() private view returns (uint256) {
        return IERC20(GM_POOL).totalSupply();
    }

    ///
    /// @dev gets GMX tokens amount strategy owns
    /// @return amount of GMX market tokens on strategy
    ///
    function _c_long() private view returns (uint256) {
        return IERC20(GM_POOL).balanceOf(CORE_STRATEGY);
    }

    ///
    /// @inheritdoc IGMXv2strategyReader
    ///
    function c_short() public view returns (uint256) {
        (address aToken, , ) = GMXv2Keys
            .AAVE_IPoolDataProvider
            .getReserveTokensAddresses(DEPOSIT_CCY);
        uint256 tokens = IERC20(aToken).balanceOf(CORE_STRATEGY);
        return tokens;
    }

    ///
    /// @dev value on the long side
    /// @return value of GMX market tokens strategy has in depositCcy
    ///
    function _v_long() private view returns (uint256) {
        IReader reader = IReader(_contracts[GMXv2Keys.READER]);
        address datastore = _contracts[GMXv2Keys.DATASTORE];

        Market.Props memory market = reader.getMarket(datastore, GM_POOL);
        // get prices in usd for long and short token
        uint256 answerLong = GMXv2Keys.AAVE_IOracle.getAssetPrice(
            market.longToken
        );

        uint256 answerShort = GMXv2Keys.AAVE_IOracle.getAssetPrice(
            market.shortToken
        );

        Market.MarketPrices memory prices = _buildPoolPrices(
            answerLong,
            answerShort
        );

        (uint256 longAmount, uint256 shortAmount) = reader
            .getWithdrawalAmountOut(
                datastore,
                market,
                prices,
                _c_long(),
                address(0)
            );

        uint256 initalAmountOut;
        uint256 convertedAmountOut;
        uint256 secCcyAmount;

        if (market.longToken == DEPOSIT_CCY) {
            // deposit asset is longToken
            initalAmountOut = longAmount;
            // convert secondary ccy to deposit asset
            secCcyAmount = shortAmount;
        } else {
            // deposit asset is shortToken
            initalAmountOut = shortAmount;
            // convert seccondary ccy to deposit asset
            secCcyAmount = longAmount;
        }

        if (secCcyAmount > 0) {
            convertedAmountOut =
                (secCcyAmount * _a_short()) /
                GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION;

            convertedAmountOut = GMXv2Helpers.adjustForDecimals(
                convertedAmountOut,
                SEC_CCY_DECIMALS,
                DEP_CCY_DECIMALS
            );
            convertedAmountOut =
                (convertedAmountOut *
                    (GMXv2Keys.BASIS_POINTS_DIVISOR - _g_swap())) /
                GMXv2Keys.BASIS_POINTS_DIVISOR;
        }

        return initalAmountOut + convertedAmountOut;
    }

    ///
    /// @dev value on the short side
    /// @return value of collateral in AAVE minus the cost to unwind short positions
    ///
    function _v_short() private view returns (uint256) {
        uint256 unwind = (l_short() * r_short()) /
            GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION;

        unwind = GMXv2Helpers.adjustForDecimals(
            unwind,
            SEC_CCY_DECIMALS,
            DEP_CCY_DECIMALS
        );

        unwind =
            (unwind * (GMXv2Keys.BASIS_POINTS_DIVISOR + g_flash())) /
            GMXv2Keys.BASIS_POINTS_DIVISOR;

        return c_short() - unwind;
    }

    ///
    /// @inheritdoc IGMXv2strategyReader
    ///
    function e_gbuy() public view returns (uint256) {
        IReader reader = IReader(_contracts[GMXv2Keys.READER]);
        address datastore = _contracts[GMXv2Keys.DATASTORE];

        Market.Props memory market = reader.getMarket(datastore, GM_POOL);

        uint256 answerLong = GMXv2Keys.AAVE_IOracle.getAssetPrice(
            market.longToken
        );
        uint256 answerShort = GMXv2Keys.AAVE_IOracle.getAssetPrice(
            market.shortToken
        );

        Market.MarketPrices memory prices = _buildPoolPrices(
            answerLong,
            answerShort
        );

        uint256 longTokenAmount = 0;
        uint256 shortTokenAmount = 0;
        if (market.longToken == DEPOSIT_CCY) {
            longTokenAmount = 10 ** DEP_CCY_DECIMALS;
        } else {
            shortTokenAmount = 10 ** DEP_CCY_DECIMALS;
        }

        uint256 gmTokens = reader.getDepositAmountOut(
            address(datastore),
            market,
            prices,
            longTokenAmount,
            shortTokenAmount,
            address(0)
        );

        return gmTokens;
    }

    ///
    /// @inheritdoc IGMXv2strategyReader
    ///
    function l_short() public view returns (uint256) {
        (, address stableDebtToken, address variableDebtToken) = GMXv2Keys
            .AAVE_IPoolDataProvider
            .getReserveTokensAddresses(SEC_CCY);

        uint256 variableDebt = IERC20(variableDebtToken).balanceOf(
            CORE_STRATEGY
        );
        uint256 stableDebt = IERC20(stableDebtToken).balanceOf(CORE_STRATEGY);

        return variableDebt + stableDebt;
    }

    ///
    /// @dev secondaryCcy/depositCcy exchange rate from AAVE oracle
    /// @return exchange rate
    ///
    function _a_short() private view returns (uint256) {
        uint256 a_dep_usd = GMXv2Keys.AAVE_IOracle.getAssetPrice(DEPOSIT_CCY);
        uint256 a_sec_usd = GMXv2Keys.AAVE_IOracle.getAssetPrice(SEC_CCY);

        return (a_sec_usd * GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION) / a_dep_usd;
    }

    ///
    /// @inheritdoc IGMXv2strategyReader
    ///
    function r_short() public view returns (uint256) {
        return
            (_a_short() * (GMXv2Keys.BASIS_POINTS_DIVISOR - _g_swap())) /
            GMXv2Keys.BASIS_POINTS_DIVISOR;
    }

    ///
    /// @dev value of GM token in long token ccy
    /// @return value of 1 GM token in GMX market long token amount
    ///
    function _e_gsellLong() private view returns (uint256) {
        (
            uint256 longAmount,
            uint256 shortAmount,
            Market.Props memory market
        ) = _unwindGmToken();

        uint256 amount;
        if (market.longToken == DEPOSIT_CCY) {
            amount = longAmount;
        } else {
            amount = shortAmount;
        }
        return amount;
    }

    ///
    /// @dev value of GM token in short token ccy
    /// @return value of 1 GM token in GMX market short token amount
    ///
    function _e_gsellShort() private view returns (uint256) {
        (
            uint256 longAmount,
            uint256 shortAmount,
            Market.Props memory market
        ) = _unwindGmToken();

        uint256 amount;
        if (market.longToken == SEC_CCY) {
            amount = longAmount;
        } else {
            amount = shortAmount;
        }
        return amount;
    }

    ///
    /// @inheritdoc IGMXv2strategyReader
    ///
    function g_flash() public view override returns (uint128) {
        IPool pool = IPool(GMXv2Keys.AAVE_IPoolAddressesProvider.getPool());
        return pool.FLASHLOAN_PREMIUM_TOTAL();
    }

    ///
    /// @inheritdoc IGMXv2strategyReader
    ///
    function h() public view returns (uint256) {
        IPool pool = IPool(GMXv2Keys.AAVE_IPoolAddressesProvider.getPool());

        (, , , , , uint256 healthFactor) = pool.getUserAccountData(
            CORE_STRATEGY
        );
        return healthFactor;
    }

    ///
    /// @dev retrieves liquidation threshold of deposit ccy in AAVE
    /// @return deposit ccy liquidation threshold in bps
    ///
    function _q() private view returns (uint256) {
        IPool pool = IPool(GMXv2Keys.AAVE_IPoolAddressesProvider.getPool());
        DataTypes.ReserveConfigurationMap memory map = pool.getConfiguration(
            DEPOSIT_CCY
        );
        uint256 target = map.data >> 16;
        uint256 mask = (1 << 16) - 1;
        return target & mask;
    }

    ///
    /// @dev helper function to calculate T_long.
    /// @return ratio (h / q)
    ///
    function _hDivQ() private view returns (uint256) {
        return
            (GMXv2Keys.FIJA_HEALTH_FACTOR * GMXv2Keys.BASIS_POINTS_DIVISOR) /
            _q();
    }

    ///
    /// @dev helper function to calculate C_long for both deposits and withdrawals
    /// @param t input param to calculate Clong
    /// @param Tlong input param to calculate Clong
    /// @return amount of GM tokens to increase/decrease with investment
    ///
    function _C_long(int256 t, int256 Tlong) private view returns (uint256) {
        // TODO is C_long withdrawal and deposits formula decided against t or Tlong?
        if (t >= 0) {
            return
                uint256(
                    (int256(_c_long()) +
                        (Tlong * int256(e_gbuy())) /
                        int256((10 ** DEP_CCY_DECIMALS)))
                );
        } else {
            uint256 base = ((_e_gsellShort() * r_short()) /
                GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION);

            base = GMXv2Helpers.adjustForDecimals(
                base,
                SEC_CCY_DECIMALS,
                DEP_CCY_DECIMALS
            );

            uint256 temp = _e_gsellLong() + base;

            int256 modifier1 = (Tlong * int256(10 ** DEP_CCY_DECIMALS)) /
                int256(temp);

            modifier1 = GMXv2Helpers.adjustForDecimalsInt(
                modifier1,
                DEP_CCY_DECIMALS,
                GMXv2Keys.GM_TOKEN_DECIMALS
            );

            int256 clong = int256(_c_long());

            if (clong + modifier1 < 0) {
                return 0;
            } else {
                return uint256(clong + modifier1);
            }
        }
    }

    ///
    /// @dev helper function to calculate Lshort for both deposits and withdrawals
    /// @param t input param to calculate Lshort
    /// @param Tlong input param to calculate Lshort
    /// @return amount of AAVE loan to increase/decrease with investment
    ///
    function _L_short(int256 t, int256 Tlong) private view returns (uint256) {
        Market.Props memory market = IReader(_contracts[GMXv2Keys.READER])
            .getMarket(_contracts[GMXv2Keys.DATASTORE], GM_POOL);

        uint256 secPriceUsd;
        if (SEC_CCY == market.longToken) {
            secPriceUsd = GMXv2Keys.AAVE_IOracle.getAssetPrice(
                market.longToken
            );
        } else {
            secPriceUsd = GMXv2Keys.AAVE_IOracle.getAssetPrice(
                market.shortToken
            );
        }
        // calcuation is for both deposits and withdrawals
        return
            uint256(
                ((int256(_e_gsellShort()) +
                    ((_oiExposureSecCcy(market, secPriceUsd) *
                        int256(GMXv2Keys.GM_TOKEN_PRECISION)) /
                        int256(_c_long_total()))) * int256(_C_long(t, Tlong))) /
                    int256(GMXv2Keys.GM_TOKEN_PRECISION)
            );
    }

    ///
    /// @dev helper function to calculate Tlong for both deposits and withdrawals
    /// @param t input param to calculate Tlong
    /// @return calculation of target GM tokens in deposit or withdrawal flow
    ///
    function _T_long(int256 t) private view returns (int256) {
        Market.Props memory market = IReader(_contracts[GMXv2Keys.READER])
            .getMarket(_contracts[GMXv2Keys.DATASTORE], GM_POOL);

        uint256 secPriceUsd;
        if (SEC_CCY == market.longToken) {
            secPriceUsd = GMXv2Keys.AAVE_IOracle.getAssetPrice(
                market.longToken
            );
        } else {
            secPriceUsd = GMXv2Keys.AAVE_IOracle.getAssetPrice(
                market.shortToken
            );
        }

        int256 e_sellShortModSecCcy = int256(_e_gsellShort()) +
            ((_oiExposureSecCcy(market, secPriceUsd) *
                int256(GMXv2Keys.GM_TOKEN_PRECISION)) /
                int256(_c_long_total()));

        if (t >= 0) {
            return _T_long_deposit(t, e_sellShortModSecCcy);
        } else {
            return _T_long_withdraw(t, e_sellShortModSecCcy);
        }
    }

    ///
    /// @dev helper function to calculate Tlong for deposits
    /// @param t input param to calculate Tlong for deposits
    /// @param e_sellShortModSecCcy input param to calculate Tlong for deposits
    /// @return calculation of target GM tokens in deposit flow
    ///
    function _T_long_deposit(
        int256 t,
        int256 e_sellShortModSecCcy
    ) private view returns (int256) {
        return
            (_numeratorTlongDeposit(t, e_sellShortModSecCcy) *
                int256(GMXv2Keys.GM_TOKEN_PRECISION)) /
            _denominatorTlongDeposit(e_sellShortModSecCcy);
    }

    ///
    /// @dev helper function to calculate Tlong for withdrawals
    /// @param t input param to calculate Tlong for withdrawals
    /// @param e_sellShortModSecCcy input param to calculate Tlong for withdrawals
    /// @return calculation of target GM tokens in withdrawals flow
    ///
    function _T_long_withdraw(
        int256 t,
        int256 e_sellShortModSecCcy
    ) private view returns (int256) {
        return
            (_numeratorTlongWithdraw(t, e_sellShortModSecCcy) *
                int256(10 ** DEP_CCY_DECIMALS)) /
            (_denominatorTlongWithdraw(e_sellShortModSecCcy));
    }

    ///
    /// @dev helper function to calculate Tlong for deposits
    /// @param t input param to calculate Tlong for deposits
    /// @param e_sellShortModSecCcy input param to calculate Tlong for deposits
    /// @return calculation of target GM tokens in deposits flow
    ///
    function _numeratorTlongDeposit(
        int256 t,
        int256 e_sellShortModSecCcy
    ) private view returns (int256) {
        int256 base = (int256(_c_long()) * e_sellShortModSecCcy) /
            int256(GMXv2Keys.GM_TOKEN_PRECISION);

        int256 temp = ((base - (int256(l_short()))) * int256(r_short())) /
            int256(GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION);

        temp = GMXv2Helpers.adjustForDecimalsInt(
            temp,
            SEC_CCY_DECIMALS,
            DEP_CCY_DECIMALS
        );

        temp =
            (temp * int256(GMXv2Keys.BASIS_POINTS_DIVISOR - g_flash())) /
            int256(GMXv2Keys.BASIS_POINTS_DIVISOR);

        int256 modifier1 = int256(c_short()) + t + temp;

        int256 modifier2 = (base * int256(_a_short())) /
            int256(GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION);

        modifier2 = GMXv2Helpers.adjustForDecimalsInt(
            modifier2,
            SEC_CCY_DECIMALS,
            DEP_CCY_DECIMALS
        );

        modifier2 = (modifier2 * int256(_hDivQ())) / 10 ** 18;

        return modifier1 - modifier2;
    }

    ///
    /// @dev helper function to calculate Tlong for deposits
    /// @param e_sellShortModSecCcy input param to calculate Tlong for deposits
    /// @return calculation of target GM tokens in deposits flow
    ///
    function _denominatorTlongDeposit(
        int256 e_sellShortModSecCcy
    ) private view returns (int256) {
        int256 base = (int256(e_gbuy()) * e_sellShortModSecCcy) /
            int256(10 ** SEC_CCY_DECIMALS);

        int256 modifier1 = ((
            ((base * int256(_a_short())) /
                int256(GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION))
        ) * int256(_hDivQ())) / int256(10 ** 18);

        int256 modifier2 = (((
            (base * int256(GMXv2Keys.BASIS_POINTS_DIVISOR - g_flash()))
        ) / int256(GMXv2Keys.BASIS_POINTS_DIVISOR)) * int256(r_short())) /
            int256(GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION);

        return int256(GMXv2Keys.GM_TOKEN_PRECISION) + modifier1 - modifier2;
    }

    ///
    /// @dev helper function to calculate Tlong for withdrawals
    /// @param t input param to calculate Tlong for withdrawals
    /// @param e_sellShortModSecCcy input param to calculate Tlong for withdrawals
    /// @return calculation of target GM tokens in withdrawals flow
    ///
    function _numeratorTlongWithdraw(
        int256 t,
        int256 e_sellShortModSecCcy
    ) private view returns (int256) {
        int256 base = (int256(_c_long()) * e_sellShortModSecCcy) /
            int256(GMXv2Keys.GM_TOKEN_PRECISION);

        int256 temp = ((int256(l_short()) - base) * int256(r_short())) /
            int256(GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION);

        temp = GMXv2Helpers.adjustForDecimalsInt(
            temp,
            SEC_CCY_DECIMALS,
            DEP_CCY_DECIMALS
        );

        temp =
            (temp * int256(GMXv2Keys.BASIS_POINTS_DIVISOR + g_flash())) /
            int256(GMXv2Keys.BASIS_POINTS_DIVISOR);

        int256 modifier1 = int256(c_short()) + t - temp;

        int256 modifier2 = (base * int256(_a_short())) /
            int256(GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION);

        modifier2 = GMXv2Helpers.adjustForDecimalsInt(
            modifier2,
            SEC_CCY_DECIMALS,
            DEP_CCY_DECIMALS
        );

        modifier2 = (modifier2 * int256(_hDivQ())) / 10 ** 18;

        return modifier1 - modifier2;
    }

    ///
    /// @dev helper function to calculate Tlong for withdrawals
    /// @param e_sellShortModSecCcy input param to calculate Tlong for withdrawals
    /// @return calculation of target GM tokens in withdrawals flow
    ///
    function _denominatorTlongWithdraw(
        int256 e_sellShortModSecCcy
    ) private view returns (int256) {
        int256 temp1 = (e_sellShortModSecCcy * int256(r_short())) /
            int256(GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION);

        temp1 = GMXv2Helpers.adjustForDecimalsInt(
            temp1,
            SEC_CCY_DECIMALS,
            DEP_CCY_DECIMALS
        );

        int256 temp2 = ((int256(_e_gsellShort()) * int256(r_short())) /
            int256(GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION));

        temp2 = GMXv2Helpers.adjustForDecimalsInt(
            temp2,
            SEC_CCY_DECIMALS,
            DEP_CCY_DECIMALS
        );

        temp2 = int256(_e_gsellLong()) + temp2;

        int256 modifier1 = (((int256(temp1) *
            int256(GMXv2Keys.BASIS_POINTS_DIVISOR + g_flash())) /
            int256(GMXv2Keys.BASIS_POINTS_DIVISOR)) *
            int256(10 ** DEP_CCY_DECIMALS)) / temp2;

        temp1 =
            (e_sellShortModSecCcy * int256(_a_short())) /
            int256(GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION);

        temp1 = GMXv2Helpers.adjustForDecimalsInt(
            temp1,
            SEC_CCY_DECIMALS,
            DEP_CCY_DECIMALS
        );

        int256 modifier2 = (temp1 * int256(10 ** DEP_CCY_DECIMALS)) / temp2;

        modifier2 = (modifier2 * int256(_hDivQ())) / 10 ** 18;

        return int256(10 ** DEP_CCY_DECIMALS) - modifier1 + modifier2;
    }

    ///
    /// @dev unwinds 1 GMX token to long token and short token amounts
    /// @return amount of long tokens in 1 GM token
    /// @return amount of short tokens in 1 GM token
    /// @return market address
    ///
    function _unwindGmToken()
        private
        view
        returns (uint256, uint256, Market.Props memory)
    {
        IReader reader = IReader(_contracts[GMXv2Keys.READER]);
        address datastore = _contracts[GMXv2Keys.DATASTORE];

        Market.Props memory market = reader.getMarket(datastore, GM_POOL);

        // get prices in usd for long and short token
        uint256 answerLong = GMXv2Keys.AAVE_IOracle.getAssetPrice(
            market.longToken
        );
        uint256 answerShort = GMXv2Keys.AAVE_IOracle.getAssetPrice(
            market.shortToken
        );

        Market.MarketPrices memory prices = _buildPoolPrices(
            answerLong,
            answerShort
        );

        (uint256 longAmount, uint256 shortAmount) = reader
            .getWithdrawalAmountOut(
                datastore,
                market,
                prices,
                GMXv2Keys.GM_TOKEN_PRECISION,
                address(0)
            );

        return (longAmount, shortAmount, market);
    }

    ///
    /// @inheritdoc IGMXv2strategyReader
    ///
    function imbalanceBps() public view returns (uint256) {
        uint256 imbBps;

        uint256 cLong = _c_long();
        if (cLong != 0) {
            IReader reader = IReader(_contracts[GMXv2Keys.READER]);
            address datastore = _contracts[GMXv2Keys.DATASTORE];

            Market.Props memory market = reader.getMarket(datastore, GM_POOL);

            // get prices in usd for long and short token
            uint256 answerLong = GMXv2Keys.AAVE_IOracle.getAssetPrice(
                market.longToken
            );
            uint256 answerShort = GMXv2Keys.AAVE_IOracle.getAssetPrice(
                market.shortToken
            );

            uint256 secAmount = (cLong * _e_gsellShort()) /
                GMXv2Keys.GM_TOKEN_PRECISION;

            uint256 secPriceUsd;
            if (SEC_CCY == market.longToken) {
                secPriceUsd = answerLong;
            } else {
                secPriceUsd = answerShort;
            }

            int256 imbalanceBpsTemp = ((int256(secAmount) +
                (((_oiExposureSecCcy(market, secPriceUsd) *
                    int256(GMXv2Keys.GM_TOKEN_PRECISION)) /
                    int256(_c_long_total())) * int256(_c_long())) /
                int256(GMXv2Keys.GM_TOKEN_PRECISION) -
                int256(l_short())) * 10000) / int256(secAmount);

            if (imbalanceBpsTemp < 0) {
                imbalanceBpsTemp = imbalanceBpsTemp * -1;
            }
            imbBps = uint256(imbalanceBpsTemp);
        }
        return imbBps;
    }

    ///
    /// @dev helper method to fetch key for market open interest
    /// @param market GMX market address
    /// @param collateralToken long/short token address in the market
    /// @param isLong flag for long or short interest
    /// @return key used to fetch long and short open interest from datastore
    ///
    function _openInterestKey(
        address market,
        address collateralToken,
        bool isLong
    ) private pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    GMXv2Keys.OPEN_INTEREST,
                    market,
                    collateralToken,
                    isLong
                )
            );
    }

    ///
    /// @dev calculate open interest exposure of the GMX market
    /// @param market GMX market/pool address
    /// @param secPriceUsd input parameter to calculate open interest
    /// @return open interest exposure in secondary ccy
    ///
    function _oiExposureSecCcy(
        Market.Props memory market,
        uint256 secPriceUsd
    ) private view returns (int256) {
        bytes32 key = _openInterestKey(
            market.marketToken,
            market.longToken,
            true
        );
        IDatastore datastore = IDatastore(_contracts[GMXv2Keys.DATASTORE]);

        uint256 longInterestUsingLongToken = datastore.getUint(key);

        key = _openInterestKey(market.marketToken, market.shortToken, true);
        uint256 longInterestUsingShortToken = datastore.getUint(key);

        key = _openInterestKey(market.marketToken, market.longToken, false);
        uint256 shortInterestUsingLongToken = datastore.getUint(key);

        key = _openInterestKey(market.marketToken, market.shortToken, false);
        uint256 shortInterestUsingShortToken = datastore.getUint(key);

        int256 longInterestUsd = int256(
            longInterestUsingLongToken + longInterestUsingShortToken
        );
        int256 shortInterestUsd = int256(
            shortInterestUsingLongToken + shortInterestUsingShortToken
        );

        // convert interest in usd to secondary ccy
        int256 oIExposureSecCcy = ((shortInterestUsd - longInterestUsd) *
            int256(GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION)) /
            int256(secPriceUsd);

        oIExposureSecCcy = GMXv2Helpers.adjustForDecimalsInt(
            oIExposureSecCcy,
            GMXv2Keys.PRICE_DECIMALS,
            SEC_CCY_DECIMALS
        );

        return oIExposureSecCcy;
    }

    ///
    /// @dev build market token prices in USD with precisions aligned to GMX API
    /// @param oracleLongUsd  market long token price in USD from AAVE oracle
    /// @param oracleShortUsd market short token price in USD from AAVE oracle
    /// @return Market.MarketPrices
    ///
    function _buildPoolPrices(
        uint256 oracleLongUsd,
        uint256 oracleShortUsd
    ) private view returns (Market.MarketPrices memory) {
        uint256 price = GMXv2Helpers.adjustPriceDecimals(
            oracleLongUsd,
            LONG_PRICE_DECIMALS
        );

        Price.Props memory longTokenPrice = Price.Props({
            max: (price *
                (GMXv2Keys.BASIS_POINTS_DIVISOR +
                    GMXv2Keys.PRICE_DEVIATION_BPS)) /
                GMXv2Keys.BASIS_POINTS_DIVISOR,
            min: (price *
                (GMXv2Keys.BASIS_POINTS_DIVISOR -
                    GMXv2Keys.PRICE_DEVIATION_BPS)) /
                GMXv2Keys.BASIS_POINTS_DIVISOR
        });
        price = GMXv2Helpers.adjustPriceDecimals(
            oracleShortUsd,
            SHORT_PRICE_DECIMALS
        );

        Price.Props memory shortTokenPrice = Price.Props({
            max: (price *
                (GMXv2Keys.BASIS_POINTS_DIVISOR +
                    GMXv2Keys.PRICE_DEVIATION_BPS)) /
                GMXv2Keys.BASIS_POINTS_DIVISOR,
            min: (price *
                (GMXv2Keys.BASIS_POINTS_DIVISOR -
                    GMXv2Keys.PRICE_DEVIATION_BPS)) /
                GMXv2Keys.BASIS_POINTS_DIVISOR
        });
        return
            Market.MarketPrices(
                longTokenPrice,
                longTokenPrice,
                shortTokenPrice
            );
    }

    ///
    /// @dev gets depositCcy amount which strategy has
    /// @return amount of depositCcy tokens
    ///
    function _v_dep_ccy() private view returns (uint256) {
        uint256 depositCcyValue;
        if (asset() == GMXv2Keys.ETH) {
            // TODO to change
            depositCcyValue =
                CORE_STRATEGY.balance +
                IERC20(WETH).balanceOf(CORE_STRATEGY);
        } else {
            depositCcyValue = IERC20(DEPOSIT_CCY).balanceOf(CORE_STRATEGY);
        }
        return depositCcyValue;
    }

    ///
    /// @dev gets how much strategy has secondaryCcy tokens in depositCcy amount
    /// @return amount of secondary tokens in depositCcy
    ///
    function _v_short_ccy() private view returns (uint256) {
        uint256 secInDepositCcy = (IERC20(SEC_CCY).balanceOf(CORE_STRATEGY) *
            r_short()) / GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION;

        secInDepositCcy = GMXv2Helpers.adjustForDecimals(
            secInDepositCcy,
            SEC_CCY_DECIMALS,
            DEP_CCY_DECIMALS
        );
        return secInDepositCcy;
    }

    ///
    /// @inheritdoc IGMXv2strategyReader
    ///
    function assetsOnly() external view returns (uint256) {
        return _v_dep_ccy() + _v_long() + _v_short();
    }

    ///
    /// @inheritdoc IGMXv2strategyReader
    ///
    function nativeDepositRate() external view override returns (uint256) {
        uint256 a_dep_usd = GMXv2Keys.AAVE_IOracle.getAssetPrice(DEPOSIT_CCY);
        uint256 a_sec_usd = GMXv2Keys.AAVE_IOracle.getAssetPrice(WETH);

        return (a_sec_usd * GMXv2Keys.AAVE_BASE_CURRENCY_PRECISION) / a_dep_usd;
    }
}

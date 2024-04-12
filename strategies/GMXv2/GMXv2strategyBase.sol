// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./GMXv2Keys.sol";

///
/// @title GMXv2 Base contract
/// @author Fija
/// @notice Used to initalize main and periphery contract variables
/// @dev Enables spliting contracts to main and periphery with access to same data,
/// this to utilize immutable varibles in terms of gas cost
/// NOTE: Parent contract to GMXv2strategy and GMXv2strategyReader
///
abstract contract GMXv2strategyBase {
    ///
    /// @param router GMX router address
    /// @param depositVault GMX deposit vault address
    /// @param withdrawVault GMX withdraw vault address
    /// @param reader GMX reader address
    /// @param datastore GMX datastore address
    /// @param exchangeRouter GMX exchange router address
    /// @param roleStore GMX role store address
    ///
    struct ProtocolContracts {
        address router;
        address depositVault;
        address withdrawVault;
        address reader;
        address datastore;
        address exchangeRouter;
        address roleStore;
    }

    ///
    /// @param gmPool GMX market address
    /// @param secondaryCcy secondary ccy for GMX market
    /// @param weth wrapped native token address
    /// @param uniswapPool pool address for GMX market token swaps
    /// @param nativeDepPool pool address for native token to depositCcy swaps
    /// @param hfHighThreshold health factor high threshold
    /// @param hfLowThreshold health factor low threshold
    /// @param imbalanceThresholdBps imbalance threshold
    /// @param longPriceDecimals decimals for long token in GMX market
    /// @param shortPriceDecimals decimals for short token in GMX market
    /// @param contracts GMX contracts
    ///
    struct ConstructorData {
        address gmPool;
        address secondaryCcy;
        address weth;
        address uniswapPool;
        address nativeDepPool;
        uint256 hfHighThreshold;
        uint256 hfLowThreshold;
        uint256 imbalanceThresholdBps;
        uint8 longPriceDecimals;
        uint8 shortPriceDecimals;
        ProtocolContracts contracts;
    }

    ///
    /// @dev reference to GMX contract addresses
    ///
    mapping(bytes32 => address) internal _contracts;

    ///
    /// @dev GMX market/pool address
    ///
    address internal immutable GM_POOL;

    ///
    /// @dev secondary ccy address
    ///
    address internal immutable SEC_CCY;

    ///
    /// @dev deposit ccy address
    ///
    address internal immutable DEPOSIT_CCY;

    ///
    /// @dev wrapped native token address
    ///
    address internal immutable WETH;

    ///
    /// @dev pool address for GMX market token swaps
    ///
    address internal immutable UNISWAP_DEP_SEC_POOL;

    ///
    /// @dev pool address for native token to depositCcy swaps
    ///
    address internal immutable UNISWAP_NATIVE_DEP_POOL;

    ///
    /// @dev imbalance threshold in bps
    ///
    uint256 internal immutable IMBALANCE_THR_BPS;

    ///
    /// @dev health factor high threshold
    ///
    uint256 internal immutable HF_HIGH_THR;

    ///
    /// @dev health factor low threshold
    ///
    uint256 internal immutable HF_LOW_THR;

    ///
    /// @dev decimals for long token in GMX market align with GMX API
    ///
    uint8 internal immutable LONG_PRICE_DECIMALS;

    ///
    /// @dev decimals for short token in GMX market align with GMX API
    ///
    uint8 internal immutable SHORT_PRICE_DECIMALS;

    ///
    /// @dev decimals for deposit ccy
    ///
    uint8 internal immutable DEP_CCY_DECIMALS;

    ///
    /// @dev decimals for secondary ccy
    ///
    uint8 internal immutable SEC_CCY_DECIMALS;

    constructor(ConstructorData memory data_, address depositCurrency_) {
        _contracts[GMXv2Keys.ROUTER] = data_.contracts.router;
        _contracts[GMXv2Keys.WITHDRAW_VAULT] = data_.contracts.withdrawVault;
        _contracts[GMXv2Keys.DEPOSIT_VAULT] = data_.contracts.depositVault;
        _contracts[GMXv2Keys.READER] = data_.contracts.reader;
        _contracts[GMXv2Keys.DATASTORE] = data_.contracts.datastore;
        _contracts[GMXv2Keys.EXCHANGE_ROUTER] = data_.contracts.exchangeRouter;
        _contracts[GMXv2Keys.ROLE_STORE] = data_.contracts.roleStore;

        WETH = data_.weth;
        DEPOSIT_CCY = depositCurrency_ == GMXv2Keys.ETH
            ? WETH
            : depositCurrency_;
        SEC_CCY = data_.secondaryCcy;
        GM_POOL = data_.gmPool;
        HF_HIGH_THR = data_.hfHighThreshold;
        HF_LOW_THR = data_.hfLowThreshold;
        IMBALANCE_THR_BPS = data_.imbalanceThresholdBps;

        LONG_PRICE_DECIMALS = data_.longPriceDecimals;
        SHORT_PRICE_DECIMALS = data_.shortPriceDecimals;

        UNISWAP_DEP_SEC_POOL = data_.uniswapPool;
        UNISWAP_NATIVE_DEP_POOL = data_.nativeDepPool;

        DEP_CCY_DECIMALS = depositCurrency_ == GMXv2Keys.ETH
            ? 18
            : IERC20Metadata(DEPOSIT_CCY).decimals();
        SEC_CCY_DECIMALS = IERC20Metadata(SEC_CCY).decimals();
    }
}

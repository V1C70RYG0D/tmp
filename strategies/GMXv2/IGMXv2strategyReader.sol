// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../../base/types.sol";

///
/// @title GMXv2strategyReader interface
/// @notice exposed methods for interaction with GMXv2strategyReader,
/// used in core strategy and external library
///
interface IGMXv2strategyReader {
    ///
    /// @param Tlong input for investment logic
    /// @param Lshort input for investment logic
    ///
    struct TlongLshort {
        int256 Tlong;
        uint256 Lshort;
    }

    ///
    /// @param eGsellShort input for withdraw operation of investment logic
    /// @param eGsellLong input withdraw operation of investment logic
    /// @param rShort input withdraw operation of investment logic
    ///
    struct WithdrawCalcParams {
        uint256 eGsellShort;
        uint256 eGsellLong;
        uint256 rShort;
    }

    ///
    /// @dev calculates Tlong and Lshort params needed for investment logic
    /// @param t input parameter to Tlong and Lshort
    /// @return Tlong and Lshort
    ///
    function getTlongLshort(
        int256 t
    ) external view returns (TlongLshort memory);

    ///
    /// @dev calculates params for withdrawal operations of investment logic
    /// @return WithdrawCalcParams
    ///
    function withdrawCalcParams()
        external
        view
        returns (WithdrawCalcParams memory);

    ///
    /// @dev required gas to provide to GMX keeper to execute deposit/withdrawal requests
    /// @param txType enum to determine the type of transaction to calculate gas limit
    /// @return gas amount
    ///
    function getExecutionGasLimit(
        TxType txType
    ) external view returns (uint256);

    ///
    /// @dev calculates GMX callback gas limit based on transaction type
    /// @param txType transaction type enum
    /// @return callback gas limit
    ///
    function callbackGasLimit(TxType txType) external pure returns (uint256);

    ///
    /// NOTE: only core contract access
    /// @dev sets GMX contract address by key for case when contract address change
    /// @param key contract key
    /// @param value contract address
    ///
    function setContract(string memory key, address value) external;

    ///
    /// @dev helper method to calculate strategy's total assets amount
    /// @return total amount of assets core strategy has under management, including current flashloan or execution fee, if any
    ///
    function assetsOnly() external view returns (uint256);

    ////
    /// @dev calculates imbalance used for detecting when to rebalance strategy
    /// @return strategy imbalance in bps
    ///
    function imbalanceBps() external view returns (uint256);

    ///
    /// @dev used as supporting method to core strategy status
    /// @return strategy metadata
    ///
    function status() external view returns (string memory);

    ///
    /// @dev retrieves health factor of strategy in AAVE
    /// @return current health factor
    ///
    function h() external view returns (uint256);

    ///
    /// @dev secondaryCcy/depositCcy exchange rate with swap fee from AAVE oracle
    /// @return exchange rate
    ///
    function r_short() external view returns (uint256);

    ///
    /// @dev collateral in AAVE
    /// @return collateral amount strategy has at AAVE
    ///
    function c_short() external view returns (uint256);

    ///
    /// @dev depositCcy/GMX tokens exchange rate
    /// @return GM tokens amount for 1 deposit token
    ///
    function e_gbuy() external view returns (uint256);

    ///
    /// @dev borrowed amount in AAVE
    /// @return stable and variable debt sum strategy has at AAVE
    ///
    function l_short() external view returns (uint256);

    ///
    /// @dev fee AAVE charges for flashloan
    /// @return flashloan fee
    ///
    function g_flash() external view returns (uint128);

    ///
    /// @dev weth/depositCcy exchange rate from AAVE oracle
    /// @return exchange rate
    ///
    function nativeDepositRate() external view returns (uint256);
}

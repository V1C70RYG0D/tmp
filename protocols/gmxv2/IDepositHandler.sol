// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./Price.sol";
import "./Deposit.sol";

///
/// @title DepositHandler interface
/// @notice Interface towards GMX DepositHandler contract
/// @dev used to simulate keeper deposit execution
///
interface IDepositHandler {
    ///
    /// @dev executes a deposit
    /// @param key the key of the deposit to execute
    /// @param oracleParams Price.SetPricesParams
    ///
    function executeDeposit(
        bytes32 key,
        Price.SetPricesParams calldata oracleParams
    ) external;
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./Price.sol";

///
/// @title WithdrawalHandler interface
/// @notice Interface towards GMX WithdrawalHandler contract
/// @dev used to simulate keeper withdrawal execution
///
interface IWithdrawHandler {
    ///
    /// @dev executes a withdrawal
    /// @param key the key of the withdrawal to execute
    /// @param oracleParams Price.SetPricesParams
    ///
    function executeWithdrawal(
        bytes32 key,
        Price.SetPricesParams calldata oracleParams
    ) external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Deposit.sol";
import "./Withdrawal.sol";

///
/// @title ExchangeRouter interface
/// @notice interface towards GMX ExchangeRouter contract
/// @dev used as main entry point to interact with GMX deposit and withdraw processes
///
interface IExchangeRouter {
    ///
    /// @dev Creates a new deposit
    /// The deposit is created by transferring the specified amounts of
    /// long and short tokens from the caller's account to the deposit store, and then calling the
    /// createDeposit() function on the deposit handler contract.
    /// @param params deposit parameters, as specified in the Deposit.CreateDepositParams struct
    /// @return The unique ID of the newly created deposit
    ///
    function createDeposit(
        Deposit.CreateDepositParams calldata params
    ) external payable returns (bytes32);

    ///
    /// @dev Creates a new withdrawal
    /// The withdrawal is created by calling the createWithdrawal() function on the withdrawal handler contract.
    /// @param params withdrawal parameters, as specified in the Withdrawal.CreateWithdrawalParams struct
    /// @return The unique ID of the newly created withdrawal
    ///
    function createWithdrawal(
        Withdrawal.CreateWithdrawalParams calldata params
    ) external payable returns (bytes32);

    ///
    /// @dev Wraps the specified amount of native tokens into WNT then sends the WNT to the specified address
    /// @param receiver address of WNT receiver
    /// @param amount amount of native tokens to wrap
    ///
    function sendWnt(address receiver, uint256 amount) external payable;

    ///
    /// @dev Sends the given amount of tokens to the given address
    /// @param token address of token to be sent
    /// @param receiver token receiver address
    /// @param amount token amount to be sent
    ///
    function sendTokens(
        address token,
        address receiver,
        uint256 amount
    ) external payable;
}

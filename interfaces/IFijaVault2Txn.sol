// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./IFijaVault.sol";
import "./IFijaStrategy.sol";

import "../base/types.sol";

///
/// @title FijaVault2Txn interface
/// @author Fija
/// @notice Defines interface methods and events used by FijaVault2Txn
/// @dev expands base IFijaVault with adding callback methods to support
/// 2 transaction deposit/withdraw/redeem
///
interface IFijaVault2Txn is IFijaVault {
    ///
    /// @dev emits when deposit fails
    /// @param receiver token receiver address
    /// @param assets amount of assets caller wants to deposit
    /// @param timestamp timestamp in seconds
    ///
    event DepositFailed(
        address indexed receiver,
        uint256 assets,
        uint256 timestamp
    );

    ///
    /// @dev emits when withdraw fails
    /// @param receiver asset receiver address
    /// @param owner token owner address
    /// @param assets amount of assets owner wants to withdraw
    /// @param timestamp timestamp in seconds
    ///
    event WithdrawFailed(
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 timestamp
    );

    ///
    /// @dev emits when redeem fails
    /// @param receiver asset receiver address
    /// @param owner token owner address
    /// @param tokens amount of tokens owner wants to burn
    /// @param timestamp timestamp in seconds
    ///
    event RedeemFailed(
        address indexed receiver,
        address indexed owner,
        uint256 tokens,
        uint256 timestamp
    );

    ///
    /// @dev callback invoked by strategy to indicate it's deposit process completed
    /// @param assets amount of assets caller wants to deposit
    /// @param tokensToMint amount of tokens vault needs to send to the caller
    /// @param receiver token receiver address
    /// @param isSuccess flag indicating strategy deposit was successful
    ///
    function afterDeposit(
        uint256 assets,
        uint256 tokensToMint,
        address receiver,
        bool isSuccess
    ) external;

    ///
    /// @dev callback invoked by strategy to indicate it's redeem process completed
    /// @param tokens amount of vault tokens caller wants to redeem
    /// @param receiver asset receiver address
    /// @param owner vault token owner address
    /// @param isSuccess flag indicating strategy redeem was successful
    ///
    function afterRedeem(
        uint256 tokens,
        address receiver,
        address owner,
        bool isSuccess
    ) external;

    ///
    /// @dev callback invoked by strategy to indicate it's withdrawal process completed
    /// @param assets amount of assets caller wants to withdraw
    /// @param receiver asset receiver address
    /// @param owner vault token owner address
    /// @param isSuccess flag indicating strategy withdrawal was successful
    ///
    function afterWithdraw(
        uint256 assets,
        address receiver,
        address owner,
        bool isSuccess
    ) external;

    ///
    /// @dev gets input params for vault.deposit/withdraw/redeem,
    /// used by strategy to invoke vault callbacks with original calldata
    /// @return TxParams
    ///
    function txParams() external view returns (TxParams memory);
}

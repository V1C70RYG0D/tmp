// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

///
/// @title Withdrawal
/// @notice Struct for withdrawals
///
library Withdrawal {
    ///
    /// @dev there is a limit on the number of fields a struct can have when being passed
    /// or returned as a memory variable which can cause "Stack too deep" errors
    /// use sub-structs to avoid this issue
    /// @param addresses address values
    /// @param numbers number values
    /// @param flags boolean values
    ///
    struct Props {
        Addresses addresses;
        Numbers numbers;
        Flags flags;
    }
    ///
    /// @param account account to withdraw for.
    /// @param receiver address that will receive the withdrawn tokens.
    /// @param callbackContract  contract that will be called back.
    /// @param uiFeeReceiver ui fee receiver.
    /// @param market market on which the withdrawal will be executed.
    ///
    struct Addresses {
        address account;
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address[] longTokenSwapPath;
        address[] shortTokenSwapPath;
    }

    ///
    /// @param marketTokenAmount amount of market tokens that will be withdrawn.
    /// @param minLongTokenAmount minimum amount of long tokens that must be withdrawn.
    /// @param minShortTokenAmount minimum amount of short tokens that must be withdrawn.
    /// @param updatedAtBlock block at which the withdrawal was last updated.
    /// @param executionFee execution fee for the withdrawal.
    /// @param callbackGasLimit gas limit for calling the callback contract.
    ///
    struct Numbers {
        uint256 marketTokenAmount;
        uint256 minLongTokenAmount;
        uint256 minShortTokenAmount;
        uint256 updatedAtBlock;
        uint256 executionFee;
        uint256 callbackGasLimit;
    }

    ///
    /// @param shouldUnwrapNativeToken whether to unwrap the native token when
    ///
    struct Flags {
        bool shouldUnwrapNativeToken;
    }

    ///
    /// @dev CreateWithdrawalParams struct used in creating withdrawal request to avoid stack too deep errors
    /// @param receiver  address that will receive the withdrawal tokens.
    /// @param callbackContract contract that will be called back.
    /// @param market market on which the withdrawal will be executed.
    /// @param minLongTokenAmount minimum amount of long tokens that must be withdrawn.
    /// @param minShortTokenAmount minimum amount of short tokens that must be withdrawn.
    /// @param shouldUnwrapNativeToken whether the native token should be unwrapped when executing the withdrawal.
    /// @param executionFee execution fee for the withdrawal.
    /// @param callbackGasLimit gas limit for calling the callback contract.
    ///
    struct CreateWithdrawalParams {
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address[] longTokenSwapPath;
        address[] shortTokenSwapPath;
        uint256 minLongTokenAmount;
        uint256 minShortTokenAmount;
        bool shouldUnwrapNativeToken;
        uint256 executionFee;
        uint256 callbackGasLimit;
    }
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

///
/// @title Deposit
/// @notice Struct for deposits
/// @dev there is a limit on the number of fields a struct can have when being passed
/// or returned as a memory variable which can cause "Stack too deep" errors
///
library Deposit {
    ///
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
    /// @param account the account depositing liquidity
    /// @param receiver the address to send the liquidity tokens to
    /// @param callbackContract the callback contract
    /// @param uiFeeReceiver the ui fee receiver
    /// @param market the market to deposit to
    ///
    struct Addresses {
        address account;
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address initialLongToken;
        address initialShortToken;
        address[] longTokenSwapPath;
        address[] shortTokenSwapPath;
    }

    ///
    /// @param initialLongTokenAmount the amount of long tokens to deposit
    /// @param initialShortTokenAmount the amount of short tokens to deposit
    /// @param minMarketTokens the minimum acceptable number of liquidity tokens
    /// @param updatedAtBlock the block that the deposit was last updated at
    /// sending funds back to the user in case the deposit gets cancelled
    /// @param executionFee the execution fee for keepers
    /// @param callbackGasLimit the gas limit for the callbackContract
    ///
    struct Numbers {
        uint256 initialLongTokenAmount;
        uint256 initialShortTokenAmount;
        uint256 minMarketTokens;
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
    /// @dev CreateDepositParams struct used in creating deposit request to avoid stack too deep errors
    /// @param receiver the address to send the market tokens to
    /// @param callbackContract the callback contract
    /// @param uiFeeReceiver the ui fee receiver
    /// @param market the market to deposit into
    /// @param minMarketTokens the minimum acceptable number of liquidity tokens
    /// @param shouldUnwrapNativeToken whether to unwrap the native token when
    /// sending funds back to the user in case the deposit gets cancelled
    /// @param executionFee the execution fee for keepers
    /// @param callbackGasLimit the gas limit for the callbackContract
    ///
    struct CreateDepositParams {
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address initialLongToken;
        address initialShortToken;
        address[] longTokenSwapPath;
        address[] shortTokenSwapPath;
        uint256 minMarketTokens;
        bool shouldUnwrapNativeToken;
        uint256 executionFee;
        uint256 callbackGasLimit;
    }
}

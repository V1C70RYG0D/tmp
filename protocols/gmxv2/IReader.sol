// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Market.sol";
import "./Deposit.sol";
import "./Withdrawal.sol";

//
/// @title Reader interface
/// @notice interface towards GMX Reader contract
/// @dev library for read methods
///
interface IReader {
    ///
    /// @dev gets market from data store
    /// @param dataStore datastore address
    /// @param key market unique key
    /// @return struct Market.Props
    ///
    function getMarket(
        address dataStore,
        address key
    ) external view returns (Market.Props memory);

    ///
    /// @dev gets deposit from data store
    /// @param dataStore datastore address
    /// @param key deposit unique key
    /// @return struct Deposit.Props
    ///
    function getDeposit(
        address dataStore,
        bytes32 key
    ) external view returns (Deposit.Props memory);

    ///
    /// @dev gets withdrawal from data store
    /// @param dataStore datastore address
    /// @param key withdrawal unique key
    /// @return struct Withdrawal.Props
    ///
    function getWithdrawal(
        address dataStore,
        bytes32 key
    ) external view returns (Withdrawal.Props memory);

    ///
    /// @dev gives amounts in market tokens based on amount of GMX tokens to burn
    /// @param dataStore address of datastore
    /// @param market target market for which query is executed - Market.Props
    /// @param prices set prices for market - Market.MarketPrices
    /// @param marketTokenAmount amount of GMX tokens to burn
    /// @param uiFeeReceiver UI fee receiver address
    /// @return amounts of long and short token to receive
    ///
    function getWithdrawalAmountOut(
        address dataStore,
        Market.Props memory market,
        Market.MarketPrices memory prices,
        uint256 marketTokenAmount,
        address uiFeeReceiver
    ) external view returns (uint256, uint256);

    ///
    /// @dev gives amount of GMX tokens received based on amount of tokens deposited
    /// @param dataStore address of datastore
    /// @param market target market for which query is executed - Market.Props
    /// @param prices set prices for market - Market.MarketPrices
    /// @param longTokenAmount amount of long token deposited
    /// @param shortTokenAmount amount of short token deposited
    /// @param uiFeeReceiver UI fee receiver address
    /// @return amount of GMX tokens to receive
    ///
    function getDepositAmountOut(
        address dataStore,
        Market.Props memory market,
        Market.MarketPrices memory prices,
        uint256 longTokenAmount,
        uint256 shortTokenAmount,
        address uiFeeReceiver
    ) external view returns (uint256);
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./Price.sol";

///
/// @title Market
/// @notice Struct for markets
/// @dev markets are are created by specifying a long collateral token,
/// short collateral token and index token
///
library Market {
    ///
    /// @param marketToken address of the market token for the market
    /// @param indexToken address of the index token for the market
    /// @param longToken address of the long token for the market
    /// @param shortToken address of the short token for the market
    ///
    struct Props {
        address marketToken;
        address indexToken;
        address longToken;
        address shortToken;
    }

    ///
    /// @param indexTokenPrice price of the market's index token
    /// @param longTokenPrice price of the market's long token
    /// @param shortTokenPrice price of the market's short token
    ///
    struct MarketPrices {
        Price.Props indexTokenPrice;
        Price.Props longTokenPrice;
        Price.Props shortTokenPrice;
    }
}

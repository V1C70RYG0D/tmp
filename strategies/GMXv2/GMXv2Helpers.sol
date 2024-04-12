// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

///
/// @title Helper library for GMXv2 strategy
/// @notice used for adjusting decimals when converting tokens
///
library GMXv2Helpers {
    ///
    /// @dev adjust to amount to different decimals precision
    /// @param amount amount to adjust
    /// @param divDecimals decimals from
    /// @param mulDecimals decimals to
    /// @return value with mulDecimals precision
    ///
    function adjustForDecimals(
        uint256 amount,
        uint256 divDecimals,
        uint256 mulDecimals
    ) internal pure returns (uint256) {
        return (amount * 10 ** mulDecimals) / 10 ** divDecimals;
    }

    ///
    /// @dev adjust to amount to different decimals precision for signed integer
    /// @param amount amount to adjust
    /// @param divDecimals decimals from
    /// @param mulDecimals decimals to
    /// @return value with mulDecimals precision
    ///
    function adjustForDecimalsInt(
        int256 amount,
        uint256 divDecimals,
        uint256 mulDecimals
    ) internal pure returns (int256) {
        return (amount * int256(10 ** mulDecimals)) / int256(10 ** divDecimals);
    }

    ///
    /// @dev adjust amount to price precision needed to build market prices
    /// @param amount amount to covert to different precision
    /// @param decimals decimals precision which token has on GMX API (eg. https://arbitrum-api.gmxinfra.io/prices/tickers)
    /// @return amount in precision aligned to GMX API token precision
    ///
    function adjustPriceDecimals(
        uint256 amount,
        uint8 decimals
    ) internal pure returns (uint256) {
        return amount * 10 ** (decimals - 8);
    }
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

///
/// @title Price
/// @notice library for price types
///
library Price {
    ///
    /// @param min the min price
    /// @param max the max price
    ///
    struct Props {
        uint256 min;
        uint256 max;
    }

    ///
    /// @dev SetPricesParams struct for values required in DepositHandler.executeDeposit or WithdrawalHandler.executeWithdrawal
    /// @param signerInfo compacted indexes of signers, the index is used to retrieve
    /// the signer address from the OracleStore
    /// @param tokens list of tokens to set prices for
    /// @param compactedOracleBlockNumbers compacted oracle block numbers
    /// @param compactedOracleTimestamps compacted oracle timestamps
    /// @param compactedDecimals compacted decimals for prices
    /// @param compactedMinPrices compacted min prices
    /// @param compactedMinPricesIndexes compacted min price indexes
    /// @param compactedMaxPrices compacted max prices
    /// @param compactedMaxPricesIndexes compacted max price indexes
    /// @param signatures signatures of the oracle signers
    /// @param priceFeedTokens tokens to set prices for based on an external price feed value
    ///
    struct SetPricesParams {
        uint256 signerInfo;
        address[] tokens;
        uint256[] compactedMinOracleBlockNumbers;
        uint256[] compactedMaxOracleBlockNumbers;
        uint256[] compactedOracleTimestamps;
        uint256[] compactedDecimals;
        uint256[] compactedMinPrices;
        uint256[] compactedMinPricesIndexes;
        uint256[] compactedMaxPrices;
        uint256[] compactedMaxPricesIndexes;
        bytes[] signatures;
        address[] priceFeedTokens;
        address[] realtimeFeedTokens;
        bytes[] realtimeFeedData;
    }
}

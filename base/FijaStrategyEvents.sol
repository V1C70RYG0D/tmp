// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

///
/// @title Strategy events
/// @notice Generic events used by Fija strategies
///
library FijaStrategyEvents {
    ///
    /// @dev emits when rebalance executes
    /// @param timestamp current timestamp when rebalance is executed
    /// @param data metadata associated with event
    ///
    event Rebalance(uint256 indexed timestamp, string data);

    ///
    /// @dev emits when harvest executes
    /// @param timestamp current timestamp when harvest is executed
    /// @param harvestResult amount of harvested funds
    /// @param profitShare amount of profits
    /// @param profitToken address of profit token
    /// @param data metadata associated with event
    ///
    event Harvest(
        uint256 indexed timestamp,
        uint256 harvestResult,
        uint256 profitShare,
        address profitToken,
        string data
    );

    ///
    /// @dev emits when emergency mode is toggled
    /// @param timestamp current timestamp when emergency mode is toggled
    /// @param turnOn flag for turning on/off emergency mode
    ///
    event EmergencyMode(uint256 indexed timestamp, bool turnOn);
}

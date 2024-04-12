// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./IFijaERC4626Base.sol";

///
/// @title FijaStrategy interface
/// @author Fija
/// @notice Expanding base IFijaERC4626Base to support strategy specific methods
///
interface IFijaStrategy is IFijaERC4626Base {
    ///
    /// @dev check if there is a need to rebalance strategy funds
    /// @return bool indicating need for rebalance
    ///
    function needRebalance() external view returns (bool);

    ///
    /// @dev executes strategy rebalancing
    ///
    function rebalance() external payable;

    ///
    /// @dev check if there is a need to harvest strategy funds
    /// @return bool indicating need for harvesting
    ///
    function needHarvest() external view returns (bool);

    ///
    /// @dev executes strategy harvesting
    ///
    function harvest() external payable;

    ///
    /// @dev gets emergency mode status of strategy
    /// @return flag indicting emergency mode status
    ///
    function emergencyMode() external view returns (bool);

    ///
    /// @dev sets emergency mode on/off
    /// @param turnOn toggle flag
    ///
    function setEmergencyMode(bool turnOn) external payable;

    ///
    /// @dev check if there is a need for setting strategy in emergency mode
    /// @return bool indicating need for emergency mode
    ///
    function needEmergencyMode() external view returns (bool);

    ///
    /// @dev gets various strategy status parameters
    /// @return status parameters as string
    ///
    function status() external view returns (string memory);
}

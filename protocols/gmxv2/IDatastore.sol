// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

///
/// @title Datastore interface
/// @notice Interface towards GMX Datastore contract
///
interface IDatastore {
    ///
    /// @dev get the uint value for the given key
    /// @param key the key of the value
    /// @return the uint value for the key
    ///
    function getUint(bytes32 key) external view returns (uint256);

    ///
    /// @dev set the uint value for the given key
    /// @param key the key of the value
    /// @param value the value to set
    /// @return the uint value for the key
    ///
    function setUint(bytes32 key, uint256 value) external returns (uint256);
}

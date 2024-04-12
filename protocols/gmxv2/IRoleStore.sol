// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//
/// @title RoleStore interface
/// @notice interface towards GMX RoleStore contract
/// @dev used to query contract roles
///
interface IRoleStore {
    ///
    /// @dev Returns true if the given account has the specified role
    /// @param account address of the account
    /// @param roleKey  key of the role
    /// @return true if the account has the role, false otherwise
    ///
    function hasRole(
        address account,
        bytes32 roleKey
    ) external view returns (bool);
}

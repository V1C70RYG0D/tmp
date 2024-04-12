// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./IFijaStrategy.sol";

///
/// @title FijaStrategy2Txn interface
/// @author Fija
/// @notice Expanding base IFijaStrategy to be able to estimate gas limit for GMX keeper execution fee
///
interface IFijaStrategy2Txn is IFijaStrategy {
    ///
    /// @dev based on Tlong calculation returns gas limit for deposit or withdrawal branch
    /// @param t parameter for Tlong calculation which is basis to decide if gas limit is
    /// for deposit or withdrawal case
    /// @return gas limit for calculating gmx keeper execution fee
    ///
    function getExecutionGasLimit(int256 t) external view returns (uint256);
}

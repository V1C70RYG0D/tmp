// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

// there is a known issue with prbmath v3.x releases
// https://github.com/PaulRBerg/prbmath/issues/178
// due to this, either prbmath v2.x or v4.x versions should be used instead
import "prb-math/contracts/PRBMathUD60x18.sol";

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

///
/// @title Precision
/// @notice library for precision values and conversions
///
library Precision {
    using SafeCast for uint256;

    uint256 public constant FLOAT_PRECISION = 10 ** 30;
    uint256 public constant FLOAT_PRECISION_SQRT = 10 ** 15;

    uint256 public constant WEI_PRECISION = 10 ** 18;
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    uint256 public constant FLOAT_TO_WEI_DIVISOR = 10 ** 12;

    ///
    /// @dev applies the given factor to the given value and returns the result
    /// @param value  value to apply the factor to
    /// @param factor  factor to apply
    /// @return  result of applying the factor to the value
    ///
    function applyFactor(
        uint256 value,
        uint256 factor
    ) internal pure returns (uint256) {
        return mulDiv(value, factor, FLOAT_PRECISION);
    }

    ///
    /// @dev Calculates floor(x * numerator / denominator)
    /// @param value to apply multiplication and division
    /// @param numerator numerator
    /// @param denominator denominator
    /// @return result of calculation in full precision
    function mulDiv(
        uint256 value,
        uint256 numerator,
        uint256 denominator
    ) internal pure returns (uint256) {
        return Math.mulDiv(value, numerator, denominator);
    }
}

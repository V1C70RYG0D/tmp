// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

interface IGmxGlpRewardRouter {
    function feeGlpTracker() external view returns (address);

    function stakedGlpTracker() external view returns (address);

    function mintAndStakeGlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minGlp
    ) external returns (uint256);

    function unstakeAndRedeemGlp(
        address _tokenOut,
        uint256 _glpAmount,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256);
}

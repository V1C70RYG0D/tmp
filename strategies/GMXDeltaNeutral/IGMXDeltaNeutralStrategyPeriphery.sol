// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IGMXDeltaNeutralStrategyPeriphery {
    function needRebalanceParams()
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256);

    function harvestParams() external view returns (uint256, uint256);

    function vLongVshort() external view returns (uint256, uint256);

    function genericInvestmetLogicParams(
        int256 t
    ) external view returns (int256, int256, uint256, uint256, uint256, uint256, uint256);

    function investTlongWithdraw() external view returns (uint256, uint256);

    function investLBtcWithdraw() external view returns (uint256, uint256);

    function investLEthWithdraw() external view returns (uint256, uint256);

    function flashFee() external view returns (uint256);

    function investTlongDeposit() external view returns (uint256, uint256);

    function usdcLoanEthParams() external view returns (uint256, uint256, uint256);

    function usdcLoanBtcParams()
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256);

    function status() external view returns (string memory);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IBooster {
    function owner() external view returns (address);

    function feeToken() external view returns (address);

    function feeDistro() external view returns (address);

    function lockFees() external view returns (address);

    function stakerRewards() external view returns (address);

    function lockRewards() external view returns (address);

    function setVoteDelegate(address _voteDelegate) external;

    function vote(
        uint256 _voteId,
        address _votingAddress,
        bool _support
    ) external returns (bool);

    function voteGaugeWeight(
        address[] calldata _gauge,
        uint256[] calldata _weight
    ) external returns (bool);

    function poolInfo(
        uint256 _pid
    )
        external
        view
        returns (
            address _lptoken,
            address _token,
            address _gauge,
            address _crvRewards,
            address _stash,
            bool _shutdown
        );

    function earmarkRewards(uint256 _pid) external returns (bool);

    function earmarkFees() external returns (bool);

    function isShutdown() external view returns (bool);

    function poolLength() external view returns (uint256);

    function depositAll(uint256 _pid, bool _stake) external returns (bool);

    function deposit(
        uint256 _pid,
        uint256 _amount,
        bool _stake
    ) external returns (bool);

    function withdraw(uint256 _pid, uint256 _amount) external returns (bool);

    function withdrawAll(uint256 _pid) external returns (bool);

    function withdrawTo(
        uint256 _pid,
        uint256 _amount,
        address _to
    ) external returns (bool);
}

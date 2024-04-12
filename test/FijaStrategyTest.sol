// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../base/FijaStrategy.sol";

contract FijaStrategyTest is FijaStrategy {
    bool _needRebalance = false;
    bool _needEmergencyMode = false;
    bool _needHarvest = false;
    uint _totalSupplyTest = 0;
    uint _totalAssetsTest = 0;

    constructor(
        IERC20 asset_,
        address governance_,
        string memory tokenName_,
        string memory tokenSymbol_,
        uint256 maxTicketSize_,
        uint256 maxVaultValue_
    )
        FijaStrategy(
            asset_,
            governance_,
            tokenName_,
            tokenSymbol_,
            maxTicketSize_,
            maxVaultValue_
        )
    {}

    function needRebalance() external view virtual override returns (bool) {
        return _needRebalance;
    }

    function needHarvest() external view virtual override returns (bool) {
        return _needHarvest;
    }

    function needEmergencyMode() external view virtual override returns (bool) {
        return _needEmergencyMode;
    }

    function setNeedEmergencyMode(bool needEmergencyMode_) external virtual {
        _needEmergencyMode = needEmergencyMode_;
    }

    function setRebalance(bool turnOn) external virtual {
        _needRebalance = turnOn;
    }

    function setHarvest(bool turnOn) external virtual {
        _needHarvest = turnOn;
    }

    function totalAssets() public view virtual override returns (uint256) {
        return _totalAssetsTest;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupplyTest;
    }

    function setTotalAssets(uint totalAssets_) public virtual {
        _totalAssetsTest = totalAssets_;
    }

    function setTotalSupply(uint totalSupply_) public virtual {
        _totalSupplyTest = totalSupply_;
    }
}

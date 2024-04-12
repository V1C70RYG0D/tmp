// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../base/FijaVault.sol";

contract FijaVaultTest is FijaVault {
    uint _totalSupplyTest = 0;
    uint _totalAssetsTest = 0;

    constructor(
        IFijaStrategy strategy_,
        IERC20 asset_,
        string memory tokenName_,
        string memory tokenSymbol_,
        address governance_,
        address reseller_,
        uint256 approvalDelay_,
        uint256 maxTicketSize_,
        uint256 maxVaultValue_
    )
        FijaVault(
            strategy_,
            asset_,
            tokenName_,
            tokenSymbol_,
            governance_,
            reseller_,
            approvalDelay_,
            maxTicketSize_,
            maxVaultValue_
        )
    {}

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

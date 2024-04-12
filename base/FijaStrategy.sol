// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
pragma abicoder v2;

import "@openzeppelin/contracts/utils/Strings.sol";

import "./FijaERC4626Base.sol";
import "../interfaces/IFijaStrategy.sol";

import "./FijaStrategyEvents.sol";

///
/// @title Strategy Base contract
/// @author Fija
/// @notice Used as template for implementing strategy
/// @dev there are methods with minimum or no functionality
/// it is responsibility of child contracts to override them
///
contract FijaStrategy is IFijaStrategy, FijaERC4626Base {
    bool internal _isEmergencyMode = false;

    constructor(
        IERC20 asset_,
        address governance_,
        string memory tokenName_,
        string memory tokenSymbol_,
        uint256 maxTicketSize_,
        uint256 maxVaultValue_
    )
        FijaERC4626Base(
            asset_,
            governance_,
            address(0),
            tokenName_,
            tokenSymbol_,
            maxTicketSize_,
            maxVaultValue_
        )
    {}

    ///
    /// @dev Throws if strategy is emergency modes
    ///
    modifier emergencyModeRestriction() {
        _emergencyModeRestriction();
        _;
    }

    ///
    /// NOTE: only governance access
    /// @inheritdoc IFijaACL
    ///
    function addAddressToWhitelist(
        address addr
    ) public virtual override onlyGovernance returns (bool) {
        return super.addAddressToWhitelist(addr);
    }

    ///
    /// NOTE: only governance access
    /// @inheritdoc IFijaACL
    ///
    function removeAddressFromWhitelist(
        address addr
    ) public virtual override onlyGovernance returns (bool) {
        return super.removeAddressFromWhitelist(addr);
    }

    ///
    /// @inheritdoc IFijaStrategy
    ///
    function needRebalance() external view virtual override returns (bool) {
        return false;
    }

    ///
    /// NOTE: Only governance access; Not implemented
    /// emits IFijaStrategy.Rebalance
    /// @inheritdoc IFijaStrategy
    ///
    function rebalance()
        external
        payable
        virtual
        override
        onlyGovernance
        emergencyModeRestriction
    {
        emit FijaStrategyEvents.Rebalance(block.timestamp, "");
    }

    ///
    /// @inheritdoc IFijaStrategy
    ///
    function needHarvest() external view virtual override returns (bool) {
        return false;
    }

    ///
    /// NOTE: Only governance access; Not implemented
    /// emits IFijaStrategy.Harvest
    /// @inheritdoc IFijaStrategy
    ///
    function harvest()
        external
        payable
        virtual
        override
        onlyGovernance
        emergencyModeRestriction
    {
        emit FijaStrategyEvents.Harvest(block.timestamp, 0, 0, asset(), "");
    }

    ///
    /// @inheritdoc IFijaStrategy
    ///
    function needEmergencyMode() external view virtual override returns (bool) {
        return false;
    }

    ///
    /// NOTE: Only governance access; Not implemented
    /// emits IFijaStrategy.EmergencyMode
    /// @inheritdoc IFijaStrategy
    ///
    function setEmergencyMode(
        bool turnOn
    ) external payable virtual override onlyGovernance {
        _isEmergencyMode = turnOn;
        emit FijaStrategyEvents.EmergencyMode(block.timestamp, turnOn);
    }

    ///
    /// @inheritdoc IFijaStrategy
    ///
    function emergencyMode() external view virtual override returns (bool) {
        return _isEmergencyMode;
    }

    ///
    /// @inheritdoc IFijaStrategy
    ///
    function status() external view virtual override returns (string memory) {
        string memory str = string(
            abi.encodePacked("totalAssets=", Strings.toString(totalAssets()))
        );

        return str;
    }

    ///
    /// NOTE: emergency mode check
    /// @inheritdoc FijaERC4626Base
    ///
    function deposit(
        uint256 assets,
        address receiver
    )
        public
        payable
        virtual
        override(FijaERC4626Base, IERC4626)
        emergencyModeRestriction
        returns (uint256)
    {
        return super.deposit(assets, receiver);
    }

    ///
    /// @dev helper for modifier - checks if strategy is in emergency mode
    ///
    function _emergencyModeRestriction() internal view virtual {
        if (_isEmergencyMode) {
            revert FijaInEmergencyMode();
        }
    }

    receive() external payable virtual {}
}

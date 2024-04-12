// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../../base/types.sol";

///
/// @title GMXv2 type library
/// @notice used to share types used in strategy contracts and libraries
///
library GMXv2Type {
    ///
    /// @dev used for passing references between transactions
    /// @param Tlong input for investment logic
    /// @param Lshort input for investment logic
    /// @param t input for investment logic
    ///
    struct CallbackData {
        int256 Tlong;
        uint256 Lshort;
        int256 t;
    }

    ///
    /// @dev used to pack vault and strategy calldata to be used between transactions
    /// @param strategyParams strategy calldata
    /// @param vaultParams vault calldata
    ///
    struct TxParamsWrapper {
        TxParams strategyParams;
        TxParams vaultParams;
    }

    ///
    /// @dev used to pass data to flashloan callback
    /// @param executionFee execution fee for GMX keeper
    /// @param key tx key to track deposit or withdrawal requested from GMX
    /// @param lshort debt amount for investment logic
    ///
    struct FlashloanCallbackMetadata {
        uint256 executionFee;
        bytes32 key;
        uint256 lshort;
    }

    ///
    /// @dev used to pack data for flashloan callback helper
    /// @param callbackData see CallbackData
    /// @param txParamsWrapper see TxParamsWrapper
    /// @param metadata see FlashloanCallbackMetadata
    /// @param amount flashloan amount
    /// @param premium flashloan fee
    /// @param Tshort
    ///
    struct FlashloanCallbackWrapper {
        CallbackData callbackData;
        TxParamsWrapper txParamsWrapper;
        FlashloanCallbackMetadata metadata;
        uint256 amount;
        uint256 premium;
        int256 Tshort;
    }

    ///
    /// @dev data used as main input to investment logic
    /// @param t see CallbackData
    /// @param executionFee execution fee for GMX keeper
    /// @param txParamsWrapper see TxParamsWrapper
    ///
    struct InvestLogicData {
        int256 t;
        uint256 executionFee;
        TxParamsWrapper txParamsWrapper;
    }

    ///
    /// @dev used for reference to strategy data used by external library
    /// @param PERIPHERY address of periphery contract
    /// @param GM_POOL address of GMX market
    /// @param SEC_CCY address of secondary ccy
    /// @param DEPOSIT_CCY address of deposit ccy
    /// @param UNISWAP_DEP_SEC_POOL address of Uniswap pool used for swaps
    /// @param UNISWAP_NATIVE_DEP_POOL address of Uniswap pool used for native to deposit swaps
    /// @param WETH wrapped native token address
    /// @param DEP_CCY_DECIMALS decimals for deposit ccy
    /// @param SEC_CCY_DECIMALS decimals for secondary ccy
    /// @param LONG_PRICE_DECIMALS decimals for long token in GMX market align with GMX API
    /// @param SHORT_PRICE_DECIMALS decimals for short token in GMX market align with GMX API
    ///
    struct StrategyData {
        address PERIPHERY;
        address GM_POOL;
        address SEC_CCY;
        address DEPOSIT_CCY;
        address UNISWAP_DEP_SEC_POOL;
        address UNISWAP_NATIVE_DEP_POOL;
        address WETH;
        uint8 DEP_CCY_DECIMALS;
        uint8 SEC_CCY_DECIMALS;
        uint8 LONG_PRICE_DECIMALS;
        uint8 SHORT_PRICE_DECIMALS;
    }

    ///
    /// @dev used for reference to strategy metadata shared with external library
    /// @param tokenPriceLastHarvest strategy token price at last harvest
    /// @param tokenMintedLastHarvest amount of strategy token supply at last harvest
    /// @param lastHarvestTime time of last harvest in seconds since Unix epoch
    /// @param flashLoanAmount current flashloan amount
    /// @param emergencyModeStartTime timetamp when emeregency mode started
    /// @param harvestModeStartTime timetamp when harvest started
    /// @param rebalanceModeStartTime timetamp when rebalance started
    /// @param isEmergencyMode flag for check is strategy in emergency mode
    /// @param isEmergencyModeInProgress flag indicating is emergency mode in progress
    /// @param isHarvestInProgress flag indicating is harvest in progress
    /// @param isRebalanceInProgress flag indicating is rebalance in progress
    ///
    struct StrategyMetadata {
        uint256 tokenPriceLastHarvest;
        uint256 tokenMintedLastHarvest;
        uint256 lastHarvestTime;
        uint256 flashLoanAmount;
        uint256 emergencyModeStartTime;
        uint256 harvestModeStartTime;
        uint256 rebalanceModeStartTime;
        bool isEmergencyMode;
        bool isEmergencyModeInProgress;
        bool isHarvestInProgress;
        bool isRebalanceInProgress;
    }
}

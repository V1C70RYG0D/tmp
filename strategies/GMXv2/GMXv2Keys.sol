// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@aave/core-v3/contracts/interfaces/IPoolDataProvider.sol";
import "@aave/core-v3/contracts/interfaces/IAaveOracle.sol";

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

///
/// @title library for GMXv2 strategy constants
/// @notice contains also keys to GMX contract addresses and references to other protocols
///
library GMXv2Keys {
    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint256 internal constant PRICE_DEVIATION_BPS = 30;

    uint256 internal constant BASIS_POINTS_DIVISOR = 10000;

    uint256 internal constant PRICE_PRECISION = 10 ** 30;

    uint256 internal constant AAVE_BASE_CURRENCY_PRECISION = 10 ** 8;

    uint256 internal constant GM_TOKEN_PRECISION = 10 ** 18;

    uint256 internal constant FIJA_HEALTH_FACTOR = 15 * 10 ** 17; //1.5

    uint256 internal constant SLIPPAGE = 30; // bps

    uint8 internal constant GM_TOKEN_DECIMALS = 18;

    uint8 internal constant PRICE_DECIMALS = 30;

    uint8 internal constant UNISWAP_FEE_DECIMALS = 6;

    ///
    /// @dev key for open interest
    ///
    bytes32 internal constant OPEN_INTEREST =
        keccak256(abi.encode("OPEN_INTEREST"));

    ///
    /// @dev key for GMX router in _contracts mapping
    ///
    bytes32 internal constant ROUTER = keccak256(abi.encode("ROUTER"));

    ///
    /// @dev key for GMX deposit vault in _contracts mapping
    ///
    bytes32 internal constant DEPOSIT_VAULT =
        keccak256(abi.encode("DEPOSIT_VAULT"));

    ///
    /// @dev key for GMX withdraw vault in _contracts mapping
    ///
    bytes32 internal constant WITHDRAW_VAULT =
        keccak256(abi.encode("WITHDRAW_VAULT"));

    ///
    /// @dev key for GMX reader in _contracts mapping
    ///
    bytes32 internal constant READER = keccak256(abi.encode("READER"));

    ///
    /// @dev key for GMX datastore in _contracts mapping
    ///
    bytes32 internal constant DATASTORE = keccak256(abi.encode("DATASTORE"));

    ///
    /// @dev key for GMX exchange router in _contracts mapping
    ///
    bytes32 internal constant EXCHANGE_ROUTER =
        keccak256(abi.encode("EXCHANGE_ROUTER"));

    ///
    /// @dev key for GMX role store in _contracts mapping
    ///
    bytes32 internal constant ROLE_STORE = keccak256(abi.encode("ROLE_STORE"));

    ///
    /// @dev key for GMX controller role
    ///
    bytes32 internal constant CONTROLLER = keccak256(abi.encode("CONTROLLER"));

    ///
    /// @dev key for the estimated gas limit for deposits
    ///
    bytes32 internal constant DEPOSIT_GAS_LIMIT =
        keccak256(abi.encode("DEPOSIT_GAS_LIMIT"));

    ///
    /// @dev key for the estimated gas limit for withdrawals
    ///
    bytes32 internal constant WITHDRAWAL_GAS_LIMIT =
        keccak256(abi.encode("WITHDRAWAL_GAS_LIMIT"));

    ///
    /// @dev key for the base gas limit used when estimating execution fee
    ///
    bytes32 internal constant ESTIMATED_GAS_FEE_BASE_AMOUNT =
        keccak256(abi.encode("ESTIMATED_GAS_FEE_BASE_AMOUNT"));

    ///
    /// @dev key for the multiplier used when estimating execution fee
    ///
    bytes32 internal constant ESTIMATED_GAS_FEE_MULTIPLIER_FACTOR =
        keccak256(abi.encode("ESTIMATED_GAS_FEE_MULTIPLIER_FACTOR"));

    ///
    /// @dev Reference to AAVE data provider,
    /// used for querying debt and collateral status
    ///
    IPoolDataProvider internal constant AAVE_IPoolDataProvider =
        IPoolDataProvider(0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654);

    ///
    /// @dev Reference to AAVE address provider,
    /// used for getting up-to-date pool address
    ///
    IPoolAddressesProvider internal constant AAVE_IPoolAddressesProvider =
        IPoolAddressesProvider(0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb);

    ///
    /// @dev Reference to AAVE oracle,
    /// used for getting token prices
    ///
    IAaveOracle internal constant AAVE_IOracle =
        IAaveOracle(0xb56c2F0B653B2e0b10C9b928C8580Ac5Df02C7C7);

    ///
    /// @dev Reference to Uniswap swap router,
    /// used for swapping tokens
    ///
    ISwapRouter internal constant Uniswap_ISwapRouter =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    ///
    /// @dev helper to get key for fetching GMX withdrawal gas limit
    /// @return key to query withdrawal gas limit
    ///
    function withdrawalGasLimitKey() internal pure returns (bytes32) {
        return keccak256(abi.encode(WITHDRAWAL_GAS_LIMIT));
    }

    ///
    /// @dev helper to get key for fetching GMX deposit gas limit
    /// @return key to query deposit gas limit
    ///
    function depositGasLimitKey(
        bool singleToken
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(DEPOSIT_GAS_LIMIT, singleToken));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "@aave/core-v3/contracts/interfaces/IAaveOracle.sol";
import "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import "@aave/core-v3/contracts/interfaces/IPoolDataProvider.sol";

import "../../interfaces/IERC4626.sol";
import "../../protocols/gmx/interfaces/IGmxGlpManager.sol";
import "../../protocols/gmx/interfaces/IGmxVault.sol";
import "../../protocols/gmx/interfaces/IGmxGlpRewardRouter.sol";
import "../../protocols/gmx/interfaces/IGmxRewardRouter.sol";

abstract contract GMXDeltaNeutralStrategyProtocols {
    // should be defined non-maxint
    uint256 internal constant FIJA_HEALTH_FACTOR = 15 * 10 ** 17; //1.5 in  18 decimals

    uint256 internal constant USDC_DECIMALS = 6;
    uint256 internal constant SGLP_DECIMALS = 18;
    uint256 internal constant WBTC_DECIMALS = 8;
    uint256 internal constant WETH_DECIMALS = 18;
    uint256 internal constant SLIPPAGE = 30; // bps
    uint256 internal constant HF_LO_THRESHOLD = 12 * 10 ** 17;
    uint256 internal constant HF_HI_THRESHOLD = 17 * 10 ** 17;
    uint256 internal constant AAVE_BASE_CURRENCY_PRECISION = 10 ** 8;

    uint256 internal constant GMX_GLP_PRECISION = 1000000000000000000; // 10^18
    uint256 internal constant GMX_BASIS_POINTS_DIVISOR = 10000;
    uint256 internal constant GMX_PRICE_PRECISION =
        1000000000000000000000000000000; // 10^30
    uint256 internal constant GMX_USDG_DECIMALS = 18;

    uint256 internal lastHarvestTime;

    int256 internal constant IMBALANCE_THRESHOLD = 30; // bps
    uint8 internal constant UNISWAP_FEE_DECIMALS = 6;

    address internal constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    address internal constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;

    address internal constant LINK = 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4;

    address internal constant UNI = 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0;

    address internal constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    address internal constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;

    address internal constant FRAX = 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F;

    address internal constant SGLP = 0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf;

    IPoolAddressesProvider internal constant AAVE_IPoolAddressesProvider =
        IPoolAddressesProvider(0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb);

    IPoolDataProvider internal constant AAVE_IPoolDataProvider =
        IPoolDataProvider(0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654);

    IAaveOracle internal constant AAVE_IOracle =
        IAaveOracle(0xb56c2F0B653B2e0b10C9b928C8580Ac5Df02C7C7);

    IGmxGlpManager internal constant GMX_IGmxGlpManager =
        IGmxGlpManager(0x3963FfC9dff443c2A94f21b129D429891E32ec18);

    IGmxVault internal constant GMX_IGmxVault =
        IGmxVault(0x489ee077994B6658eAfA855C308275EAd8097C4A);

    IGmxGlpRewardRouter internal constant GMX_IGmxGlpRewardRouter =
        IGmxGlpRewardRouter(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);

    IGmxRewardRouter internal constant GMX_IGmxRewardRouter =
        IGmxRewardRouter(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);

    ISwapRouter internal constant Uniswap_ISwapRouter =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    address internal constant UNISWAP_USDC_WETH_POOL =
        0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443;
    address internal constant UNISWAP_WBTC_WETH_POOL =
        0x2f5e87C9312fa29aed5c179E456625D79015299c;

    constructor() {}
}

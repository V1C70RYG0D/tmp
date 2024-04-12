// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
pragma abicoder v2;

import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

import "./IGMXDeltaNeutralStrategyPeriphery.sol";
import "./GMXDeltaNeutralStrategyProtocols.sol";

//************************************** */
//TODO IMPORTANT
// REMOVE FOR PRODUCTION
//************************************** */
import "hardhat/console.sol";

contract GMXDeltaNeutralStrategyPeriphery is
    GMXDeltaNeutralStrategyProtocols,
    IGMXDeltaNeutralStrategyPeriphery
{
    uint256 internal immutable MAX_TICKET_SIZE;
    uint256 internal immutable MAX_VAULT_VALUE;
    address internal immutable CORE_STRATEGY;

    constructor(
        address coreStrategy_,
        uint256 maxTicketSize_,
        uint256 maxVaultValue_
    ) {
        MAX_TICKET_SIZE = maxTicketSize_;
        MAX_VAULT_VALUE = maxVaultValue_;
        CORE_STRATEGY = coreStrategy_;
    }

    /// @dev retrieve the current compostion of the GLP index from the GMX protocol
    /// @return GLP composition in bps [btc, weth, link, uni]
    function _currentGLPComposition()
        private
        view
        returns (uint256, uint256, uint256, uint256)
    {
        uint256 usdgUSDC = GMX_IGmxVault.usdgAmounts(USDC);
        uint256 usdgWETH = GMX_IGmxVault.usdgAmounts(WETH);
        uint256 usdgWBTC = GMX_IGmxVault.usdgAmounts(WBTC);
        uint256 usdgLINK = GMX_IGmxVault.usdgAmounts(LINK);
        uint256 usdgUNI = GMX_IGmxVault.usdgAmounts(UNI);
        uint256 usdgUSDT = GMX_IGmxVault.usdgAmounts(USDT);
        uint256 usdgDAI = GMX_IGmxVault.usdgAmounts(DAI);
        uint256 usdgFRAX = GMX_IGmxVault.usdgAmounts(FRAX);

        uint256 totalAmountUsdg = usdgUSDC +
            usdgWETH +
            usdgWBTC +
            usdgLINK +
            usdgUNI +
            usdgUSDT +
            usdgDAI +
            usdgFRAX;

        return (
            (usdgWBTC * GMX_BASIS_POINTS_DIVISOR) / totalAmountUsdg,
            (usdgWETH * GMX_BASIS_POINTS_DIVISOR) / totalAmountUsdg,
            (usdgLINK * GMX_BASIS_POINTS_DIVISOR) / totalAmountUsdg,
            (usdgUNI * GMX_BASIS_POINTS_DIVISOR) / totalAmountUsdg
        );
    }

    /// @dev gets sell GLP for USDC exchange rate - without fee and slippage
    /// NOTE: uses GMX oracle
    /// @return GLP sell exchange rate for USDC in 30 decimals precision
    function _e_gsell() private view returns (uint256) {
        uint256 maxUSDCPrice = GMX_IGmxVault.getMaxPrice(USDC);
        uint256 sellGLPPrice = GMX_IGmxGlpManager.getPrice(false);

        return (sellGLPPrice * GMX_PRICE_PRECISION) / maxUSDCPrice;
    }

    /// @dev gets buy GLP for USDC exchange rate - without fee and slippage
    /// NOTE: uses GMX oracle
    /// @return GLP buy exchange rate for USDC in 30 decimals precision
    function _e_gbuy() private view returns (uint256) {
        uint256 minUSDCPrice = GMX_IGmxVault.getMinPrice(USDC);
        uint256 buyGLPPrice = GMX_IGmxGlpManager.getPrice(true);

        return (buyGLPPrice * GMX_PRICE_PRECISION) / minUSDCPrice;
    }

    /// @dev Retrieves exchange rate weth to usdc according
    /// NOTE: uses AAVE oracle
    /// @return weth exchange rate for USDC in 8 decimals precision
    function _a_eth() private view returns (uint256) {
        uint256 a_usdc_usd = AAVE_IOracle.getAssetPrice(USDC);
        uint256 a_weth_usd = AAVE_IOracle.getAssetPrice(WETH);

        return (a_weth_usd * AAVE_BASE_CURRENCY_PRECISION) / a_usdc_usd;
    }

    /// @dev Retrieves exchange rate wbtc to usdc according to aave oracle
    /// NOTE: uses AAVE oracle
    /// @return wbtc exchange rate for USDC in 8 decimals precision
    function _a_btc() private view returns (uint256) {
        uint256 a_usdc_usd = AAVE_IOracle.getAssetPrice(USDC);
        uint256 a_wbtc_usd = AAVE_IOracle.getAssetPrice(WBTC);

        return (a_wbtc_usd * AAVE_BASE_CURRENCY_PRECISION) / a_usdc_usd;
    }

    /// @dev see _a_eth()
    function _r_eth() private view returns (uint256) {
        return _a_eth();
    }

    /// @dev see _r_wbtc()
    function _r_btc() private view returns (uint256) {
        return _a_btc();
    }

    /// @dev Retrieves swap fee wbtc to usdc for uniswap and vice versa
    /// swap is routed USDC -> WETH -> WBTC and vice t incurring 2 pool fees
    /// Only approximate. Does not take into account slippage and the midpoint rate
    /// Uniswap pool midpoint might be off from oracle rate
    /// NOTE: fee calculation is not fully correct as it has 2 swaps in series
    /// @return swap fee between wbtc and usdc in bps
    function _g_sbtc() private view returns (uint256) {
        uint256 btcEthFee = IUniswapV3Pool(UNISWAP_WBTC_WETH_POOL).fee();
        uint256 ethUsdcFee = IUniswapV3Pool(UNISWAP_USDC_WETH_POOL).fee();
        // convert to bps
        return
            _adjustForDecimals(btcEthFee + ethUsdcFee, UNISWAP_FEE_DECIMALS, 4);
    }

    /// @dev Retrieves swap fee eth to usdc for uniswap and vice versa
    /// Only approximate. Does not take into account slippage and the midpoint rate
    /// Uniswap pool midpoint might be off from oracle rate
    /// @return swap fee between eth and usdc in bps
    function _g_seth() private view returns (uint256) {
        uint256 ethUsdcFee = IUniswapV3Pool(UNISWAP_USDC_WETH_POOL).fee();
        // convert it to bps
        return _adjustForDecimals(ethUsdcFee, UNISWAP_FEE_DECIMALS, 4);
    }

    /// @dev gets flashloan fee
    /// NOTE: recommended is to get Pool through PoolAddressesProvider
    /// @return fee in bps
    function _g_flash() private view returns (uint128) {
        IPool pool = IPool(AAVE_IPoolAddressesProvider.getPool());
        return pool.FLASHLOAN_PREMIUM_TOTAL();
    }

    /// @dev fee for buying glp for USDC, calculated based on fixed MAX_TICKET_SIZE amount
    /// NOTE: uses GMX oracle
    /// @return glp buy fee for usdc in bps
    function _g_gbuy() private view returns (uint256) {
        uint256 minUSDCPrice = GMX_IGmxVault.getMinPrice(USDC);
        uint256 amountInUSDG = (MAX_TICKET_SIZE * minUSDCPrice) /
            GMX_PRICE_PRECISION;

        amountInUSDG = _adjustForDecimals(
            amountInUSDG,
            USDC_DECIMALS,
            GMX_USDG_DECIMALS
        );

        uint256 mintBurnFeeBasisPoints = GMX_IGmxVault.mintBurnFeeBasisPoints();
        uint256 taxBasisPoints = GMX_IGmxVault.taxBasisPoints();

        return
            GMX_IGmxVault.getFeeBasisPoints(
                USDC,
                amountInUSDG,
                mintBurnFeeBasisPoints,
                taxBasisPoints,
                true
            );
    }

    /// @dev fee for selling glp for USDC, calculated based on fixed MAX_TICKET_SIZE amount
    /// NOTE: uses GMX oracle
    /// @return glp sell fee for usdc in bps
    function _g_gsell() private view returns (uint256) {
        uint256 maxUSDCPrice = GMX_IGmxVault.getMaxPrice(USDC);
        uint256 amountInUSDG = (MAX_TICKET_SIZE * maxUSDCPrice) /
            GMX_PRICE_PRECISION;

        amountInUSDG = _adjustForDecimals(
            amountInUSDG,
            USDC_DECIMALS,
            GMX_USDG_DECIMALS
        );

        uint256 mintBurnFeeBasisPoints = GMX_IGmxVault.mintBurnFeeBasisPoints();
        uint256 taxBasisPoints = GMX_IGmxVault.taxBasisPoints();

        return
            GMX_IGmxVault.getFeeBasisPoints(
                USDC,
                amountInUSDG,
                mintBurnFeeBasisPoints,
                taxBasisPoints,
                false
            );
    }

    /// @dev adjusts result considering different decimal precisions
    /// @param amount to adjust
    /// @param divDecimals 10^divDecimals to divide amount
    /// @param mulDecimals 10^mulDecimals to multiply amount
    /// @return adjusted result
    function _adjustForDecimals(
        uint256 amount,
        uint256 divDecimals,
        uint256 mulDecimals
    ) private pure returns (uint256) {
        return (amount * 10 ** mulDecimals) / (10 ** divDecimals);
    }

    /// @dev retreives the long side of investment
    /// @return amount GLP tokens strategy has
    function _c_long() private view returns (uint256) {
        return IERC20(SGLP).balanceOf(CORE_STRATEGY);
    }

    /// @dev gets collateral on Aave which is strategy short position in USDC
    /// @return collateral amount on Aave in aArbUSDC tokens
    function _c_short() private view returns (uint256) {
        (address aToken, , ) = AAVE_IPoolDataProvider.getReserveTokensAddresses(
            USDC
        );

        return IERC20(aToken).balanceOf(CORE_STRATEGY);
    }

    /// @dev retrieves the balance of aave eth loan in number of native tokens and native precision
    /// @return loan amount expressed in aave eth tokens (sArbWETH + vArbWETH)
    function _l_eth() private view returns (uint256) {
        (
            ,
            address stableDebtToken,
            address variableDebtToken
        ) = AAVE_IPoolDataProvider.getReserveTokensAddresses(WETH);

        uint256 variableDebt = IERC20(variableDebtToken).balanceOf(
            CORE_STRATEGY
        );
        uint256 stableDebt = IERC20(stableDebtToken).balanceOf(CORE_STRATEGY);

        return variableDebt + stableDebt;
    }

    /// @dev retrieves the balance of aave btc loan in number of native tokens and native precision
    /// @return loan amount expressed in aave btc tokens  (sArbWBTC + vArbWBTC)
    function _l_btc() private view returns (uint256) {
        (
            ,
            address stableDebtToken,
            address variableDebtToken
        ) = AAVE_IPoolDataProvider.getReserveTokensAddresses(WBTC);

        uint256 variableDebt = IERC20(variableDebtToken).balanceOf(
            CORE_STRATEGY
        );
        uint256 stableDebt = IERC20(stableDebtToken).balanceOf(CORE_STRATEGY);

        return variableDebt + stableDebt;
    }

    /// @dev retrieves health factor of strategy in Aave
    /// @return current health factor in 18 decimals
    function _h() private view returns (uint256) {
        IPool pool = IPool(AAVE_IPoolAddressesProvider.getPool());

        (, , , , , uint256 healthFactor) = pool.getUserAccountData(
            CORE_STRATEGY
        );

        return healthFactor;
    }

    /// @dev retrieves liquidation threshold of USDC in Aave
    /// multiple configuration data inside uint256, need to use mask to extract bits
    /// @return USDC liqudation threshold in bps
    function _q() private view returns (uint256) {
        IPool pool = IPool(AAVE_IPoolAddressesProvider.getPool());
        DataTypes.ReserveConfigurationMap memory map = pool.getConfiguration(
            USDC
        );
        uint256 target = map.data >> 16;
        uint256 mask = (1 << 16) - 1;
        return target & mask;
    }

    /// @dev calculates long position
    /// The current value on the long side is the amount of GLP we have,
    /// minus the fees needed to sell the GLP to usdc.
    /// NOTE: we calculate sell glp fee assuming selling all glp
    /// @return amount of usdc received from selling GLP
    function _v_long() private view returns (uint256) {
        uint256 usdcAmount = (_c_long() * _e_gsell()) / GMX_PRICE_PRECISION;
        usdcAmount = _adjustForDecimals(
            usdcAmount,
            SGLP_DECIMALS,
            USDC_DECIMALS
        );

        return ((usdcAmount * (GMX_BASIS_POINTS_DIVISOR - _g_gsell())) /
            GMX_BASIS_POINTS_DIVISOR);
    }

    /// @dev calculates short position
    /// The current value on the short side is the amount of USDC collateral in Aave
    /// minus the cost to unwind the short positions.
    /// @return amount of usdc in short position in Aave
    function _v_short() private view returns (uint256) {
        uint256 btcUnwind = (((((_l_btc() * _r_btc()) /
            AAVE_BASE_CURRENCY_PRECISION) * GMX_BASIS_POINTS_DIVISOR) /
            (GMX_BASIS_POINTS_DIVISOR - _g_flash())) *
            GMX_BASIS_POINTS_DIVISOR) / (GMX_BASIS_POINTS_DIVISOR - _g_sbtc());

        btcUnwind = _adjustForDecimals(btcUnwind, WBTC_DECIMALS, USDC_DECIMALS);

        uint256 ethUnwind = (((((_l_eth() * _r_eth()) /
            AAVE_BASE_CURRENCY_PRECISION) * GMX_BASIS_POINTS_DIVISOR) /
            (GMX_BASIS_POINTS_DIVISOR - _g_flash())) *
            GMX_BASIS_POINTS_DIVISOR) / (GMX_BASIS_POINTS_DIVISOR - _g_seth());

        ethUnwind = _adjustForDecimals(ethUnwind, WETH_DECIMALS, USDC_DECIMALS);

        return _c_short() - ethUnwind - btcUnwind;
    }

    /*****************************************
     ******* T_long T_short calculation ******
     *****************************************/

    /// @notice  calculates target investment on long position
    /// @param t deposit or withdrawal amount of USDC
    /// @return target investment on long position in USDC
    function _T_long(int t) private view returns (int256) {
        if (t >= 0) {
            return _T_long_deposit(uint256(t));
        } else {
            // multiply by -1 to account for working with positive t in call
            return _T_long_withdraw(t);
        }
    }

    /// @notice  calculates target investment on short position
    /// @param t deposit or withdrawal amount of USDC (signed integer)
    /// @return target investment on short position in USDC
    function _T_short(int t) private view returns (int256) {
        return t - _T_long(t);
    }

    /// @notice  calculates target investment on long position for deposits
    /// _denominatorTlongDeposit(t) is in 30 decimals precision so we need to multiply
    /// with 10^30 take this into account
    /// @param t deposit amount of USDC
    /// @return target investment on long position in USDC
    function _T_long_deposit(uint256 t) private view returns (int256) {
        return
            (_numeratorTlongDeposit(t) * int256(GMX_PRICE_PRECISION)) /
            _denominatorTlongDeposit();
    }

    /// @notice  calculates target investment on long position for withdrawal
    /// _denominatorTlongWithdraw(t) is in bps so we need to multiply
    /// with 10^4 take this into account
    /// @param t withdraw amount of USDC
    /// @return target investment on long position in USDC
    function _T_long_withdraw(int t) private view returns (int256) {
        return
            (_numeratorTlongWithdraw(t) * int256(GMX_BASIS_POINTS_DIVISOR)) /
            _denominatorTlongWithdraw();
    }

    function _numeratorTlongWithdraw(int t) private view returns (int256) {
        uint256 lrBtcFees = (((((_l_btc() * _r_btc()) /
            AAVE_BASE_CURRENCY_PRECISION) * GMX_BASIS_POINTS_DIVISOR) /
            (GMX_BASIS_POINTS_DIVISOR - _g_flash())) *
            GMX_BASIS_POINTS_DIVISOR) / (GMX_BASIS_POINTS_DIVISOR - _g_sbtc());

        lrBtcFees = _adjustForDecimals(lrBtcFees, WBTC_DECIMALS, USDC_DECIMALS);

        uint256 lrEthFees = (((((_l_eth() * _r_eth()) /
            AAVE_BASE_CURRENCY_PRECISION) * GMX_BASIS_POINTS_DIVISOR) /
            (GMX_BASIS_POINTS_DIVISOR - _g_flash())) *
            GMX_BASIS_POINTS_DIVISOR) / (GMX_BASIS_POINTS_DIVISOR - _g_seth());

        lrEthFees = _adjustForDecimals(lrEthFees, WETH_DECIMALS, USDC_DECIMALS);

        uint256 cLongEgSell = (_c_long() * _e_gsell()) / GMX_PRICE_PRECISION;

        cLongEgSell = _adjustForDecimals(
            cLongEgSell,
            SGLP_DECIMALS,
            USDC_DECIMALS
        );

        uint256 cLongEgSellIBtc = (cLongEgSell * _i_btc()) /
            GMX_BASIS_POINTS_DIVISOR;

        uint256 cLongEgSellIBtcFees = (((cLongEgSellIBtc *
            GMX_BASIS_POINTS_DIVISOR) /
            (GMX_BASIS_POINTS_DIVISOR - _g_flash())) *
            GMX_BASIS_POINTS_DIVISOR) / (GMX_BASIS_POINTS_DIVISOR - _g_sbtc());

        uint256 cLongEgSellIBtcHQ = (cLongEgSellIBtc * _hDivQ()) / (10 ** 18);

        uint256 cLongEgSellISum = (cLongEgSell * _i_sum()) /
            GMX_BASIS_POINTS_DIVISOR;

        uint256 cLongEgSellISumFees = (((cLongEgSellISum *
            GMX_BASIS_POINTS_DIVISOR) /
            (GMX_BASIS_POINTS_DIVISOR - _g_flash())) *
            GMX_BASIS_POINTS_DIVISOR) / (GMX_BASIS_POINTS_DIVISOR - _g_seth());

        uint256 cLongEgSellISumHQ = (cLongEgSellISum * _hDivQ()) / (10 ** 18);

        // returns numerator value in USDC
        return
            t -
            int256(
                lrBtcFees + lrEthFees + cLongEgSellIBtcHQ + cLongEgSellISumHQ
            ) +
            int256(_c_short() + cLongEgSellISumFees + cLongEgSellIBtcFees);
    }

    function _denominatorTlongWithdraw() private view returns (int256) {
        uint256 iBtcGgSell = (_i_btc() * GMX_BASIS_POINTS_DIVISOR) /
            (GMX_BASIS_POINTS_DIVISOR - _g_gsell());

        uint256 iBtcGgSellFee = (((iBtcGgSell * GMX_BASIS_POINTS_DIVISOR) /
            (GMX_BASIS_POINTS_DIVISOR - _g_flash())) *
            GMX_BASIS_POINTS_DIVISOR) / (GMX_BASIS_POINTS_DIVISOR - _g_sbtc());

        uint256 iBtcGgSellHQ = (iBtcGgSell * _hDivQ()) / (10 ** 18);

        uint256 iSumGgSell = (_i_sum() * GMX_BASIS_POINTS_DIVISOR) /
            (GMX_BASIS_POINTS_DIVISOR - _g_gsell());

        uint256 iSumGgSellFee = (((iSumGgSell * GMX_BASIS_POINTS_DIVISOR) /
            (GMX_BASIS_POINTS_DIVISOR - _g_flash())) *
            GMX_BASIS_POINTS_DIVISOR) / (GMX_BASIS_POINTS_DIVISOR - _g_sbtc());

        uint256 iSumGgSellHQ = (iSumGgSell * _hDivQ()) / (10 ** 18);

        // retuns number as bps, so we replace "1" in formula with 10^4
        return
            int256(10 ** 4) -
            int256(iBtcGgSellFee + iSumGgSellFee) +
            int256(iBtcGgSellHQ + iSumGgSellHQ);
    }

    /// @dev calculates numerator value of T_long formula on deposits
    /// NOTE:  follows progression of numerator calculation with
    /// comments of exact expression evaluated
    /// @param t amount in USDC deposited
    /// @return numerator value in USDC
    function _numeratorTlongDeposit(uint256 t) private view returns (int256) {
        // r_btc is in AAVE_BASE_CURRENCY_PRECISION we need to divide with same precision.
        // all g values are in bps so we need to replace 1 in formula with
        // 10^4 and divide expression with 10^4 to account for multipling with bps.
        // evaluates: (_l_btc * _r_btc) * (1 - _g_flash) * (1 - _g_sbtc)
        // USDC 8 decimals precision
        uint256 lrBtcFees = (((((_l_btc() * _r_btc()) /
            AAVE_BASE_CURRENCY_PRECISION) *
            (GMX_BASIS_POINTS_DIVISOR - _g_flash())) /
            GMX_BASIS_POINTS_DIVISOR) *
            (GMX_BASIS_POINTS_DIVISOR - _g_sbtc())) / GMX_BASIS_POINTS_DIVISOR;

        // need to adjust 8 to 6 decimals for USDC
        // returns USDC value in 6 decimals
        lrBtcFees = _adjustForDecimals(lrBtcFees, WBTC_DECIMALS, USDC_DECIMALS);

        // r_eth is in AAVE_BASE_CURRENCY_PRECISION we need to divide with same precision.
        // all g values are in bps so we need to replace 1 in formula with
        // 10^4 and divide expression with 10^4 to account for multipling with bps.
        // evaluates: (_l_eth * _r_eth) * (1 - _g_flash) * (1 - _g_seth)
        // USDC amount in 18 decimals precision due to conversion from eth
        uint256 lrEthFees = (((((_l_eth() * _r_eth()) /
            AAVE_BASE_CURRENCY_PRECISION) *
            (GMX_BASIS_POINTS_DIVISOR - _g_flash())) /
            GMX_BASIS_POINTS_DIVISOR) *
            (GMX_BASIS_POINTS_DIVISOR - _g_seth())) / GMX_BASIS_POINTS_DIVISOR;

        // need to adjust 18 to 6 decimals for USDC
        // returns USDC amount in 6 decimals
        lrEthFees = _adjustForDecimals(lrEthFees, WETH_DECIMALS, USDC_DECIMALS);

        // _e_gsell is calculated with 30 decimal precision so we need to divide
        // with GMX_PRICE_PRECISION to account for.
        // evaluates: (_c_long *  _e_gsell)
        // returns USDC amount in 18 decimals due to conversion from sGLP
        uint256 cLongEgSell = (_c_long() * _e_gsell()) / GMX_PRICE_PRECISION;

        // need to adjust 18 (sGLP) to 6 decimals for USDC
        // returns USDC amount in 6 decimals
        cLongEgSell = _adjustForDecimals(
            cLongEgSell,
            SGLP_DECIMALS,
            USDC_DECIMALS
        );

        // _i_btc is in bps so we need to divide by 10^4 to account for this
        // evaluates: (_c_long *  _e_gsell) * _i_btc
        // returns USDC amount
        uint256 cLongEgSellIBtc = (cLongEgSell * _i_btc()) /
            GMX_BASIS_POINTS_DIVISOR;

        // all g values are in bps so we need to replace 1 in formula with
        // 10^4 and divide expression with 10^4 to account for multipling with bps.
        // evaluates: ((_c_long *  _e_gsell) * _i_btc) * (1 - _g_flash) * (1 - _g_sbtc)
        // returns USDC amount
        uint256 cLongEgSellIBtcFees = (((cLongEgSellIBtc *
            (GMX_BASIS_POINTS_DIVISOR - _g_flash())) /
            GMX_BASIS_POINTS_DIVISOR) *
            (GMX_BASIS_POINTS_DIVISOR - _g_sbtc())) / GMX_BASIS_POINTS_DIVISOR;

        // additionally we divide by constant to account for multiplaction of _hDivQ
        // which is in 18 decimal precision.
        // evaluates: ((_c_long *  _e_gsell) * _i_btc) * (h / q_usdc)
        // returns USDC amount
        uint256 cLongEgSellIBtcHQ = (cLongEgSellIBtc * _hDivQ()) / (10 ** 18);

        // _i_sum is in bps so we need to divide by 10^4 to account it
        // evaluates: ((_c_long *  _e_gsell) * (_i_eth + _i_link + _i_uni))
        // returns USDC amount
        uint256 cLongEgSellISum = (cLongEgSell * _i_sum()) /
            GMX_BASIS_POINTS_DIVISOR;

        // all g values are in bps so we need to replace 1 in formula with
        // 10^4 and divide expression with 10^4 to account for multipling with bps.
        // evaluates: ((_c_long *  _e_gsell) * (_i_eth + _i_link + _i_uni)) * (1 - _g_flash) * (1 - _g_seth)
        // returns USDC amount
        uint256 cLongEgSellISumFees = (((cLongEgSellISum *
            (GMX_BASIS_POINTS_DIVISOR - _g_flash())) /
            GMX_BASIS_POINTS_DIVISOR) *
            (GMX_BASIS_POINTS_DIVISOR - _g_seth())) / GMX_BASIS_POINTS_DIVISOR;

        // additionally we divide by constant to account for multiplaction of _hDivQ
        // which is in 18 decimal precision.
        // evaluates: ((_c_long *  _e_gsell) * (_i_eth + _i_link + _i_uni)) * (h / q_usdc)
        // returns USDC amount
        uint256 cLongEgSellISumHQ = (cLongEgSellISum * _hDivQ()) / (10 ** 18);

        // returns numerator value in USDC
        return
            int256(t) -
            int256(
                lrBtcFees + lrEthFees + cLongEgSellIBtcHQ + cLongEgSellISumHQ
            ) +
            int256(_c_short() + cLongEgSellISumFees + cLongEgSellIBtcFees);
    }

    /// @dev calculates denominator value of T_long formula on deposits
    /// NOTE:  follows progression of denominator calculation with
    /// comments of exact expression evaluated
    /// @return denominator value in 30 decimals precision
    function _denominatorTlongDeposit() private view returns (int256) {
        // additional precision modification needed
        // due to division of glp/usdc exchange rates.
        // evaluates: (_e_gsell / _e_gbuy)
        // 30 decimals precision
        uint256 egSellBuyRatio = (_e_gsell() *
            GMX_GLP_PRECISION *
            10 ** SGLP_DECIMALS) /
            _e_gbuy() /
            10 ** USDC_DECIMALS;

        // i_btc is in bps so we need to divide by 10^4.
        // evaluates: (_e_gsell / _e_gbuy) * _i_btc
        // 30 decimals precision
        uint256 egSellBuyRatioIdxBtc = (egSellBuyRatio * _i_btc()) /
            GMX_BASIS_POINTS_DIVISOR;

        // all g values are in bps so we need to replace 1 in formula with
        // 10^4 and divide expression with 10^4 to account for multipling with bps.
        // evaluates: ((_e_gsell / _e_gbuy) * _i_btc) * (1 - g_gbuy) * (1 - g_flash) * (1 - g_sbtc)
        // 30 decimals precision
        uint256 egSellBuyRatioIdxBtcFees = (((((egSellBuyRatioIdxBtc *
            (GMX_BASIS_POINTS_DIVISOR - _g_gbuy())) /
            GMX_BASIS_POINTS_DIVISOR) *
            (GMX_BASIS_POINTS_DIVISOR - _g_flash())) /
            GMX_BASIS_POINTS_DIVISOR) *
            (GMX_BASIS_POINTS_DIVISOR - _g_sbtc())) / GMX_BASIS_POINTS_DIVISOR;

        // first part approach is the same as above expression.
        // this is preparation to be used for expression after.
        // evaluates: ((_e_gsell / _e_gbuy) * _i_btc) * (1 - g_gbuy)
        // 30 decimals precision
        uint256 egSellBuyRatioIdxBtcHQ = (egSellBuyRatioIdxBtc *
            (GMX_BASIS_POINTS_DIVISOR - _g_gbuy())) / GMX_BASIS_POINTS_DIVISOR;

        // additionally we divide by constant to account for multipliction of _hDivQ
        // which is in 18 decimal precision.
        // evaluates: (((_e_gsell / _e_gbuy) * _i_btc) * (1 - g_gbuy)) * (h / q_usdc)
        // 30 decimals precision
        egSellBuyRatioIdxBtcHQ =
            (egSellBuyRatioIdxBtcHQ * _hDivQ()) /
            (10 ** 18);

        // as i_sum is in bps there is in need to divide by 10^4
        // evaluates: (_e_gsell / _e_gbuy) * (i_eth + i_link + i_uni)
        // 30 decimals precision
        uint256 egSellBuyRatioIsum = (egSellBuyRatio * _i_sum()) /
            GMX_BASIS_POINTS_DIVISOR;

        // all g values are in bps so we need to replace 1 in formula with
        // 10^4 and divide expression with 10^4 to account for multipling with bps.
        // evaluates: (((_e_gsell / _e_gbuy) * (i_eth + i_link + i_uni)) * (1 - g_gbuy) * (1 - g_flash) * (1 - g_sbtc)
        // 30 decimals precision
        uint256 egSellBuyRatioIsumFees = (((((egSellBuyRatioIsum *
            (GMX_BASIS_POINTS_DIVISOR - _g_gbuy())) /
            GMX_BASIS_POINTS_DIVISOR) *
            (GMX_BASIS_POINTS_DIVISOR - _g_flash())) /
            GMX_BASIS_POINTS_DIVISOR) *
            (GMX_BASIS_POINTS_DIVISOR - _g_seth())) / GMX_BASIS_POINTS_DIVISOR;

        // first part approach is the same as above expression.
        // this is preparation to be used for expression after.
        // all g values are in bps so we need to replace 1 in formula with
        // 10^4 and divide expression with 10^4 to account for multipling with bps.
        // evaluates: (((_e_gsell / _e_gbuy) * (i_eth + i_link + i_uni)) * (1 - g_gbuy)
        // 30 decimals precision
        uint256 egSellBuyRatioIsumHQ = (egSellBuyRatioIsum *
            (GMX_BASIS_POINTS_DIVISOR - _g_gbuy())) / GMX_BASIS_POINTS_DIVISOR;

        // additionally we divide by constant to account for multipliction of _hDivQ
        // which is in 18 decimal precision.
        // evaluates: (((_e_gsell / _e_gbuy) * _i_btc) * (1 - g_gbuy)) * (h / q_usdc)
        // 30 decimals precision
        egSellBuyRatioIsumHQ = (egSellBuyRatioIsumHQ * _hDivQ()) / (10 ** 18);

        // as all values are in 30 decimals precision, so "1" is replaced in formula with 10^30.
        // returns 30 decimals precision number of T_long denominator for deposits
        return
            int256(10 ** 30) -
            int256(egSellBuyRatioIdxBtcFees + egSellBuyRatioIsumFees) +
            int256(egSellBuyRatioIdxBtcHQ + egSellBuyRatioIsumHQ);
    }

    /// @notice calculates (hf / q_usdc)
    /// @dev helper function to calculate T_long.
    /// q - liquidation threshold for USDC is in bps so
    /// we divide by 10^4
    /// @return ratio (h / q_usdc)
    function _hDivQ() private view returns (uint256) {
        return (FIJA_HEALTH_FACTOR * GMX_BASIS_POINTS_DIVISOR) / _q();
    }

    /// @notice calculates index for BTC in GLP index composition
    /// @dev helper function to calculate T_long
    /// @return btc index in bps
    function _i_btc() private view returns (uint256) {
        (uint256 i_btc, , , ) = _currentGLPComposition();
        return i_btc;
    }

    /// @notice calculates index sum for ETH, LINK, UNI in GLP index composition
    /// @dev helper function to calculate T_long
    /// @return sum of ETH, LINK and UNI index in bps
    function _i_sum() private view returns (uint256) {
        (
            ,
            uint256 i_eth,
            uint256 i_link,
            uint256 i_uni
        ) = _currentGLPComposition();

        return i_eth + i_link + i_uni;
    }

    function _adjustForDecimalsInt(
        int256 amount,
        uint256 divDecimals,
        uint256 mulDecimals
    ) private pure returns (int256) {
        return (amount * int256(10 ** mulDecimals)) / int256(10 ** divDecimals);
    }

    function _L_btc(int256 t) private view returns (uint256) {
        int256 cLong = int256(_c_long());
        // deposit or rebalance
        int256 cLongEgSellaBtcRatioIBtc = _mulEgSellaBtcRatioIBtc(cLong);
        if (t >= 0) {
            int256 tLongFeeEgSellaBtcRatioIBtc = _TlongFeeEgBuy(t);

            if ((int256(cLong) + tLongFeeEgSellaBtcRatioIBtc) < 0) {
                return 0;
            }

            tLongFeeEgSellaBtcRatioIBtc = _mulEgSellaBtcRatioIBtc(
                tLongFeeEgSellaBtcRatioIBtc
            );

            return
                uint256(
                    int256(cLongEgSellaBtcRatioIBtc) +
                        tLongFeeEgSellaBtcRatioIBtc
                );
        } else {
            // withdrawal
            int256 tLongFeeEgSellaBtcRatioIBtc = _TlongFeeEgSell(t);

            if ((int256(cLong) + tLongFeeEgSellaBtcRatioIBtc) < 0) {
                return 0;
            }

            tLongFeeEgSellaBtcRatioIBtc = _mulEgSellaBtcRatioIBtc(
                tLongFeeEgSellaBtcRatioIBtc
            );

            return
                uint256(
                    tLongFeeEgSellaBtcRatioIBtc +
                        int256(cLongEgSellaBtcRatioIBtc)
                );
        }
    }

    function _L_eth(int256 t) private view returns (uint256) {
        int256 cLong = int256(_c_long());
        int256 cLongEgSellaEthRatioISum = _mulEgSellaEthRatioISum(cLong);

        // deposit or rebalance
        if (t >= 0) {
            int256 tLongFeeEgSellaEthRatioISum = _TlongFeeEgBuy(t);

            if ((int256(cLong) + tLongFeeEgSellaEthRatioISum) < 0) {
                return 0;
            }

            tLongFeeEgSellaEthRatioISum = _mulEgSellaEthRatioISum(
                tLongFeeEgSellaEthRatioISum
            );

            return
                uint256(
                    int256(cLongEgSellaEthRatioISum) +
                        tLongFeeEgSellaEthRatioISum
                );
        } else {
            // withdrawal
            int256 tLongFeeEgSellaBtcRatioISum = _TlongFeeEgSell(t);

            if ((int256(cLong) + tLongFeeEgSellaBtcRatioISum) < 0) {
                return 0;
            }

            tLongFeeEgSellaBtcRatioISum = _mulEgSellaEthRatioISum(
                tLongFeeEgSellaBtcRatioISum
            );
            return
                uint256(
                    int256(cLongEgSellaEthRatioISum) +
                        tLongFeeEgSellaBtcRatioISum
                );
        }
    }

    function _TlongFeeEgBuy(int256 t) private view returns (int256) {
        int256 tLongFeeEgBuy = (_T_long(t) * int256(GMX_PRICE_PRECISION)) /
            int256(_e_gbuy());

        tLongFeeEgBuy = _adjustForDecimalsInt(
            tLongFeeEgBuy,
            USDC_DECIMALS,
            SGLP_DECIMALS
        );

        tLongFeeEgBuy =
            (tLongFeeEgBuy * int256(GMX_BASIS_POINTS_DIVISOR - _g_gbuy())) /
            int256(GMX_BASIS_POINTS_DIVISOR);

        return tLongFeeEgBuy;
    }

    function _TlongFeeEgSell(int256 t) private view returns (int256) {
        int256 tLongFeeEgSell = (_T_long(t) * int256(GMX_PRICE_PRECISION)) /
            int256(_e_gsell());

        tLongFeeEgSell = _adjustForDecimalsInt(
            tLongFeeEgSell,
            USDC_DECIMALS,
            SGLP_DECIMALS
        );

        tLongFeeEgSell =
            (tLongFeeEgSell * int256(GMX_BASIS_POINTS_DIVISOR)) /
            int256(GMX_BASIS_POINTS_DIVISOR - _g_gsell());

        return tLongFeeEgSell;
    }

    function _mulEgSellaBtcRatioIBtc(
        int256 multipler
    ) private view returns (int256) {
        int256 cLongEgSellAbtcIBtc = (multipler * int256(_e_gsell())) /
            int256(GMX_PRICE_PRECISION);

        cLongEgSellAbtcIBtc = _adjustForDecimalsInt(
            cLongEgSellAbtcIBtc,
            SGLP_DECIMALS,
            USDC_DECIMALS
        );

        cLongEgSellAbtcIBtc =
            (cLongEgSellAbtcIBtc * int256(AAVE_BASE_CURRENCY_PRECISION)) /
            int256(_a_btc());

        cLongEgSellAbtcIBtc =
            (cLongEgSellAbtcIBtc * int256(_i_btc())) /
            int256(GMX_BASIS_POINTS_DIVISOR);

        cLongEgSellAbtcIBtc = _adjustForDecimalsInt(
            cLongEgSellAbtcIBtc,
            USDC_DECIMALS,
            WBTC_DECIMALS
        );

        return cLongEgSellAbtcIBtc;
    }

    function _mulEgSellaEthRatioISum(
        int256 multipler
    ) private view returns (int256) {
        int256 cLongEgSellaEthRatioISum = (multipler * int256(_e_gsell())) /
            int256(GMX_PRICE_PRECISION);

        cLongEgSellaEthRatioISum = _adjustForDecimalsInt(
            cLongEgSellaEthRatioISum,
            SGLP_DECIMALS,
            USDC_DECIMALS
        );

        cLongEgSellaEthRatioISum =
            (cLongEgSellaEthRatioISum * int256(AAVE_BASE_CURRENCY_PRECISION)) /
            int256(_a_eth());

        cLongEgSellaEthRatioISum =
            (cLongEgSellaEthRatioISum * int256(_i_sum())) /
            int256(GMX_BASIS_POINTS_DIVISOR);

        cLongEgSellaEthRatioISum = _adjustForDecimalsInt(
            cLongEgSellaEthRatioISum,
            USDC_DECIMALS,
            WETH_DECIMALS
        );

        return cLongEgSellaEthRatioISum;
    }

    /** PARAMETER HELPERS */

    function needRebalanceParams()
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256)
    {
        return (
            _h(),
            _c_long(),
            _c_short(),
            _l_btc(),
            _l_eth(),
            _i_btc(),
            _i_sum()
        );
    }

    function harvestParams() external view returns (uint256, uint256) {
        return (_r_eth(), _g_seth());
    }

    function vLongVshort() external view returns (uint256, uint256) {
        return (_v_long(), _v_short());
    }

    function genericInvestmetLogicParams(
        int256 t
    )
        external
        view
        returns (int256, int256, uint256, uint256, uint256, uint256, uint256)
    {
        return (
            _T_long(t),
            _T_short(t),
            _L_btc(t),
            _L_eth(t),
            _l_btc(),
            _l_eth(),
            _g_flash()
        );
    }

    function investTlongWithdraw() external view returns (uint256, uint256) {
        return (_e_gsell(), _g_gsell());
    }

    function investLBtcWithdraw() external view returns (uint256, uint256) {
        return (_r_btc(), _g_sbtc());
    }

    function investLEthWithdraw() external view returns (uint256, uint256) {
        return (_r_eth(), _g_seth());
    }

    function flashFee() external view returns (uint256) {
        return _g_flash();
    }

    function investTlongDeposit() external view returns (uint256, uint256) {
        return (_e_gbuy(), _g_gbuy());
    }

    function usdcLoanEthParams()
        external
        view
        returns (uint256, uint256, uint256)
    {
        return (_r_eth(), _g_seth(), _g_flash());
    }

    function usdcLoanBtcParams()
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256)
    {
        return (_r_eth(), _g_seth(), _r_btc(), _g_sbtc(), _g_flash());
    }

    function status() external view virtual override returns (string memory) {
        uint256 vDirectUsdc = IERC20(USDC).balanceOf(CORE_STRATEGY);
        uint256 vTotal = IERC4626(CORE_STRATEGY).totalAssets();

        string memory str1 = string(
            abi.encodePacked(
                "c_long=",
                Strings.toString(_c_long()),
                "|c_short=",
                Strings.toString(_c_short()),
                "|l_btc=",
                Strings.toString(_l_btc()),
                "|l_eth=",
                Strings.toString(_l_eth())
            )
        );

        string memory str2 = string(
            abi.encodePacked(
                "|h=",
                Strings.toString(_h()),
                "|v_long=",
                Strings.toString(_v_long()),
                "|v_short=",
                Strings.toString(_v_short()),
                "|v_usdc=",
                Strings.toString(vDirectUsdc),
                "|v=",
                Strings.toString(vTotal)
            )
        );

        (
            uint256 btc,
            uint256 eth,
            uint256 link,
            uint256 uni
        ) = _currentGLPComposition();

        console.log("i_btc:", btc);
        console.log("i_eth:", eth);
        console.log("i_link:", link);
        console.log("i_uni:", uni);
        console.log("g_sbtc:", _g_sbtc());
        console.log("g_seth:", _g_seth());
        console.log("g_flash:", _g_flash());
        console.log("g_gsell:", _g_gsell());
        console.log("g_gbuy:", _g_gbuy());
        console.log("a_btc:", _a_btc());
        console.log("a_eth:", _a_eth());
        console.log("e_gsell:", _e_gsell());
        console.log("e_gbuy:", _e_gbuy());
        console.log("l_btc:", _l_btc());
        console.log("l_eth:", _l_eth());
        console.log("c_long:", _c_long());
        console.log("c_short:", _c_short());
        console.log("v_long:", _v_long());
        console.log("v_short:", _v_short());
        console.log("vDirectUsdc:", vDirectUsdc);
        console.log("totalAssets:", vTotal);

        return string(abi.encodePacked(str1, str2));
    }
}

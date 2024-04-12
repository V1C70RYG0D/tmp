// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
pragma abicoder v2;

import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

import "@openzeppelin/contracts/utils/Strings.sol";
import "@aave/core-v3/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";

import "../../base/FijaStrategy.sol";
import "./GMXDeltaNeutralStrategyPeriphery.sol";
import "./GMXDeltaNeutralStrategyProtocols.sol";
import "./IGMXDeltaNeutralStrategyPeriphery.sol";

import "../../base/FijaStrategyEvents.sol";

contract GMXDeltaNeutralStrategy is
    IFlashLoanSimpleReceiver,
    GMXDeltaNeutralStrategyProtocols,
    FijaStrategy
{
    IGMXDeltaNeutralStrategyPeriphery internal _strategyPeriphery;

    constructor(
        address governance_,
        uint256 maxTicketSize_,
        uint256 maxVaultValue_
    )
        FijaStrategy(
            IERC20(USDC),
            governance_,
            "GMXDeltaNeutralToken",
            "sGMXDN",
            maxTicketSize_,
            maxVaultValue_
        )
    {
        lastHarvestTime = block.timestamp;

        _strategyPeriphery = IGMXDeltaNeutralStrategyPeriphery(
            new GMXDeltaNeutralStrategyPeriphery(
                address(this),
                maxTicketSize_,
                maxVaultValue_
            )
        );
    }

    // health factor is 18 decimals precision
    // current need for rebalance is h < 1.2 or h > 1.7
    function needRebalance() external view virtual override returns (bool) {
        (
            uint256 h,
            uint256 cLong,
            uint256 cShort,
            uint256 lBtc,
            uint256 lEth,
            uint256 iBtc,
            uint256 iSum
        ) = _strategyPeriphery.needRebalanceParams();

        if (cLong == 0) {
            return cShort != 0;
        }

        if (h < HF_LO_THRESHOLD || h > HF_HI_THRESHOLD) {
            return true;
        }

        // BTC imbalance
        int256 pctImbalance = int256(GMX_BASIS_POINTS_DIVISOR) -
            int256(
                (((lBtc * GMX_BASIS_POINTS_DIVISOR) / iBtc) *
                    10 ** SGLP_DECIMALS) / cLong
            );

        if (
            pctImbalance < -IMBALANCE_THRESHOLD ||
            pctImbalance > IMBALANCE_THRESHOLD
        ) {
            return true;
        }

        // ETH imbalance
        pctImbalance =
            int256(GMX_BASIS_POINTS_DIVISOR) -
            int256(
                (((lEth * GMX_BASIS_POINTS_DIVISOR) / iSum) *
                    10 ** SGLP_DECIMALS) / cLong
            );

        if (
            pctImbalance < -IMBALANCE_THRESHOLD ||
            pctImbalance > IMBALANCE_THRESHOLD
        ) {
            return true;
        }

        return false;
    }

    function rebalance() external payable virtual override onlyGovernance {
        _genericInvestmentLogic(0);
        emit FijaStrategyEvents.Rebalance(block.timestamp, "METADATA");
    }

    function needHarvest() external view virtual override returns (bool) {
        uint256 totalAsset = totalAssets();
        // check 48 hours
        if (block.timestamp >= (lastHarvestTime + 172800)) {
            if (totalAsset > 3_000_000_000_000) {
                return true;
            }
        }
        // check weekly
        if (block.timestamp >= (lastHarvestTime + 604800)) {
            if (totalAsset > 500_000_000_000) {
                return true;
            }
        }
        // check bi-weekly
        if (block.timestamp >= (lastHarvestTime + 1209600)) {
            if (totalAsset > 100_000_000_000) {
                return true;
            }
        }
        // check 30 days
        if (block.timestamp >= (lastHarvestTime + 2592000)) {
            if (totalAsset > 0) {
                return true;
            }
        }
        return false;
    }

    function harvest() external payable virtual override onlyGovernance {
        GMX_IGmxRewardRouter.handleRewards(
            false,
            false,
            false,
            false,
            false,
            true,
            false
        );
        // get all weth we have on balance for swap
        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));

        (uint256 rEth, uint256 gsEth) = _strategyPeriphery.harvestParams();

        // calculate expected USDC to get from swap
        uint256 minUSDCOut = (wethBalance * rEth) /
            AAVE_BASE_CURRENCY_PRECISION;

        minUSDCOut = _adjustForDecimals(
            minUSDCOut,
            WETH_DECIMALS,
            USDC_DECIMALS
        );

        minUSDCOut =
            (minUSDCOut * (GMX_BASIS_POINTS_DIVISOR - gsEth)) /
            GMX_BASIS_POINTS_DIVISOR;

        minUSDCOut =
            (minUSDCOut * (GMX_BASIS_POINTS_DIVISOR - SLIPPAGE)) /
            GMX_BASIS_POINTS_DIVISOR;

        ISwapRouter.ExactInputSingleParams memory swapInput = ISwapRouter
            .ExactInputSingleParams(
                WETH,
                USDC,
                uint24(gsEth) * 100, // in 6 decimals for uniswap
                address(this),
                block.timestamp + 120,
                wethBalance,
                minUSDCOut,
                0
            );

        SafeERC20.safeIncreaseAllowance(
            IERC20(WETH),
            address(Uniswap_ISwapRouter),
            wethBalance
        );
        // swap ETH TO USDC and leave USDC
        Uniswap_ISwapRouter.exactInputSingle(swapInput);

        lastHarvestTime = block.timestamp;

        emit FijaStrategyEvents.Harvest(
            block.timestamp,
            0,
            0,
            asset(),
            "METADATA"
        );
    }

    function setEmergencyMode(
        bool turnOn
    ) external payable virtual override onlyGovernance {
        _isEmergencyMode = turnOn;
        emit FijaStrategyEvents.EmergencyMode(block.timestamp, turnOn);
    }

    /// @dev returns total amount of assets which is managed by strategy
    /// calculated based on strategy formula considering deployed
    /// short and long positions and rewinding them back to asset (USDC)
    function totalAssets() public view virtual override returns (uint256) {
        (uint256 vLong, uint256 vShort) = _strategyPeriphery.vLongVshort();
        return IERC20(USDC).balanceOf(address(this)) + vLong + vShort;
    }

    /// @dev returns status parameters of GMX strategy
    function status() external view virtual override returns (string memory) {
        return _strategyPeriphery.status();
    }

    /// @dev calculates amount of strategy tokens receiver will get from the Strategy based on asset deposit.
    /// Emits Deposit event
    //  NOTE: requires pre-approval of the Strategy with the Strategy's underlying asset token
    /// @param assets amount of assets caller wants to deposit
    /// @param receiver address of the owner of deposit once deposit completes,
    /// this address will receiver vault tokens.
    /// @return amount of strategy tokens receiver will receive based on asset deposit
    function deposit(
        uint256 assets,
        address receiver
    ) public payable virtual override returns (uint256) {
        uint256 currentBalance = IERC20(asset()).balanceOf(address(this));

        uint256 tokens = super.deposit(assets, receiver);

        _genericInvestmentLogic(int256(assets) + int256(currentBalance));

        return tokens;
    }

    /// @dev Burns exactly strategy tokens from owner and sends assets to receiver.
    /// Emits Withdraw event
    /// @param tokens amount of strategy tokens caller wants to redeem
    /// @param receiver address of the asset receiver
    /// @param owner address of the owner of strategy tokens
    /// @return amount of assets receiver will receive based on exact burnt strategy tokens
    function redeem(
        uint256 tokens,
        address receiver,
        address owner
    ) external payable virtual override returns (uint256) {
        uint256 assets = previewRedeem(tokens);

        uint256 currentBalance = IERC20(USDC).balanceOf(address(this));

        if (assets > currentBalance) {
            _genericInvestmentLogic(int256(currentBalance) - int256(assets));
        }
        // redeem tokens to get usdc back
        return super.redeem(tokens, receiver, owner);
    }

    /// @dev Burns strategy tokens from owner and sends exactly assets to receiver.
    /// Emits Withdraw event
    /// @param assets amount of assets caller wants to withdraw
    /// @param receiver address of the asset receiver
    /// @param owner address of the owner of strategy tokens
    /// @return amount of strategy tokens burnt based on exact assets requested
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external payable virtual override returns (uint256) {
        uint256 currentBalance = IERC20(asset()).balanceOf(address(this));

        if (assets > currentBalance) {
            _genericInvestmentLogic(int256(currentBalance) - int256(assets));
        }

        // withdraw assets minus rouge deposit
        return super.withdraw(assets, receiver, owner);
    }

    function _genericInvestmentLogic(int256 t) private {
        (
            int256 tLong,
            int256 tShort,
            uint256 LBtc,
            uint256 LEth,
            uint256 lBtc,
            uint256 lEth,
            uint256 flashFee
        ) = _strategyPeriphery.genericInvestmetLogicParams(t);

        IPool pool = IPool(AAVE_IPoolAddressesProvider.getPool());

        if (tLong < 0) {
            // withdraw funds from GLP
            // Tlong / e_gsell

            (uint256 eGSell, uint256 gGSell) = _strategyPeriphery
                .investTlongWithdraw();
            uint256 sGLP = (uint256(-tLong) * GMX_PRICE_PRECISION) / eGSell;

            sGLP = _adjustForDecimals(sGLP, USDC_DECIMALS, SGLP_DECIMALS);

            //Tlong / e_gsell / (1 - g_gsell)
            sGLP =
                (sGLP * GMX_BASIS_POINTS_DIVISOR) /
                (GMX_BASIS_POINTS_DIVISOR - gGSell);

            //Tlong / e_gsell / (1 - g_gsell) / (1 - SLIPPAGE)
            sGLP =
                (sGLP * GMX_BASIS_POINTS_DIVISOR) /
                (GMX_BASIS_POINTS_DIVISOR - SLIPPAGE);

            GMX_IGmxGlpRewardRouter.unstakeAndRedeemGlp(
                USDC,
                sGLP, // from GLP amount
                uint256(-tLong), // minimum USDC out
                address(this)
            );
        }
        if (tShort > 0) {
            // then deposit corresponding collateral to Aave
            // TODO could be optimised withPermit
            // deposits from strategy to aave
            SafeERC20.safeIncreaseAllowance(
                IERC20(USDC),
                address(pool),
                uint256(tShort)
            );
            pool.supply(USDC, uint256(tShort), address(this), 0);
        }
        if (LBtc < lBtc) {
            (uint256 rBtc, uint256 gSBtc) = _strategyPeriphery
                .investLBtcWithdraw();

            uint256 usdcForFlash = ((lBtc - LBtc) * rBtc) /
                AAVE_BASE_CURRENCY_PRECISION;

            usdcForFlash = _adjustForDecimals(
                usdcForFlash,
                WBTC_DECIMALS,
                USDC_DECIMALS
            );

            usdcForFlash =
                (usdcForFlash * GMX_BASIS_POINTS_DIVISOR) /
                (GMX_BASIS_POINTS_DIVISOR - gSBtc);
            // 0x1 flag for callback that is BTC
            pool.flashLoanSimple(address(this), USDC, usdcForFlash, "0x1", 0);
        }
        if (LEth < lEth) {
            (uint256 rEth, uint256 gSEth) = _strategyPeriphery
                .investLEthWithdraw();

            uint256 usdcForFlash = ((lEth - LEth) * rEth) /
                AAVE_BASE_CURRENCY_PRECISION;

            usdcForFlash = _adjustForDecimals(
                usdcForFlash,
                WETH_DECIMALS,
                USDC_DECIMALS
            );

            usdcForFlash =
                (usdcForFlash * GMX_BASIS_POINTS_DIVISOR) /
                (GMX_BASIS_POINTS_DIVISOR - gSEth);

            pool.flashLoanSimple(address(this), USDC, usdcForFlash, "", 0);
        }
        if (LEth > lEth) {
            pool.flashLoanSimple(
                address(this),
                WETH,
                ((LEth - lEth) * (GMX_BASIS_POINTS_DIVISOR - flashFee)) /
                    GMX_BASIS_POINTS_DIVISOR,
                "",
                0
            );
        }
        if (LBtc > lBtc) {
            pool.flashLoanSimple(
                address(this),
                WBTC,
                ((LBtc - lBtc) * (GMX_BASIS_POINTS_DIVISOR - flashFee)) /
                    GMX_BASIS_POINTS_DIVISOR,
                "",
                0
            );
        }
        if (tShort < 0) {
            // then remove corresponding collateral from Aave
            // withdraw collateral from aave to strategy.
            pool.withdraw(USDC, uint256(-tShort), address(this));
        }
        if (tLong > 0) {
            (uint256 eGBuy, uint256 gGbuy) = _strategyPeriphery
                .investTlongDeposit();
            // deposit funds to GLP
            // buy GLP, includes slippage to set minimum GLP to buy
            // 0 in the call below indicats min price of GLP in USD to buy
            // T_long / e_gbuy
            uint256 minsGLP = (uint256(tLong) * GMX_PRICE_PRECISION) / eGBuy;
            minsGLP = _adjustForDecimals(minsGLP, USDC_DECIMALS, SGLP_DECIMALS);

            // (T_long / e_gbuy) * (1- g_gbuy) * (1 - slippage)
            minsGLP =
                (minsGLP * (GMX_BASIS_POINTS_DIVISOR - gGbuy)) /
                GMX_BASIS_POINTS_DIVISOR;
            minsGLP =
                (minsGLP * (GMX_BASIS_POINTS_DIVISOR - SLIPPAGE)) /
                GMX_BASIS_POINTS_DIVISOR;

            // approve glpMananger to take USDC as Router is invoking Manager
            SafeERC20.safeIncreaseAllowance(
                IERC20(USDC),
                address(GMX_IGmxGlpManager),
                uint256(tLong)
            );

            GMX_IGmxGlpRewardRouter.mintAndStakeGlp(
                USDC,
                uint256(tLong), // from USDC amount
                0,
                minsGLP // min GLP to get out
            );
        }
    }

    // callback for aave flash loans
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        if (initiator != address(this)) {
            revert FijaUnauthorizedFlash();
        }

        if (asset == USDC) {
            // weth?
            if (params.length == 0) {
                _usdcLoanEth(amount, premium);
            } else {
                // btc
                _usdcLoanBtc(amount, premium);
            }
            // usdc loan
        } else if (asset == WETH) {
            _ethLoan(amount, premium);
        } else if (asset == WBTC) {
            _btcLoan(amount, premium);
        } else {
            revert FijaInvalidAssetFlash();
        }
        return true;
    }

    function _usdcLoanEth(uint256 amount, uint256 premium) private {
        (uint256 rEth, uint256 gSEth, uint256 gFlash) = _strategyPeriphery
            .usdcLoanEthParams();
        uint256 wETHAmountMin = (amount * AAVE_BASE_CURRENCY_PRECISION) / rEth;

        wETHAmountMin = _adjustForDecimals(
            wETHAmountMin,
            USDC_DECIMALS,
            WETH_DECIMALS
        );

        wETHAmountMin =
            (wETHAmountMin * (GMX_BASIS_POINTS_DIVISOR - gSEth)) /
            GMX_BASIS_POINTS_DIVISOR;

        wETHAmountMin =
            (wETHAmountMin * (GMX_BASIS_POINTS_DIVISOR - SLIPPAGE)) /
            GMX_BASIS_POINTS_DIVISOR;

        ISwapRouter.ExactInputSingleParams memory swapInput = ISwapRouter
            .ExactInputSingleParams(
                USDC,
                WETH,
                uint24(gSEth) * 100, // in 6 decimals for uniswap
                address(this),
                block.timestamp + 120,
                amount,
                wETHAmountMin,
                0
            );

        SafeERC20.safeIncreaseAllowance(
            IERC20(USDC),
            address(Uniswap_ISwapRouter),
            amount
        );
        uint256 beforeSwap = IERC20(WETH).balanceOf(address(this));
        // swap USDC TO ETH
        Uniswap_ISwapRouter.exactInputSingle(swapInput);

        uint256 afterSwap = IERC20(WETH).balanceOf(address(this));

        address poolAddr = AAVE_IPoolAddressesProvider.getPool();
        SafeERC20.safeIncreaseAllowance(
            IERC20(WETH),
            poolAddr,
            afterSwap - beforeSwap
        );
        IPool pool = IPool(poolAddr);
        pool.repay(WETH, afterSwap - beforeSwap, 2, address(this));

        pool.withdraw(
            USDC,
            (amount * GMX_BASIS_POINTS_DIVISOR) /
                (GMX_BASIS_POINTS_DIVISOR - gFlash),
            address(this)
        );

        // prepare approval to repay flashloan
        SafeERC20.safeIncreaseAllowance(
            IERC20(USDC),
            poolAddr,
            amount + premium
        );
    }

    function _usdcLoanBtc(uint256 amount, uint256 premium) private {
        (
            uint256 rEth,
            uint256 gSEth,
            uint256 rBtc,
            uint256 gSBtc,

        ) = _strategyPeriphery.usdcLoanBtcParams();

        // convert USDC to WETH
        uint256 amountMin = (amount * AAVE_BASE_CURRENCY_PRECISION) / rEth;

        amountMin = _adjustForDecimals(amountMin, USDC_DECIMALS, WETH_DECIMALS);

        amountMin =
            (amountMin * (GMX_BASIS_POINTS_DIVISOR - gSEth)) /
            GMX_BASIS_POINTS_DIVISOR;

        amountMin =
            (amountMin * (GMX_BASIS_POINTS_DIVISOR - SLIPPAGE)) /
            GMX_BASIS_POINTS_DIVISOR;

        // swap USDC to WETH
        ISwapRouter.ExactInputSingleParams memory swapInput = ISwapRouter
            .ExactInputSingleParams(
                USDC,
                WETH,
                uint24(gSEth) * 100, // in 6 decimals for uniswap
                address(this),
                block.timestamp + 120,
                amount,
                amountMin,
                0
            );
        SafeERC20.safeIncreaseAllowance(
            IERC20(USDC),
            address(Uniswap_ISwapRouter),
            amount
        );

        uint256 beforeSwap = IERC20(WETH).balanceOf(address(this));
        Uniswap_ISwapRouter.exactInputSingle(swapInput);

        uint256 afterSwap = IERC20(WETH).balanceOf(address(this));

        // get estimate to convert USDC to WBTC to get target WBTC
        amountMin = (amount * AAVE_BASE_CURRENCY_PRECISION) / rBtc;

        amountMin = _adjustForDecimals(amountMin, USDC_DECIMALS, WBTC_DECIMALS);

        amountMin =
            (amountMin * (GMX_BASIS_POINTS_DIVISOR - gSBtc)) /
            GMX_BASIS_POINTS_DIVISOR;

        // double slippage as we calculate intermediary swap
        amountMin =
            (amountMin * (GMX_BASIS_POINTS_DIVISOR - SLIPPAGE * 2)) /
            GMX_BASIS_POINTS_DIVISOR;

        // swap WETH to WBTC
        swapInput = ISwapRouter.ExactInputSingleParams(
            WETH,
            WBTC,
            IUniswapV3Pool(UNISWAP_WBTC_WETH_POOL).fee(),
            address(this),
            block.timestamp + 120,
            afterSwap - beforeSwap, // weth received from previous step
            amountMin,
            0
        );
        SafeERC20.safeIncreaseAllowance(
            IERC20(WETH),
            address(Uniswap_ISwapRouter),
            afterSwap - beforeSwap
        );

        beforeSwap = IERC20(WBTC).balanceOf(address(this));

        Uniswap_ISwapRouter.exactInputSingle(swapInput);

        afterSwap = IERC20(WBTC).balanceOf(address(this));

        address poolAddr = AAVE_IPoolAddressesProvider.getPool();
        SafeERC20.safeIncreaseAllowance(
            IERC20(WBTC),
            poolAddr,
            afterSwap - beforeSwap
        );

        IPool(poolAddr).repay(WBTC, afterSwap - beforeSwap, 2, address(this));

        IPool(poolAddr).withdraw(
            USDC,
            (amount * GMX_BASIS_POINTS_DIVISOR) /
                (GMX_BASIS_POINTS_DIVISOR - _strategyPeriphery.flashFee()),
            address(this)
        );

        // prepare approval to repay flashloan
        SafeERC20.safeIncreaseAllowance(
            IERC20(USDC),
            poolAddr,
            amount + premium
        );
    }

    function _ethLoan(uint256 amount, uint256 premium) private {
        (uint256 rEth, uint256 gSEth, ) = _strategyPeriphery
            .usdcLoanEthParams();

        address poolAddr = AAVE_IPoolAddressesProvider.getPool();
        IPool pool = IPool(poolAddr);

        // weth loan

        // calculate expected USDC to get from swap
        uint256 minUSDCOut = (amount * rEth) / AAVE_BASE_CURRENCY_PRECISION;

        minUSDCOut = _adjustForDecimals(
            minUSDCOut,
            WETH_DECIMALS,
            USDC_DECIMALS
        );

        minUSDCOut =
            (minUSDCOut * (GMX_BASIS_POINTS_DIVISOR - gSEth)) /
            GMX_BASIS_POINTS_DIVISOR;

        minUSDCOut =
            (minUSDCOut * (GMX_BASIS_POINTS_DIVISOR - SLIPPAGE)) /
            GMX_BASIS_POINTS_DIVISOR;

        // convert from bps to uniswap format fee
        ISwapRouter.ExactInputSingleParams memory swapInput = ISwapRouter
            .ExactInputSingleParams(
                WETH,
                USDC,
                uint24(gSEth) * 100, // in 6 decimals for uniswap
                address(this),
                block.timestamp + 120,
                amount,
                minUSDCOut,
                0
            );

        SafeERC20.safeIncreaseAllowance(
            IERC20(WETH),
            address(Uniswap_ISwapRouter),
            amount
        );

        uint256 beforeSwap = IERC20(USDC).balanceOf(address(this));
        // swap ETH TO USDC
        Uniswap_ISwapRouter.exactInputSingle(swapInput);
        uint256 afterSwap = IERC20(USDC).balanceOf(address(this));

        uint256 diff = afterSwap - beforeSwap;

        // deposit USDC to Aave
        // TODO could be optimised withPermit
        // deposits from strategy to aave

        SafeERC20.safeIncreaseAllowance(IERC20(USDC), poolAddr, diff);
        pool.supply(USDC, diff, address(this), 0);

        // borrow variable interest ETH from AAVE to repay flashloan
        pool.borrow(WETH, amount + premium, 2, 0, address(this));

        // prepare approval to repay flashloan
        SafeERC20.safeIncreaseAllowance(
            IERC20(WETH),
            poolAddr,
            amount + premium
        );
    }

    function _btcLoan(uint256 amount, uint256 premium) private {
        (
            uint256 rEth,
            uint256 gSEth,
            uint256 rBtc,
            uint256 gSBtc,

        ) = _strategyPeriphery.usdcLoanBtcParams();

        address poolAddr = AAVE_IPoolAddressesProvider.getPool();

        // convert how much final USDC we need to get for WETH to USDC
        // sbtc fee and double slippage below are just approx. what we should get after 2 swaps
        uint256 minUSDCOut = (amount * rBtc) / AAVE_BASE_CURRENCY_PRECISION;

        minUSDCOut = _adjustForDecimals(
            minUSDCOut,
            WBTC_DECIMALS,
            USDC_DECIMALS
        );

        minUSDCOut =
            (minUSDCOut * (GMX_BASIS_POINTS_DIVISOR - gSBtc)) /
            GMX_BASIS_POINTS_DIVISOR;

        minUSDCOut =
            (minUSDCOut * (GMX_BASIS_POINTS_DIVISOR - SLIPPAGE * 2)) /
            GMX_BASIS_POINTS_DIVISOR;

        // convert WBTC to WETH

        uint256 minWETHOut = (amount * rBtc) / AAVE_BASE_CURRENCY_PRECISION;

        minWETHOut = _adjustForDecimals(
            minWETHOut,
            WBTC_DECIMALS,
            USDC_DECIMALS
        );

        minWETHOut = (minWETHOut * AAVE_BASE_CURRENCY_PRECISION) / rEth;

        minWETHOut = _adjustForDecimals(
            minWETHOut,
            USDC_DECIMALS,
            WETH_DECIMALS
        );

        minWETHOut =
            (minWETHOut *
                (GMX_BASIS_POINTS_DIVISOR -
                    _adjustForDecimals(
                        IUniswapV3Pool(UNISWAP_WBTC_WETH_POOL).fee(),
                        UNISWAP_FEE_DECIMALS,
                        4
                    ))) /
            GMX_BASIS_POINTS_DIVISOR;

        minWETHOut =
            (minWETHOut * (GMX_BASIS_POINTS_DIVISOR - SLIPPAGE)) /
            GMX_BASIS_POINTS_DIVISOR;

        ISwapRouter.ExactInputSingleParams memory swapInput = ISwapRouter
            .ExactInputSingleParams(
                WBTC,
                WETH,
                IUniswapV3Pool(UNISWAP_WBTC_WETH_POOL).fee(),
                address(this),
                block.timestamp + 120,
                amount, // WBTC
                minWETHOut,
                0
            );
        SafeERC20.safeIncreaseAllowance(
            IERC20(WBTC),
            address(Uniswap_ISwapRouter),
            amount
        );

        uint256 beforeSwap = IERC20(WETH).balanceOf(address(this));
        // swap WBTC TO WETH
        Uniswap_ISwapRouter.exactInputSingle(swapInput);
        uint256 afterSwap = IERC20(WETH).balanceOf(address(this));

        // swap WETH to USDC
        swapInput = ISwapRouter.ExactInputSingleParams(
            WETH,
            USDC,
            uint24(gSEth) * 100,
            address(this),
            block.timestamp + 120,
            afterSwap - beforeSwap, // WETH from previous swap
            minUSDCOut,
            0
        );

        SafeERC20.safeIncreaseAllowance(
            IERC20(WETH),
            address(Uniswap_ISwapRouter),
            afterSwap - beforeSwap
        );

        beforeSwap = IERC20(USDC).balanceOf(address(this));
        Uniswap_ISwapRouter.exactInputSingle(swapInput);

        afterSwap = IERC20(USDC).balanceOf(address(this));

        // deposit USDC to Aave
        // TODO could be optimised withPermit
        // deposits from strategy to aave

        SafeERC20.safeIncreaseAllowance(
            IERC20(USDC),
            poolAddr,
            afterSwap - beforeSwap
        );
        IPool(poolAddr).supply(USDC, afterSwap - beforeSwap, address(this), 0);

        // borrow variable interest BTC from AAVE to repay flashloan
        IPool(poolAddr).borrow(WBTC, amount + premium, 2, 0, address(this));

        // prepare approval to repay flashloan
        SafeERC20.safeIncreaseAllowance(
            IERC20(WBTC),
            poolAddr,
            amount + premium
        );
    }

    function _adjustForDecimals(
        uint256 amount,
        uint256 divDecimals,
        uint256 mulDecimals
    ) private pure returns (uint256) {
        return (amount * 10 ** mulDecimals) / (10 ** divDecimals);
    }

    function ADDRESSES_PROVIDER()
        external
        pure
        virtual
        override
        returns (IPoolAddressesProvider)
    {
        return AAVE_IPoolAddressesProvider;
    }

    function POOL() external view virtual override returns (IPool) {
        return IPool(AAVE_IPoolAddressesProvider.getPool());
    }
}

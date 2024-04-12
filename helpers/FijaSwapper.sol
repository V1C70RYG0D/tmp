// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IFijaSwapper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
// import "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "../protocols/uniswap/libraries/Path.sol";
import "../protocols/uniswap/libraries/PoolAddress.sol";

// TODO: Remove for production
import "hardhat/console.sol";

/**
/* @dev provides a stripped down Swapper for exactInputMulithop functionality and predefined paths
/* Path defined from a sequence of tokens from input to output with fees in between:
/* Contract does not allow extraction of all implemented swaps
/* tokens are addresses. fees are represented as uint24
 */

contract FijaSwapper is IFijaSwapper {
    /**
     * @dev executes swap from via implemented route from input to output
     * returns the amount of tokens received
     * does not check if there is no route from input to output
     */
    uint256 private constant ADDR_SIZE = 20;
    uint256 private constant FEE_SIZE = 3;
    uint256 private constant OFFSET = 23;

    address private constant swapRouterAddress =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    ISwapRouter internal constant swapRouter = ISwapRouter(swapRouterAddress);
    address private constant uniswapV3FactoryAddress =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;

    mapping(bytes32 => uint24) internal aggregatedFees;
    mapping(bytes32 => bytes) internal uniswapPaths;

    function swap(
        address input,
        address output,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) external payable override returns (uint256 amountOut) {
        bool pathExists = this.hasPath(input, output);
        if (pathExists == false) {
            revert SwapPathNotImplemented(input, output);
        }
        bytes32 key = keccak256(abi.encodePacked(input, output));
        bytes memory path = uniswapPaths[key];
        TransferHelper.safeApprove(input, swapRouterAddress, amountIn);
        TransferHelper.safeTransferFrom(
            input,
            msg.sender,
            address(this),
            amountIn
        );
        ISwapRouter.ExactInputParams memory swapParams = ISwapRouter
            .ExactInputParams({
                path: path,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum
            });
        amountOut = swapRouter.exactInput(swapParams);
        console.log("amountOut returned from uniswap swap call:");
        console.logUint(amountOut);
        return amountOut;
    }

    /**
     * @dev returns the aggregate fee for a multihop swap
     * reverts if there is no route from input to output
     * Does not take slippage into account
     */
    function aggregateFee(
        address input,
        address output
    ) external view override returns (uint24) {
        bytes32 key = keccak256(abi.encodePacked(input, output));
        return aggregatedFees[key];
    }

    /**
     * @dev returns the bytes representing the path for swapping
     * empty if no path implemented
     */
    function swapPath(
        address input,
        address output
    ) external view override returns (bytes memory) {
        bytes32 key = keccak256(abi.encodePacked(input, output));
        return uniswapPaths[key];
    }

    /**
     * @dev returns uniswap poolAddress for the pool
     * Reverts if one of the checks is not passing
     * Guarantees of the check performed:
     * - input and outputs are not meaningful addresses
     * - input and output addresses correspond correspond to erc20 tokens
     * - uniswapV3 pool with tokens and fees exists
     * - uniswapV3 pool with tokens has funds for bothinput and output token
     * Not currently checked:
     * - pool has suffient liquidity for low slippage
     * - input and output token addresses correspond to a list of specific tokens
     */

    /**
     * @dev returns pool Address for a tokenpair  with fee
     * Returns zero address if pool is not initialized
     */
    function getUniswapPool(
        address input,
        address output,
        uint24 fee
    ) internal view returns (address poolAddress) {
        IUniswapV3PoolImmutables pool;
        PoolAddress.PoolKey memory poolKey;
        poolKey = PoolAddress.getPoolKey(input, output, fee);
        // poolAddress is calculated. No guarantee that the pool has been created
        poolAddress = PoolAddress.computeAddress(
            uniswapV3FactoryAddress,
            poolKey
        );
        // Check that the pool exists
        pool = IUniswapV3PoolImmutables(poolAddress);
        // Check that the pool has deployed contract - otherwise not initialized.
        if (poolAddress.code.length == 0) {
            return address(0);
        }
        if (pool.token0() == input || pool.token1() == input) {
            return poolAddress;
        } else {
            // return zero Address if pool is not intialized
            return address(0);
        }
    }

    /**
     * @dev updates internal state of the contract which holds the routes for input-output-pairs
     * Performs certain checks at the multihop and individual hop level:
     * - All  intermediate pools are initialized.
     * - token and fee sequence for the paths are well formed
     * Reverts if a single check fails for any of the paths
     * Assumes that both the forward and return path are specified when both are used
     * Currently not checked
     * - After update: The Swapper has pools for all required exchanges
     * - After update: The Swapper has paths for all required exchanges
     * - Forward and backward paths are using the same intermediate pools
     * - The pools are suffieciently funded
     */
    function updatePaths(bytes[] calldata newPaths) external override {
        uint24 aggregatedFee;
        uint24 fee;
        uint256 numPools;
        bytes memory updatePath;
        bytes32 key;

        // check that input is well formed
        if (newPaths.length == 0) {
            revert UpdatePathsIsEmptyList();
        }
        for (uint256 i; i < newPaths.length; i++) {
            // path needs to included at least 2 addresses and 1 fee and can be extended by address-fee pairs
            fee = 0;
            aggregatedFee = 0;
            updatePath = newPaths[i];
            if (
                updatePath.length < ADDR_SIZE + OFFSET ||
                (updatePath.length - ADDR_SIZE) % OFFSET != 0
            ) {
                revert IncorrectPathSyntax(updatePath);
            }
            address[] memory tokenChain = new address[](
                ((updatePath.length + FEE_SIZE) / OFFSET)
            );
            address[] memory poolChain = new address[](
                (updatePath.length - FEE_SIZE) / OFFSET
            );
            numPools = Path.numPools(updatePath);
            for (uint256 j = 0; j < numPools; j++) {
                (tokenChain[j], tokenChain[j + 1], fee) = Path.decodeFirstPool(
                    updatePath
                );
                aggregatedFee += fee;
                poolChain[j] = getUniswapPool(
                    tokenChain[j],
                    tokenChain[j + 1],
                    fee
                );
                if (poolChain[j] == address(0)) {
                    revert IntermediatePoolDoesNotExist(
                        tokenChain[j],
                        tokenChain[j + 1],
                        fee
                    );
                }
                if (updatePath.length != 2 * ADDR_SIZE + FEE_SIZE) {
                    updatePath = Path.skipToken(updatePath);
                }
            }
            key = keccak256(
                abi.encodePacked(
                    tokenChain[0],
                    tokenChain[tokenChain.length - 1]
                )
            );
            aggregatedFees[key] = aggregatedFee;
            uniswapPaths[key] = newPaths[i];

            emit PathUpdateEvent({
                input: tokenChain[0],
                output: tokenChain[tokenChain.length - 1],
                poolChain: poolChain,
                aggregatedFee: aggregatedFee,
                timestamp: block.timestamp
            });
        }
    }

    /**
     * @dev returns true if the path is initialized in the Swapper
     */
    function hasPath(
        address input,
        address output
    ) external view override returns (bool) {
        bytes32 key = keccak256(abi.encodePacked(input, output));
        if (uniswapPaths[key].length != 0) {
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev removes swap path and its reverse in the FiajSwapper
     * Does not check if path exists or not
     * TO BE DECIDED: REMOVE function for safety purposes. Signaling that the sapper cannot be made invalid even by the owner
     */
    function purgePath(address input, address output) external override {
        if (this.hasPath(input, output)) {
            bytes32 key = keccak256(abi.encodePacked(input, output));
            aggregatedFees[key] = 0;
            uniswapPaths[key] = bytes("");
        }
        // reverse path purge
        if (this.hasPath(output, input)) {
            bytes32 key = keccak256(abi.encodePacked(output, input));
            aggregatedFees[key] = 0;
            uniswapPaths[key] = bytes("");
        }
    }
}

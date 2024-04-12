// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

/**
/* @dev provides a stripped down Swapper for exactInputMulithop functionality and predefined paths
/* Path defined from a sequence of tokens from input to output with fees in between:
/* Contract does not allow extraction of all implemented swaps
/* tokens are addresses. fees are represented as uint24
 */

interface IFijaSwapper {
    /**
     * @dev emits when a path is updated
     * path ist represented by a list of intermediate UniswapV3 pool addresses between input and output
     * Fromfee and intermediate token can be recoverd from pool address
     */
    event PathUpdateEvent(
        address input,
        address output,
        address[] poolChain,
        uint24 aggregatedFee,
        uint256 timestamp
    );

    error UpdatePathsIsEmptyList();
    error IncorrectPathSyntax(bytes updatePath);
    error SwapPathNotImplemented(address input, address output);
    error IntermediatePoolDoesNotExist(
        address input,
        address output,
        uint24 fee
    );

    /**
     * @dev executes swap from via implemented route from input to output
     * returns the amount of tokens received
     * does not check if there is no route from input to output
     */
    function swap(
        address input,
        address output,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) external payable returns (uint256);

    /**
     * @dev returns the aggregate fee for a multihop swap
     * zero if no path implemented
     * Does not take slippage into account
     */
    function aggregateFee(
        address input,
        address output
    ) external view returns (uint24);

    /**
     * @dev returns the bytes representing the path for swapping
     * empty if no path implemented
     */
    function swapPath(
        address input,
        address output
    ) external view returns (bytes memory);

    /**
     * @dev removes swap path and its reverse in the FiajSwapper
     * Does not check if path exists or not
     */
    function purgePath(address input, address output) external;

    /**
     * @dev returns true if the path is initialized in the Swapper
     */
    function hasPath(
        address input,
        address output
    ) external view returns (bool);

    /**
     * @dev updates internal state of the contract which holds the routes for input-output-pairs
     * Contract assumes that the respective intermediate pools for each pool are actually initialized
     * Does not check if all required swaps are enabled after the update
     * Previously defined paths can be overwritten but not deleted
     * Assumes that both the forward and return path are specified when both are used
     * Does not check if forward and backward paths are using the same intermediate pools
     * Reverts with custom error if any check is not passing
     */
    function updatePaths(bytes[] calldata newPaths) external;
}

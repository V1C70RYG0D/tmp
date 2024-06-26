// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract Swap {
    // uniswap
    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    IUniswapV2Router v2Router = IUniswapV2Router(UNISWAP_V2_ROUTER);

    constructor() {}

    function swapEthForTokens(
        address[] calldata _path,
        uint256 _amount,
        uint256 _amountOutMin,
        address _to,
        address payable[] calldata _feeWallets,
        uint256[] calldata _feeAmounts,
        uint256 _deadline
    ) external payable {
        v2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: _amount}(_amountOutMin, _path, _to, _deadline);

        for (uint256 i = 0; i < _feeWallets.length; i++) {
            _feeWallets[i].transfer(_feeAmounts[i]);
        }
    }

    function swapTokensForEth(
        address[] calldata _path,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _to,
        address payable[] calldata _feeWallets,
        uint256[] calldata _feeAmounts,
        uint256 _deadline
    ) external payable {
        // transfer the amount in tokens from msg.sender to this contract
        IERC20(_path[0]).transferFrom(msg.sender, address(this), _amountIn);

        //by calling IERC20 approve you allow the uniswap contract to spend the tokens in this contract
        IERC20(_path[0]).approve(UNISWAP_V2_ROUTER, _amountIn);

        v2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(_amountIn, _amountOutMin, _path, _to, _deadline);

        for (uint256 i = 0; i < _feeWallets.length; i++) {
            _feeWallets[i].transfer(_feeAmounts[i]);
        }
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint);

    function balanceOf(address account) external view returns (uint);

    function transfer(address recipient, uint amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint amount) external returns (bool);

    function transferFrom(address sender, address recipient, uint amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
}

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function WETH() external pure returns (address);

    function getAmountsOut(uint amountIn, address[] memory path) external view returns (uint[] memory amounts);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

contract FijaReceiveETH {
    function destroy(address payable receiver) external {
        selfdestruct(receiver);
    }

    receive() external payable {}
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

enum TxType {
    DEPOSIT,
    WITHDRAW,
    REDEEM,
    HARVEST,
    REBALANCE,
    EMERGENCY_MODE_WITHDRAW,
    EMERGENCY_MODE_DEPOSIT
}

struct TxParams {
    uint256 assets;
    uint256 tokens;
    address receiver;
    address owner;
    TxType txType;
}

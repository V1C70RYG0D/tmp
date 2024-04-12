// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// FijaVault errors
error VaultNoAssetMatching();
error VaultNotWhitelisted();
error VaultNoUpdateCandidate();
error VaultUpdateStrategyTimeError();
error VaultStrategyUndefined();
error VaultUnauthorizedAccess();

// FijaACL errors
error ACLOwnerZero();
error ACLGovZero();
error ACLResellZero();
error ACLNotOwner();
error ACLNotGov();
error ACLNotGovOwner();
error ACLNotReseller();
error ACLNotWhitelist();
error ACLTransferUserNotWhitelist();
error ACLDepositReceiverNotWhitelist();
error ACLRedeemWithdrawReceiverOwnerNotWhitelist();
error ACLWhitelistAddressZero();

// Strategy errors
error FijaUnauthorizedFlash();
error FijaInvalidAssetFlash();
error FijaStrategyUpdateInProgress();

// Transfer errors
error TransferDisbalance();
error NotEnoughETHSent();
error TransferFailed();

// emergency mode restriction
error FijaInEmergencyMode();

error FijaInsufficientAmountToWithdraw();
error FijaZeroInput();

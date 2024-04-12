// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./FijaStrategy.sol";
import "../interfaces/IFijaStrategy.sol";

import "../interfaces/IFijaVault2Txn.sol";
import "@aave/periphery-v3/contracts/misc/interfaces/IWETH.sol";

///
/// @title FijaStrategy2Txn
/// @author Fija
/// @notice Test strategy contract
/// @dev used for simulating 2 tx deposits/withdraw/redeem
/// processes on strategy contract
///
contract FijaStrategy2Txn is IFijaStrategy, FijaStrategy {
    constructor(
        IERC20 asset_,
        address governance_,
        string memory tokenName_,
        string memory tokenSymbol_,
        uint256 maxTicketSize_,
        uint256 maxVaultValue_
    )
        FijaStrategy(
            asset_,
            governance_,
            tokenName_,
            tokenSymbol_,
            maxTicketSize_,
            maxVaultValue_
        )
    {}

    ///
    /// NOTE: simulates 2 tx deposit process by notifying vault,
    /// strategy deposit process completed
    /// @inheritdoc FijaStrategy
    ///
    function deposit(
        uint256 assets,
        address receiver
    )
        public
        payable
        virtual
        override(FijaStrategy, IERC4626)
        returns (uint256)
    {
        uint256 amount = super.deposit(assets, receiver);

        // recover vault caller parameters
        TxParams memory params = IFijaVault2Txn(receiver).txParams();

        // notify vault by callback deposit is complete
        IFijaVault2Txn(receiver).afterDeposit(
            params.assets,
            params.tokens,
            params.receiver,
            true
        );

        return amount;
    }

    ///
    /// @dev Burns exact number of tokens from owner and sends assets to receiver.
    /// This method is used to simulate 2 tx redeem process, as it calls vault.afterRedeem to
    /// complete withdrawal process and send assets to caller
    /// @param tokens amount of tokens caller wants to redeem
    /// @param receiver address of the asset receiver
    /// @param owner address of the owner of tokens
    /// @return amount of assets receiver will receive based on exact burnt tokens
    /// NOTE: simulates 2 tx redeem process by notifying vault,
    /// strategy redeem process completed
    /// Emits IERC4626.Withdraw
    ///
    function redeem(
        uint256 tokens,
        address receiver,
        address owner
    ) public payable virtual override returns (uint256) {
        uint256 assets = super.redeem(tokens, receiver, owner);

        // recover vault caller parameters
        TxParams memory params = IFijaVault2Txn(owner).txParams();

        // notify vault by callback redeem is complete
        IFijaVault2Txn(owner).afterRedeem(
            params.tokens,
            params.receiver,
            params.owner,
            true
        );

        return assets;
    }

    ///
    /// @dev Burns tokens from owner and sends exact number of assets to receiver
    /// This method is used to simulate 2 tx withdraw process, as it calls vault.afterWithdraw to
    /// complete withdrawal process and send assets to caller
    /// @param assets amount of assets caller wants to withdraw
    /// @param receiver address of the asset receiver
    /// @param owner address of the owner of tokens
    /// @return amount of tokens burnt based on exact assets requested
    /// NOTE: simulates 2 tx withdraw process by notifying vault,
    /// strategy withdraw process completed
    /// Emits IERC4626.Withdraw
    ///
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public payable virtual override returns (uint256) {
        uint256 tokens = super.withdraw(assets, receiver, owner);

        // recover vault caller parameters
        TxParams memory params = IFijaVault2Txn(owner).txParams();

        // notify vault by callback withdraw is complete
        IFijaVault2Txn(owner).afterWithdraw(
            params.assets,
            params.receiver,
            params.owner,
            true
        );

        return tokens;
    }
}

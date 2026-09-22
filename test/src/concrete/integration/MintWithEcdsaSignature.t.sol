// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {Unauthorized} from "rain-vats-0.1.6/src/interface/IAuthorizeV1.sol";

import {ST0xOrchestrator} from "../../../../src/concrete/ST0xOrchestrator.sol";
import {IST0xOrchestratorV1, MintAuthV1, Digest} from "../../../../src/interface/IST0xOrchestratorV1.sol";
import {OrchestratorIntegrationTest} from "./OrchestratorIntegrationTest.sol";

/// @title MintWithEcdsaSignatureTest
/// @notice Workflow: an EOA recipient authorises a mint with an ECDSA
/// signature over the EIP-712 digest. Covers delivery, the recipient-scoped
/// `(to, nonce)` replay protection (and its `nonceUsed` view), and the
/// missing-vault-role negative.
contract MintWithEcdsaSignatureTest is OrchestratorIntegrationTest {
    /// The receipt is minted to and kept by the orchestrator at highwater+1;
    /// the shares are forwarded to the recipient in real rebased units; the
    /// orchestrator's own share balance nets to zero. Minting never touches
    /// the burn pointer: a fresh token's pointer starts (and stays) at 0.
    function testMintWithEcdsaSignatureDeliversShares() external {
        (address eoa, uint256 pk) = makeAddrAndKey("ecdsa-recipient");
        uint256 amount = 123e18;
        bytes32 nonce = keccak256("ecdsa");

        assertEq(vault.highwaterId(), 0, "fresh vault has no receipts");
        assertFalse(orchestrator.nonceUsed(eoa, nonce), "nonce unused before the mint");

        MintAuthV1 memory auth = _signedMintAuth(address(vault), eoa, amount, nonce, pk);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, amount, auth, "");

        uint256 mintedId = vault.highwaterId();
        assertEq(mintedId, 1, "first mint lands at id 1");
        assertEq(vault.balanceOf(eoa), amount, "recipient received the rebased shares");
        assertEq(receipt.balanceOf(address(orchestrator), mintedId), amount, "orchestrator holds the receipt");
        assertEq(IERC20(address(vault)).balanceOf(address(orchestrator)), 0, "orchestrator holds no shares");
        assertEq(orchestrator.nextBurnReceiptId(address(vault)), 0, "mint never touches the pointer; it stays at 0");
        assertTrue(orchestrator.nonceUsed(eoa, nonce), "nonce consumed by the mint");
    }

    /// Replay protection is namespaced by `(to, nonce)`: once a recipient's
    /// nonce is consumed it can never be reused for that recipient — even
    /// with a freshly signed authorisation over a DIFFERENT amount — while
    /// the same nonce remains free for a different recipient.
    function testMintNonceReplayAcrossAmountsReverts() external {
        (address eoa, uint256 pk) = makeAddrAndKey("replay-recipient");
        bytes32 nonce = keccak256("replay");

        MintAuthV1 memory auth = _signedMintAuth(address(vault), eoa, 10e18, nonce, pk);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, 10e18, auth, "");
        assertTrue(orchestrator.nonceUsed(eoa, nonce), "nonce consumed");

        // A fresh, valid signature over a different amount cannot resurrect
        // the nonce for the same recipient.
        MintAuthV1 memory replayAuth = _signedMintAuth(address(vault), eoa, 5e18, nonce, pk);
        vm.prank(MM);
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.NonceReplayed.selector, eoa, nonce));
        orchestrator.mint(address(vault), eoa, 5e18, replayAuth, "");

        // The SAME nonce is still free for a different recipient.
        (address other, uint256 otherPk) = makeAddrAndKey("other-recipient");
        assertFalse(orchestrator.nonceUsed(other, nonce), "nonce namespaced per recipient");
        MintAuthV1 memory otherAuth = _signedMintAuth(address(vault), other, 3e18, nonce, otherPk);
        vm.prank(MM);
        orchestrator.mint(address(vault), other, 3e18, otherAuth, "");
        assertEq(vault.balanceOf(other), 3e18, "other recipient minted with the same nonce");
    }

    /// A fresh orchestrator with `MINT_ROLE` granted but WITHOUT the vault's
    /// `DEPOSIT` grant on the authoriser cannot mint: the vault's `mint` leg
    /// reverts the rain-vats `Unauthorized`.
    function testMintRevertsWithoutVaultRoles() external {
        // Fresh orchestrator, never granted DEPOSIT/WITHDRAW on the authoriser.
        ST0xOrchestrator fresh = _deployOrchestrator(OWNER);
        bytes32 mintRole = fresh.MINT_ROLE();
        vm.prank(OWNER);
        fresh.grantRole(mintRole, MM);

        (address eoa, uint256 pk) = makeAddrAndKey("norole-recipient");
        uint256 amount = 1e18;
        bytes32 nonce = keccak256("norole");
        bytes32 digest = Digest.unwrap(fresh.mintAuthDigest(address(vault), eoa, amount, nonce));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        MintAuthV1 memory auth = MintAuthV1({nonce: nonce, signature: abi.encodePacked(r, s, v)});

        vm.prank(MM);
        vm.expectPartialRevert(Unauthorized.selector);
        fresh.mint(address(vault), eoa, amount, auth, "");
    }
}

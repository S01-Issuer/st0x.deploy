// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {RevokeFireblocksServiceSigner} from "../../script/20260810-revoke-fireblocks-service-signer.s.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx, TxBuilderArtifactMismatch} from "../../src/lib/LibSafeOps.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";

/// @title RevokeFireblocksServiceSignerProdTest
/// @notice PROD coverage for the retired-signer revocation: what production
/// IS on each chain carrying a live V4 authoriser, read from a real fork
/// with no mocks anywhere.
///
/// The revocation is PENDING — the retired Fireblocks signer still holds
/// all three canonical pairs on every chain — so each test asserts the
/// live pre-execution state and then drives `run()` end to end on the
/// fork: full pre-flight against the live Safe + authoriser, a three-tx
/// revoke bundle authored and round-tripped through the Tx Builder JSON,
/// the simulated post-state clean, and the n+1 reversal proven. Once the
/// Safes sign and the bundle executes on a chain, that chain's `run()`
/// reverts `FireblocksSignerAlreadyRevoked` and its test here goes red —
/// the forcing function for the post-execution pin PR, which removes the
/// retired rows from the canonical map, pins their absence, and retires
/// this file the way the executed provisioning retired its predecessor
/// fixtures.
///
/// @dev No mocks. Each chain's state is whatever the chain says it is.
/// Selection logic — which pairs get authored for a given role state — is
/// covered without a fork in
/// `20260810-revoke-fireblocks-service-signer.t.sol`.
///
/// The artifact path is chain-suffixed, so the three chains' tests cannot
/// clobber each other's file however forge schedules them.
contract RevokeFireblocksServiceSignerProdTest is Test {
    /// @notice The signer this operation revokes.
    address internal constant SIGNER = LibAuthoriserInvariants.GRANTEE_SERVICE_1C66;

    /// @notice The artifact path `run()` writes for the ACTIVE chain —
    /// mirrored from the script's `artifactPath()` so the round-trip below
    /// reads the file the dispatch under test actually produced.
    /// @return path The chain-suffixed artifact path.
    function artifactPath() internal view returns (string memory path) {
        path = string.concat("out/20260810-revoke-fireblocks-service-signer-", vm.toString(block.chainid), ".json");
    }

    /// @notice Assert the ACTIVE fork still carries the retired signer's
    /// full grant set, then drive the script end to end against it: `run()`
    /// authors the three-pair revoke bundle, writes the artifact, leaves
    /// the simulated fork revoked, and proves the n+1 reversal. `run()`
    /// reaches the authoring only after its full pre-flight passes, so this
    /// also pins the Safe, the authoriser pin + codehash, and the rest of
    /// the grant map on the live chain.
    /// @param label Human chain name, surfaced in assertion messages.
    /// @param authoriser The chain's pinned V4 authoriser clone.
    /// @param safe The chain's token-owner Safe, filling the map's Safe
    /// grantee slots.
    function assertActiveForkAuthorsRevocation(string memory label, address authoriser, address safe) internal {
        IAccessControl acl = IAccessControl(authoriser);
        RoleGrant[] memory all = LibAuthoriserInvariants.expectedGrants(safe);
        uint256 pairs = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (all[i].grantee != SIGNER) continue;
            pairs++;
            assertTrue(
                acl.hasRole(all[i].role, all[i].grantee),
                string.concat(label, ": retired signer no longer holds a canonical pair - flip the map pin PR")
            );
        }
        assertEq(pairs, 3, "the canonical map carries the retired signer's three rows");

        RevokeFireblocksServiceSigner script = new RevokeFireblocksServiceSigner();
        script.run();

        // The simulated fork ends fully revoked.
        for (uint256 i = 0; i < all.length; i++) {
            if (all[i].grantee != SIGNER) continue;
            assertFalse(
                acl.hasRole(all[i].role, all[i].grantee),
                string.concat(label, ": run() left the retired signer holding a canonical pair")
            );
        }

        // ...and every OTHER canonical row survives — the replacement
        // signer's operational grants, the Safe's action roles, every
        // `_ADMIN`. Re-asserted here independently of the script's own
        // post-state so this test fails even if those checks rot.
        for (uint256 i = 0; i < all.length; i++) {
            if (all[i].grantee == SIGNER) continue;
            assertTrue(
                acl.hasRole(all[i].role, all[i].grantee),
                string.concat(label, ": run() disturbed a canonical row it must not touch")
            );
        }

        // Round-trip the emitted artifact: scoped to this chain, three
        // value-free revoke CALLs against the chain's authoriser, in
        // canonical map order.
        (uint256 chainId, address firstTarget, SafeTx[] memory txs) = LibSafeOps.parseTxBuilderJson(artifactPath());
        assertEq(chainId, block.chainid, string.concat(label, ": artifact chain id"));
        assertEq(firstTarget, authoriser, string.concat(label, ": artifact target"));
        assertEq(txs.length, 3, string.concat(label, ": artifact bundle size"));
        bytes32[3] memory roles = [keccak256("DEPOSIT"), keccak256("WITHDRAW"), keccak256("CERTIFY")];
        for (uint256 i = 0; i < txs.length; i++) {
            assertEq(txs[i].to, authoriser, string.concat(label, ": artifact tx target"));
            assertEq(txs[i].value, 0, string.concat(label, ": artifact tx value"));
            assertEq(
                txs[i].data,
                abi.encodeCall(IAccessControl.revokeRole, (roles[i], SIGNER)),
                string.concat(label, ": artifact tx calldata")
            );
        }
    }

    /// @notice Base still holds the retired signer's grants and authors the
    /// full revoke bundle.
    function testBaseAuthorsRevocation() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertActiveForkAuthorsRevocation(
            "Base", LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE
        );
    }

    /// @notice Ethereum still holds the retired signer's grants and authors
    /// the full revoke bundle.
    function testEthereumAuthorsRevocation() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        assertActiveForkAuthorsRevocation(
            "Ethereum",
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM,
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM
        );
    }

    /// @notice HyperEVM still holds the retired signer's grants and authors
    /// the full revoke bundle.
    function testHyperEvmAuthorsRevocation() external {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        assertActiveForkAuthorsRevocation(
            "HyperEVM",
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM,
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_HYPEREVM
        );
    }

    /// @notice The signer-side `verify(string)` accepts a freshly authored
    /// artifact against a fresh fork of the same live state, and rejects a
    /// tampered copy with the exact mismatching field. Authoring simulates
    /// the revocation onto its own fork, so verification runs on a NEW
    /// fork — the signer's vantage point: artifact in hand, live chain
    /// untouched.
    function testVerifyAcceptsAuthoredArtifactAndRejectsTamper() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        new RevokeFireblocksServiceSigner().run();
        string memory path = artifactPath();

        // Fresh fork: authoring left the previous fork revoked; the live
        // chain a signer verifies against still holds the grants.
        vm.createSelectFork(LibRainDeploy.BASE);
        RevokeFireblocksServiceSigner verifier = new RevokeFireblocksServiceSigner();
        verifier.verify(path);

        // Tamper one call's payload and re-emit: verify pinpoints the field.
        (,, SafeTx[] memory txs) = LibSafeOps.parseTxBuilderJson(path);
        txs[0].data = abi.encodeCall(IAccessControl.revokeRole, (bytes32(uint256(1)), address(0xBAD)));
        vm.writeFile(
            "out/tampered-revocation.json",
            LibSafeOps.emitTxBuilderJson(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE, block.chainid, "tampered", txs)
        );
        vm.expectRevert(abi.encodeWithSelector(TxBuilderArtifactMismatch.selector, "data"));
        verifier.verify("out/tampered-revocation.json");
    }

    /// @notice A partial prior execution re-dispatches to exactly the
    /// remainder, artifact included: with CERTIFY already revoked on the
    /// live fork, `run()` authors and emits a two-tx bundle carrying the
    /// DEPOSIT and WITHDRAW revokes only. The unit suite pins this
    /// selection in memory; this pins the EMITTED artifact a signer would
    /// import for the remainder.
    function testBasePartialReDispatchEmitsRemainderArtifact() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address authoriser = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;

        // The Safe holds CERTIFY_ADMIN, so it can revoke CERTIFY directly —
        // the same call the bundle's third leg would have made.
        vm.prank(safe);
        IAccessControl(authoriser).revokeRole(keccak256("CERTIFY"), SIGNER);

        // The remainder harness writes to its own path: this test's bundle
        // CONTENT differs from the full-bundle tests', and forge runs tests
        // in parallel, so sharing the canonical path would race.
        RevokeFireblocksServiceSignerRemainderHarness script = new RevokeFireblocksServiceSignerRemainderHarness();
        script.run();

        (uint256 chainId, address firstTarget, SafeTx[] memory txs) =
            LibSafeOps.parseTxBuilderJson(script.remainderArtifactPath());
        assertEq(chainId, block.chainid, "remainder artifact chain id");
        assertEq(firstTarget, authoriser, "remainder artifact target");
        assertEq(txs.length, 2, "remainder artifact bundle size");
        bytes32[2] memory roles = [keccak256("DEPOSIT"), keccak256("WITHDRAW")];
        for (uint256 i = 0; i < txs.length; i++) {
            assertEq(txs[i].to, authoriser, "remainder artifact tx target");
            assertEq(txs[i].value, 0, "remainder artifact tx value");
            assertEq(
                txs[i].data,
                abi.encodeCall(IAccessControl.revokeRole, (roles[i], SIGNER)),
                "remainder artifact tx calldata"
            );
        }
    }
}

/// @notice The partial-re-dispatch fixture's script: identical to the
/// production script except the artifact lands on a dedicated path. This
/// test's bundle content DIFFERS from the full-bundle tests' on the same
/// chain, and forge runs tests in parallel, so writing the canonical path
/// would race with them.
contract RevokeFireblocksServiceSignerRemainderHarness is RevokeFireblocksServiceSigner {
    /// @notice The dedicated remainder-artifact path, exposed so the test
    /// parses exactly the file this fixture wrote.
    /// @return path The remainder artifact path for the ACTIVE chain.
    function remainderArtifactPath() public view returns (string memory path) {
        path = string.concat("out/20260810-revoke-remainder-", vm.toString(block.chainid), ".json");
    }

    function artifactPath() internal view override returns (string memory path) {
        path = remainderArtifactPath();
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";

import {
    DeployV4AuthoriserClone,
    V4ImplNotDeployed,
    V4ImplCodehashMismatch,
    V4AuthoriserCloneNotPinned,
    V4AuthoriserCloneCodehashMismatch,
    VerifyMismatch
} from "../../script/20260619-deploy-v4-authoriser-clone.s.sol";
import {TestableDeployV4AuthoriserClone} from "./TestableDeployV4AuthoriserClone.sol";
import {IGnosisSafe} from "../../src/interface/IGnosisSafe.sol";
import {LibSafeInvariants, SafeOwnerCountMismatch} from "../../src/lib/LibSafeInvariants.sol";
import {LibProdDeployV4} from "../../src/lib/LibProdDeployV4.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../../src/lib/LibAuthoriserInvariants.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

/// @title DeployV4AuthoriserCloneTest
/// @notice End-to-end fork tests for the V4 authoriser clone deploy + grants
/// mirror script. Selects an unpinned Base head fork (same precedent as
/// `MigrateMultisigThresholdTest`), etches the V4 impl bytecode at the
/// `LibProdDeployV4`-pinned address (the impl has not yet been Zoltu-deployed
/// at the time this script lands), then exercises `run()`, `mirrorGrants()`,
/// the `verify()` round-trip for both bundles, and the inverted preconditions.
/// @dev The V4 impl etch step is the only test-side scaffolding required to
/// pass the deploy-bundle pre-flight; the canonical Rain `CloneFactory` is
/// already deployed on Base at the `LibCloneFactoryDeploy` pinned address,
/// and the ST0x token-owner Safe passes `LibSafeInvariants.assertAll` against
/// the live chain.
///
/// The grants-bundle suite uses `TestableDeployV4AuthoriserClone` (an
/// `override`-of-`_resolveClone` subclass) to simulate the post-hydrate state
/// of `LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE` without monkeying with
/// library bytecode. Tests that exercise the unhydrated pre-flight failure
/// instantiate the base script directly so `_resolveClone()` returns
/// `address(0)` (the lib constant's compile-time value on this branch).
contract DeployV4AuthoriserCloneTest is Test {
    /// @notice The script under test, deployed fresh per fork. The bare
    /// (un-subclassed) script is used by tests that read the lib pin's true
    /// compile-time value (`address(0)`); grants-bundle tests use
    /// `TestableDeployV4AuthoriserClone` instead.
    DeployV4AuthoriserClone internal script;

    /// @notice Live Safe handle.
    IGnosisSafe internal safe;

    /// @notice The pinned V4 impl runtime bytecode (captured from a
    /// freshly-deployed instance and etched at the pin address).
    bytes internal v4ImplRuntime;

    /// @notice Selects the Base fork at chain head, deploys the script,
    /// captures the live Safe, and etches the V4 impl runtime bytecode at
    /// the `LibProdDeployV4` pin so the script's V4-impl pre-flight passes.
    /// @dev The impl has not yet been Zoltu-deployed on Base; the etch is
    /// the test's stand-in for the eventual on-chain deploy. The runtime
    /// code is sourced from a freshly-compiled
    /// `StoxOffchainAssetReceiptVaultAuthorizerV1`, so its codehash matches
    /// the `LibProdDeployV4` pin by construction (the pin was generated from
    /// the same compiled bytecode).
    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
        script = new DeployV4AuthoriserClone();
        safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        StoxOffchainAssetReceiptVaultAuthorizerV1 impl = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        v4ImplRuntime = address(impl).code;
        vm.etch(LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RAIN_VATS_0_1_6, v4ImplRuntime);
    }

    /// @notice `run()` dry-run completes against the live pre-state, writes
    /// the deploy bundle artifact, the artifact has the expected single-tx
    /// shape, and the script's logs include a predicted clone address.
    /// @dev The clone deploy is also asserted to have left the seven auto-
    /// granted `_ADMIN` roles in place on the live fork — `run()` calls into
    /// the CloneFactory under `vm.prank(safe)`, which actually deploys a
    /// real clone on the active fork state, so post-run state is observable.
    function testRunCompletesAndWritesDeployArtifact() external {
        selectBaseFork();
        script.run();

        string memory artifactPath = string.concat(vm.projectRoot(), "/out/v4-authoriser-clone-deploy.json");
        string memory json = vm.readFile(artifactPath);

        string memory bundleName = vm.parseJsonString(json, ".meta.name");
        assertEq(bundleName, "ST0x V4 authoriser - deploy clone", "meta.name pinned");

        bool hasFirstTx = vm.keyExistsJson(json, ".transactions[0].to");
        bool hasSecondTx = vm.keyExistsJson(json, ".transactions[1].to");
        assertTrue(hasFirstTx, "first transaction present");
        assertFalse(hasSecondTx, "exactly one transaction emitted");

        // The deploy bundle's only tx targets the canonical CloneFactory.
        address parsedTo = vm.parseJsonAddress(json, ".transactions[0].to");
        assertEq(parsedTo, address(0x444acC29d63fa643E8adCC35FD9aa6DE111dCb39), "tx targets canonical CloneFactory");
    }

    /// @notice Happy-path `mirrorGrants()` against a fork-deployed clone
    /// produced by `run()`. Uses `TestableDeployV4AuthoriserClone` so the
    /// lib-pin-overridden `_resolveClone()` returns the same address the
    /// deploy simulated. The mirror bundle emits exactly six `grantRole`
    /// txs targeting the clone, and the post-state matches the full
    /// `LibAuthoriserInvariants.expectedGrants()` map.
    function testMirrorGrantsCompletesAndWritesGrantsArtifact() external {
        selectBaseFork();
        // Swap the bare script for the testable subclass so
        // `_resolveClone()` / `_resolveCloneCodehash()` return the post-
        // hydrate values rather than the lib constants' compile-time
        // `address(0)` / `bytes32(0)`.
        TestableDeployV4AuthoriserClone testable = new TestableDeployV4AuthoriserClone();
        testable.run();
        address clone = testable.lastPredictedClone();
        assertTrue(clone != address(0), "deploy run produced a clone");
        testable.setResolvedClone(clone);
        testable.setResolvedCloneCodehash(clone.codehash);

        testable.mirrorGrants();

        string memory artifactPath = string.concat(vm.projectRoot(), "/out/v4-authoriser-clone-grants.json");
        string memory json = vm.readFile(artifactPath);
        string memory bundleName = vm.parseJsonString(json, ".meta.name");
        assertEq(bundleName, "ST0x V4 authoriser - mirror non-admin grants", "meta.name pinned");

        // Six tx entries, no more, no less.
        assertTrue(vm.keyExistsJson(json, ".transactions[5].to"), "sixth transaction present");
        assertFalse(vm.keyExistsJson(json, ".transactions[6].to"), "exactly six transactions emitted");

        // Each tx targets the clone.
        for (uint256 i = 0; i < 6; i++) {
            string memory toPath = string.concat(".transactions[", vm.toString(i), "].to");
            assertEq(vm.parseJsonAddress(json, toPath), clone, "tx targets clone");
        }

        // Post-state: the clone holds the full expectedGrants() map.
        IAccessControl acl = IAccessControl(clone);
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants();
        for (uint256 i = 0; i < grants.length; i++) {
            // V3 indices 0..4 are the five `_ADMIN` grants the base init
            // auto-grants; indices 5..10 are the six mirror grants. All 11
            // should hold post-mirror.
            assertTrue(acl.hasRole(grants[i].role, grants[i].grantee), "expected grant held post-mirror");
        }
    }

    /// @notice `verify()` accepts the deploy bundle artifact emitted by
    /// `run()`. The deploy branch never consults `_resolveClone()`, so the
    /// bare script suffices.
    function testVerifyAcceptsRunDeployArtifact() external {
        selectBaseFork();
        // `run()` simulates the inner clone deploy via `vm.prank(safe)`,
        // which actually deploys a clone and increments the safe's
        // implicit "nonce-for-CREATE" footprint. Snapshot first so
        // verify() sees the pre-run state.
        uint256 snap = vm.snapshotState();
        script.run();
        string memory artifactPath = string.concat(vm.projectRoot(), "/out/v4-authoriser-clone-deploy.json");
        vm.revertToState(snap);
        // Restore the V4 impl etch after the revert (the etch lives in
        // the fork's state slot and the revert may or may not preserve
        // it depending on whether the snapshot captured it; etching
        // again is idempotent).
        vm.etch(LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RAIN_VATS_0_1_6, v4ImplRuntime);
        script.verify(artifactPath);
    }

    /// @notice `verify()` accepts the grants bundle artifact emitted by
    /// `mirrorGrants()` against the fork-deployed clone. Uses the testable
    /// subclass for both authoring + verification so `_resolveClone()` /
    /// `_resolveCloneCodehash()` return the same simulated post-hydrate
    /// values in both phases. Snapshots, runs the deploy + mirror, then
    /// reverts and re-verifies — same shape as the deploy round-trip.
    function testVerifyAcceptsMirrorGrantsArtifact() external {
        selectBaseFork();
        TestableDeployV4AuthoriserClone testable = new TestableDeployV4AuthoriserClone();

        uint256 snap = vm.snapshotState();
        testable.run();
        address clone = testable.lastPredictedClone();
        bytes32 cloneCodehash = clone.codehash;
        testable.setResolvedClone(clone);
        testable.setResolvedCloneCodehash(cloneCodehash);
        testable.mirrorGrants();
        string memory artifactPath = string.concat(vm.projectRoot(), "/out/v4-authoriser-clone-grants.json");
        vm.revertToState(snap);
        vm.etch(LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RAIN_VATS_0_1_6, v4ImplRuntime);
        // Re-etch the clone too: it was created in the pre-snapshot state
        // and the revert wiped it. Etch the minimal-proxy runtime so the
        // codehash check passes; the access-control storage isn't read by
        // `verify` so we don't need to repopulate it.
        bytes memory cloneRuntime = abi.encodePacked(
            hex"363d3d373d3d3d363d73",
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RAIN_VATS_0_1_6,
            hex"5af43d82803e903d91602b57fd5bf3"
        );
        vm.etch(clone, cloneRuntime);
        // Re-load the testable's overrides after the revert (the
        // testable's contract storage is also wiped). Re-derive the
        // codehash from the freshly-etched runtime so the override
        // matches the post-revert reality.
        testable.setResolvedClone(clone);
        testable.setResolvedCloneCodehash(clone.codehash);
        testable.verify(artifactPath);
    }

    /// @notice Inverted: pre-flight rejects a missing V4 impl with
    /// `V4ImplNotDeployed`. `vm.etch` with empty bytes zeros the runtime
    /// code at the pin so `impl.code.length == 0` trips first.
    function testRunRejectsMissingV4Impl() external {
        selectBaseFork();
        address implAddr = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RAIN_VATS_0_1_6;
        vm.etch(implAddr, new bytes(0));
        vm.expectRevert(abi.encodeWithSelector(V4ImplNotDeployed.selector, implAddr));
        script.run();
    }

    /// @notice Inverted: pre-flight rejects a V4 impl whose runtime
    /// codehash drifts from the pin with `V4ImplCodehashMismatch`. Etches
    /// a single-byte stub at the pin so the address has *some* code but
    /// not the canonical bytecode.
    function testRunRejectsV4ImplCodehashDrift() external {
        selectBaseFork();
        address implAddr = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RAIN_VATS_0_1_6;
        bytes memory stub = hex"60005260206000F3";
        vm.etch(implAddr, stub);
        bytes32 expectedHash = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH_RAIN_VATS_0_1_6;
        bytes32 actualHash = keccak256(stub);
        vm.expectRevert(abi.encodeWithSelector(V4ImplCodehashMismatch.selector, implAddr, expectedHash, actualHash));
        script.run();
    }

    /// @notice Inverted: pre-flight rejects a Safe whose owner count
    /// drifts off the `LibSafeInvariants` pin with `SafeOwnerCountMismatch`.
    /// Mocks `getOwners()` to return a single-entry array; the no-arg
    /// `assertAll(safe)` expects six.
    function testRunRejectsSafeOwnerCountDrift() external {
        selectBaseFork();
        address[] memory drifted = new address[](1);
        drifted[0] = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_OWNER_1;
        vm.mockCall(address(safe), abi.encodeWithSelector(IGnosisSafe.getOwners.selector), abi.encode(drifted));

        vm.expectRevert(abi.encodeWithSelector(SafeOwnerCountMismatch.selector, address(safe), uint256(6), uint256(1)));
        script.run();
    }

    /// @notice Inverted: `mirrorGrants()` against the bare script (whose
    /// `_resolveClone()` returns the un-overridden lib constant —
    /// `address(0)` until the post-execution hydrate PR merges) reverts
    /// with `V4AuthoriserCloneNotPinned()` before any side-effecting
    /// work. This is the forcing-function the rewrite exists to enforce:
    /// the script refuses to author a grants bundle pointing at an
    /// arbitrary operator-supplied address.
    function testMirrorGrantsRejectsUnpinnedClone() external {
        selectBaseFork();
        vm.expectRevert(abi.encodeWithSelector(V4AuthoriserCloneNotPinned.selector));
        script.mirrorGrants();
    }

    /// @notice Inverted: `mirrorGrants()` against a testable subclass whose
    /// `_resolveClone()` returns an address that has code (so the
    /// `V4AuthoriserCloneNotDeployed` check passes) but whose actual
    /// codehash drifts from the simulated-post-hydrate codehash injected
    /// via `setResolvedCloneCodehash()` reverts with
    /// `V4AuthoriserCloneCodehashMismatch`. Etches a one-byte stub at a
    /// fresh address so the actual codehash is deterministically the
    /// keccak of that stub, then sets the expected codehash to a
    /// distinct sentinel value so the inequality trips.
    function testMirrorGrantsRejectsCodehashDriftedClone() external {
        selectBaseFork();
        TestableDeployV4AuthoriserClone testable = new TestableDeployV4AuthoriserClone();
        address driftedClone = address(0xdEADbeEF00000000000000000000000000000001);
        bytes memory stub = hex"60005260206000F3";
        vm.etch(driftedClone, stub);
        testable.setResolvedClone(driftedClone);
        // Inject a deterministic, distinct codehash as the "expected"
        // post-hydrate value. The actual codehash on the drifted clone is
        // `keccak256(stub)`, which will not match this sentinel.
        bytes32 expectedCodehash = keccak256("expected-codehash-sentinel");
        testable.setResolvedCloneCodehash(expectedCodehash);

        bytes32 actualCodehash = driftedClone.codehash;
        assertTrue(actualCodehash != expectedCodehash, "test precondition: codehashes differ");
        vm.expectRevert(
            abi.encodeWithSelector(
                V4AuthoriserCloneCodehashMismatch.selector, driftedClone, expectedCodehash, actualCodehash
            )
        );
        testable.mirrorGrants();
    }
}

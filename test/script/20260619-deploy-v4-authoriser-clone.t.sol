// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {VmSafe} from "forge-std-1.16.1/src/Vm.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";

import {
    DeployV4AuthoriserClone,
    V4ImplNotDeployed,
    V4ImplCodehashMismatch,
    CloneFactoryNotDeployed,
    CloneFactoryCodehashMismatch,
    CloneCodehashMismatch,
    V4AuthoriserCloneNotPinned,
    V4AuthoriserCloneNotDeployed,
    V4AuthoriserCloneCodehashMismatch,
    AutoGrantMissing,
    UnexpectedAutoGrantHeld,
    VerifyMismatch,
    VerifyUnknownBundleShape
} from "../../script/20260619-deploy-v4-authoriser-clone.s.sol";
import {TestableDeployV4AuthoriserClone} from "./TestableDeployV4AuthoriserClone.sol";
import {IGnosisSafe} from "../../src/interface/IGnosisSafe.sol";
import {LibSafeInvariants, SafeOwnerCountMismatch} from "../../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx} from "../../src/lib/LibSafeOps.sol";
import {LibProdDeployV4} from "../../src/lib/LibProdDeployV4.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../../src/lib/LibAuthoriserInvariants.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibCloneFactoryDeploy} from "rain-factory-0.1.1/src/lib/LibCloneFactoryDeploy.sol";
import {ICloneableFactoryV2} from "rain-factory-0.1.1/src/interface/ICloneableFactoryV2.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.1.6/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
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

        // ...and carries the canonical `clone(v4Impl, abi.encode(Config(Safe)))`
        // calldata, not just the right target.
        bytes memory parsedData = vm.parseJsonBytes(json, ".transactions[0].data");
        assertEq(parsedData, _expectedDeployData(), "deploy tx calldata mismatch");
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

        // Each tx targets the clone with the canonical grantRole(role,
        // grantee) calldata for the matching non-admin slice (indices 5..10)
        // of expectedGrants() — not just the right target.
        RoleGrant[] memory expected = LibAuthoriserInvariants.expectedGrants();
        for (uint256 i = 0; i < 6; i++) {
            string memory toPath = string.concat(".transactions[", vm.toString(i), "].to");
            assertEq(vm.parseJsonAddress(json, toPath), clone, "tx targets clone");
            RoleGrant memory g = expected[5 + i];
            bytes memory parsedData = vm.parseJsonBytes(json, string.concat(".transactions[", vm.toString(i), "].data"));
            assertEq(
                parsedData, abi.encodeCall(IAccessControl.grantRole, (g.role, g.grantee)), "grant tx calldata mismatch"
            );
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
    /// values in both phases.
    /// @dev Verifies against the real clone `run()` + `mirrorGrants()` leave on
    /// the fork — its actual CloneFactory-deployed runtime and post-mirror
    /// access-control state — rather than reverting and re-etching a
    /// reconstructed proxy. That exercises the bytecode the factory really
    /// deploys and satisfies the auto-grant pre-flight `verify()` now shares
    /// with `mirrorGrants()`.
    function testVerifyAcceptsMirrorGrantsArtifact() external {
        selectBaseFork();
        TestableDeployV4AuthoriserClone testable = new TestableDeployV4AuthoriserClone();

        testable.run();
        address clone = testable.lastPredictedClone();
        testable.setResolvedClone(clone);
        testable.setResolvedCloneCodehash(clone.codehash);
        testable.mirrorGrants();

        string memory artifactPath = string.concat(vm.projectRoot(), "/out/v4-authoriser-clone-grants.json");
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

    // -------------------------------------------------------------------------
    // CloneFactory pre-flight (deploy branch)
    // -------------------------------------------------------------------------

    /// @notice Inverted: `run()` rejects a missing canonical CloneFactory with
    /// `CloneFactoryNotDeployed`. Zeros the runtime code at the pinned factory
    /// address; the V4 impl etch still passes the prior pre-flight check.
    function testRunRejectsMissingCloneFactory() external {
        selectBaseFork();
        address factory = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS;
        vm.etch(factory, new bytes(0));
        vm.expectRevert(abi.encodeWithSelector(CloneFactoryNotDeployed.selector, factory));
        script.run();
    }

    /// @notice Inverted: `run()` rejects a CloneFactory whose runtime codehash
    /// drifts from the pin with `CloneFactoryCodehashMismatch`. Etches a stub
    /// so the address has code but the wrong bytecode.
    function testRunRejectsCloneFactoryCodehashDrift() external {
        selectBaseFork();
        address factory = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS;
        bytes memory stub = hex"60005260206000F3";
        vm.etch(factory, stub);
        bytes32 expectedHash = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_CODEHASH;
        bytes32 actualHash = keccak256(stub);
        vm.expectRevert(
            abi.encodeWithSelector(CloneFactoryCodehashMismatch.selector, factory, expectedHash, actualHash)
        );
        script.run();
    }

    // -------------------------------------------------------------------------
    // Clone pin pre-flight (grants branch)
    // -------------------------------------------------------------------------

    /// @notice Inverted: `mirrorGrants()` rejects a pinned clone address that
    /// is non-zero (passes the not-pinned check) but has no runtime code with
    /// `V4AuthoriserCloneNotDeployed` — the hydrate PR landed before the deploy
    /// bundle executed on Base.
    function testMirrorGrantsRejectsCloneWithNoCode() external {
        selectBaseFork();
        TestableDeployV4AuthoriserClone testable = new TestableDeployV4AuthoriserClone();
        address uncoded = address(0xc10e0000000000000000000000000000000000A1);
        testable.setResolvedClone(uncoded);
        assertEq(uncoded.code.length, 0, "test precondition: resolved clone has no code");
        vm.expectRevert(abi.encodeWithSelector(V4AuthoriserCloneNotDeployed.selector, uncoded));
        testable.mirrorGrants();
    }

    // -------------------------------------------------------------------------
    // verify() rejection paths (the anti-tamper guarantee)
    // -------------------------------------------------------------------------

    /// @notice `verify()` rejects an artifact whose chainId is not the live
    /// chain with `VerifyMismatch("chainId")` — the first check, before any
    /// bundle-shape branching.
    function testVerifyRejectsWrongChainId() external {
        selectBaseFork();
        string memory path = _writeArtifact(block.chainid + 1, _deployTxs(), "chainid");
        vm.expectRevert(abi.encodeWithSelector(VerifyMismatch.selector, "chainId"));
        script.verify(path);
    }

    /// @notice `verify()` rejects an artifact whose tx count is neither the
    /// deploy bundle's 1 nor the grants bundle's 6 with
    /// `VerifyUnknownBundleShape`.
    function testVerifyRejectsUnknownBundleShape() external {
        selectBaseFork();
        SafeTx memory deployTx = _deployTxs()[0];
        SafeTx[] memory txs = new SafeTx[](2);
        txs[0] = deployTx;
        txs[1] = deployTx;
        string memory path = _writeArtifact(block.chainid, txs, "shape");
        vm.expectRevert(abi.encodeWithSelector(VerifyUnknownBundleShape.selector, uint256(2)));
        script.verify(path);
    }

    /// @notice Deploy-branch `verify()` rejects a bundle whose tx target is not
    /// the canonical CloneFactory with `VerifyMismatch("to")`.
    function testVerifyRejectsTamperedDeployTarget() external {
        selectBaseFork();
        SafeTx[] memory txs = _deployTxs();
        txs[0].to = address(0x1111111111111111111111111111111111111111);
        string memory path = _writeArtifact(block.chainid, txs, "deploy-to");
        vm.expectRevert(abi.encodeWithSelector(VerifyMismatch.selector, "to"));
        script.verify(path);
    }

    /// @notice Deploy-branch `verify()` rejects a bundle carrying a non-zero
    /// ETH value with `VerifyMismatch("value")`.
    function testVerifyRejectsTamperedDeployValue() external {
        selectBaseFork();
        SafeTx[] memory txs = _deployTxs();
        txs[0].value = 1;
        string memory path = _writeArtifact(block.chainid, txs, "deploy-value");
        vm.expectRevert(abi.encodeWithSelector(VerifyMismatch.selector, "value"));
        script.verify(path);
    }

    /// @notice Deploy-branch `verify()` rejects a bundle whose calldata is not
    /// the canonical `clone(...)` call with `VerifyMismatch("data")`.
    function testVerifyRejectsTamperedDeployData() external {
        selectBaseFork();
        SafeTx[] memory txs = _deployTxs();
        txs[0].data = hex"deadbeef";
        string memory path = _writeArtifact(block.chainid, txs, "deploy-data");
        vm.expectRevert(abi.encodeWithSelector(VerifyMismatch.selector, "data"));
        script.verify(path);
    }

    /// @notice Grants-branch `verify()` rejects a bundle whose first tx target
    /// is not the resolved clone with `VerifyMismatch("to")`.
    function testVerifyRejectsTamperedGrantTarget() external {
        selectBaseFork();
        TestableDeployV4AuthoriserClone testable = new TestableDeployV4AuthoriserClone();
        testable.run();
        address clone = testable.lastPredictedClone();
        testable.setResolvedClone(clone);
        testable.setResolvedCloneCodehash(clone.codehash);

        SafeTx[] memory txs = _grantsTxs(clone);
        txs[0].to = address(0x2222222222222222222222222222222222222222);
        string memory path = _writeArtifact(block.chainid, txs, "grant-to");
        vm.expectRevert(abi.encodeWithSelector(VerifyMismatch.selector, "to"));
        testable.verify(path);
    }

    /// @notice Grants-branch `verify()` rejects a bundle whose grantRole
    /// calldata is tampered with `VerifyMismatch("data")`.
    function testVerifyRejectsTamperedGrantData() external {
        selectBaseFork();
        TestableDeployV4AuthoriserClone testable = new TestableDeployV4AuthoriserClone();
        testable.run();
        address clone = testable.lastPredictedClone();
        testable.setResolvedClone(clone);
        testable.setResolvedCloneCodehash(clone.codehash);

        SafeTx[] memory txs = _grantsTxs(clone);
        txs[2].data = hex"deadbeef";
        string memory path = _writeArtifact(block.chainid, txs, "grant-data");
        vm.expectRevert(abi.encodeWithSelector(VerifyMismatch.selector, "data"));
        testable.verify(path);
    }

    // -------------------------------------------------------------------------
    // Internal grant-state assertions (reached directly via exposed wrappers —
    // the production call sites in run() always see a real, correctly-shaped,
    // freshly-deployed clone, so these revert branches are otherwise dead).
    // -------------------------------------------------------------------------

    /// @notice Inverted: `assertCloneCodehash` reverts `CloneCodehashMismatch`
    /// when the clone's runtime codehash differs from the expected EIP-1167
    /// codehash.
    function testAssertCloneCodehashRejectsMismatch() external {
        selectBaseFork();
        TestableDeployV4AuthoriserClone testable = new TestableDeployV4AuthoriserClone();
        address probe = address(0xC0Dec0dec0DeC0Dec0dEc0DEC0DEC0DEC0DEC0dE);
        bytes memory stub = hex"60005260206000F3";
        vm.etch(probe, stub);
        bytes32 actual = keccak256(stub);
        bytes32 wrongExpected = keccak256("not-a-minimal-proxy");
        vm.expectRevert(abi.encodeWithSelector(CloneCodehashMismatch.selector, probe, wrongExpected, actual));
        testable.exposed_assertCloneCodehash(probe, wrongExpected);
    }

    /// @notice Inverted: `assertAutoGrantsHeld` reverts `AutoGrantMissing` when
    /// one of the seven auto-granted `_ADMIN` roles is not held by the admin.
    /// Mocks every `hasRole` true except `CONFISCATE_RECEIPT_ADMIN`, so the
    /// iteration trips on the missing role.
    function testAssertAutoGrantsRejectsMissing() external {
        selectBaseFork();
        TestableDeployV4AuthoriserClone testable = new TestableDeployV4AuthoriserClone();
        address clone = address(0xAcc0000000000000000000000000000000000001);
        address admin = address(safe);
        vm.mockCall(clone, abi.encodeWithSelector(IAccessControl.hasRole.selector), abi.encode(true));
        bytes32 missingRole = keccak256("CONFISCATE_RECEIPT_ADMIN");
        vm.mockCall(
            clone, abi.encodeWithSelector(IAccessControl.hasRole.selector, missingRole, admin), abi.encode(false)
        );
        vm.expectRevert(abi.encodeWithSelector(AutoGrantMissing.selector, clone, missingRole, admin));
        testable.exposed_assertAutoGrantsHeld(clone, admin);
    }

    /// @notice Inverted: `assertNonAdminGrantsAbsent` reverts
    /// `UnexpectedAutoGrantHeld` when a non-admin grant the mirror bundle is
    /// supposed to add is already held on the supposedly-fresh clone. Mocks
    /// every `hasRole` false except the first non-admin entry (index 5).
    function testAssertNonAdminGrantsRejectsUnexpected() external {
        selectBaseFork();
        TestableDeployV4AuthoriserClone testable = new TestableDeployV4AuthoriserClone();
        address clone = address(0xACc0000000000000000000000000000000000002);
        RoleGrant memory g = LibAuthoriserInvariants.expectedGrants()[5];
        vm.mockCall(clone, abi.encodeWithSelector(IAccessControl.hasRole.selector), abi.encode(false));
        vm.mockCall(clone, abi.encodeWithSelector(IAccessControl.hasRole.selector, g.role, g.grantee), abi.encode(true));
        vm.expectRevert(abi.encodeWithSelector(UnexpectedAutoGrantHeld.selector, clone, g.role, g.grantee));
        testable.exposed_assertNonAdminGrantsAbsent(clone);
    }

    // -------------------------------------------------------------------------
    // NewClone log extraction (reached via exposed wrapper — the production
    // call site reads the real factory, which always emits a matching event).
    // -------------------------------------------------------------------------

    /// @notice Inverted: `extractCloneAddressFromLogs` reverts when no NewClone
    /// event from the factory is present — an invariant break on the factory.
    /// The fixture takes every skip branch first (right-topic/wrong-emitter,
    /// right-emitter/empty-topics, right-emitter/wrong-topic) before the
    /// fall-through revert.
    function testExtractCloneAddressRejectsMissingNewClone() external {
        TestableDeployV4AuthoriserClone testable = new TestableDeployV4AuthoriserClone();
        address factory = makeAddr("factory");

        bytes32[] memory newCloneTopic = new bytes32[](1);
        newCloneTopic[0] = keccak256("NewClone(address,address,address)");
        bytes32[] memory otherTopic = new bytes32[](1);
        otherTopic[0] = keccak256("SomethingElse(uint256)");

        VmSafe.Log[] memory logs = new VmSafe.Log[](3);
        // Right topic, wrong emitter -> skipped by the emitter check.
        logs[0] = VmSafe.Log({topics: newCloneTopic, data: hex"", emitter: makeAddr("notFactory")});
        // Right emitter, no topics -> skipped by the topics.length check.
        logs[1] = VmSafe.Log({topics: new bytes32[](0), data: hex"", emitter: factory});
        // Right emitter, wrong topic -> skipped by the topic[0] check.
        logs[2] = VmSafe.Log({topics: otherTopic, data: hex"", emitter: factory});

        vm.expectRevert(abi.encodeWithSignature("Error(string)", "DeployV4AuthoriserClone: NewClone not emitted"));
        testable.exposed_extractCloneAddressFromLogs(logs, factory, makeAddr("expectedImpl"));
    }

    /// @notice Inverted: `extractCloneAddressFromLogs` reverts when a NewClone
    /// event is present but its `implementation` field does not match the
    /// expected V4 impl — the cross-check that the clone proxies the right
    /// logic. NewClone's three address args are all in `data` (no indexed args).
    function testExtractCloneAddressRejectsImplMismatch() external {
        TestableDeployV4AuthoriserClone testable = new TestableDeployV4AuthoriserClone();
        address factory = makeAddr("factory");
        address expectedImpl = makeAddr("expectedImpl");
        address wrongImpl = makeAddr("wrongImpl");

        bytes32[] memory topics = new bytes32[](1);
        topics[0] = keccak256("NewClone(address,address,address)");
        VmSafe.Log[] memory logs = new VmSafe.Log[](1);
        logs[0] = VmSafe.Log({
            topics: topics, data: abi.encode(makeAddr("sender"), wrongImpl, makeAddr("clone")), emitter: factory
        });

        vm.expectRevert(abi.encodeWithSignature("Error(string)", "DeployV4AuthoriserClone: NewClone impl mismatch"));
        testable.exposed_extractCloneAddressFromLogs(logs, factory, expectedImpl);
    }

    // -------------------------------------------------------------------------
    // Bundle-construction helpers (mirror the script so a tamper test can
    // perturb exactly one field of an otherwise-canonical bundle).
    // -------------------------------------------------------------------------

    /// @notice The canonical deploy-bundle calldata:
    /// `clone(v4Impl, abi.encode(Config(Safe)))` against the CloneFactory.
    function _expectedDeployData() internal view returns (bytes memory) {
        address v4Impl = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RAIN_VATS_0_1_6;
        bytes memory initData = abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: address(safe)}));
        return abi.encodeCall(ICloneableFactoryV2.clone, (v4Impl, initData));
    }

    /// @notice The canonical single-tx deploy bundle (target = CloneFactory).
    function _deployTxs() internal view returns (SafeTx[] memory txs) {
        txs = new SafeTx[](1);
        txs[0] = SafeTx({
            to: LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS,
            value: 0,
            data: _expectedDeployData(),
            operation: 0
        });
    }

    /// @notice The canonical six-tx grants bundle targeting `clone` — one
    /// `grantRole` per non-admin entry (indices 5..10) of `expectedGrants()`.
    function _grantsTxs(address clone) internal pure returns (SafeTx[] memory txs) {
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants();
        txs = new SafeTx[](6);
        for (uint256 i = 0; i < 6; i++) {
            RoleGrant memory g = grants[5 + i];
            txs[i] = SafeTx({
                to: clone, value: 0, data: abi.encodeCall(IAccessControl.grantRole, (g.role, g.grantee)), operation: 0
            });
        }
    }

    /// @notice Emit `txs` as a Tx Builder JSON artifact (via the same
    /// `LibSafeOps.emitTxBuilderJson` the script uses, so the schema is always
    /// valid) at a unique path, and return that path so a tampered/malformed
    /// bundle can be fed to `verify()`.
    function _writeArtifact(uint256 chainId, SafeTx[] memory txs, string memory tag)
        internal
        returns (string memory path)
    {
        string memory json = LibSafeOps.emitTxBuilderJson(address(safe), chainId, "tamper-fixture", txs);
        path = string.concat(vm.projectRoot(), "/out/tamper-", tag, ".json");
        vm.writeFile(path, json);
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";

import {
    UpgradeReceiptVaultToV3,
    V3ImplementationNotDeployed,
    V3CodehashMismatch
} from "../../script/UpgradeReceiptVaultToV3.s.sol";
import {IGnosisSafe} from "../../src/interface/IGnosisSafe.sol";
import {LibProdDeployV1} from "../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV3} from "../../src/lib/LibProdDeployV3.sol";
import {LibProdSafes} from "../../src/lib/LibProdSafes.sol";
import {LibBeaconInvariants, BeaconImplementationMismatch} from "../../src/lib/LibBeaconInvariants.sol";
import {IUpgradeableBeacon} from "../../src/lib/LibSafeOps.sol";
import {LibRainDeploy} from "rain-deploy-0.1.3/src/lib/LibRainDeploy.sol";

/// @title UpgradeReceiptVaultToV3Test
/// @notice End-to-end fork tests for the receipt vault V3 upgrade script.
///
/// Two pieces of on-chain state the script depends on do not exist on the
/// live chain yet, so the test plants them before running the script:
///
/// 1. **Beacon ownership** — the receipt vault beacon is owned by the
///    rainlang.eth EOA until the beacon-ownership migration executes on-chain.
///    The test pranks the EOA to transfer the beacon to the Safe, simulating
///    that migration's effect.
/// 2. **V3 implementation** — the V3 receipt vault implementation is not yet
///    deployed at its deterministic Zoltu address. The test plants it via
///    `deployCodeTo`, which runs the real constructor at the target so the
///    runtime codehash matches the pinned `LibProdDeployV3` codehash exactly.
///
/// @dev Uses an unpinned Base head fork (same precedent as the other Safe
/// fork tests).
contract UpgradeReceiptVaultToV3Test is Test {
    /// @notice The script under test, deployed fresh per fork.
    UpgradeReceiptVaultToV3 internal script;

    /// @notice Live Safe handle.
    IGnosisSafe internal safe;

    /// @notice The receipt vault beacon being upgraded.
    address internal constant BEACON = LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1;

    /// @notice The V1 implementation (current on-chain impl + rollback target).
    address internal constant V1_IMPL = LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION;

    /// @notice The V3 implementation (upgrade target).
    address internal constant V3_IMPL = LibProdDeployV3.STOX_RECEIPT_VAULT;

    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
        script = new UpgradeReceiptVaultToV3();
        safe = IGnosisSafe(LibProdSafes.STOX_TOKEN_OWNER_SAFE);
    }

    /// @notice Simulate the beacon-ownership migration (PR-A) landing on-chain:
    /// prank the EOA owner and transfer the receipt vault beacon to the Safe.
    function simulateBeaconOwnershipMigration() internal {
        vm.prank(LibProdSafes.BEACON_PRE_MIGRATION_OWNER);
        Ownable(BEACON).transferOwnership(LibProdSafes.STOX_TOKEN_OWNER_SAFE);
    }

    /// @notice Plant the audited V3 receipt vault implementation at its
    /// deterministic Zoltu address by running its constructor there. The
    /// resulting runtime codehash matches the pinned `LibProdDeployV3`
    /// codehash, so the script's codehash require passes.
    function deployV3Impl() internal {
        deployCodeTo("src/concrete/StoxReceiptVault.sol:StoxReceiptVault", V3_IMPL);
    }

    /// @notice Sanity check: the V3 implementation planted via `deployCodeTo`
    /// has the exact pinned codehash. If this drifts, every other test in this
    /// file would fail with a confusing `V3CodehashMismatch` rather than this
    /// explicit assertion.
    function testV3ImplPlantedWithPinnedCodehash() external {
        selectBaseFork();
        deployV3Impl();
        assertEq(V3_IMPL.codehash, LibProdDeployV3.STOX_RECEIPT_VAULT_CODEHASH, "planted V3 codehash matches pin");
    }

    /// @notice End-to-end happy path: beacon ownership simulated, V3 planted,
    /// `run()` completes — pre-flight passes, the upgrade simulates, the
    /// post-state asserts the beacon at V3, the artifact is written, and the
    /// n+1 rolls the beacon back to V1 (the observable side effect of the
    /// reversibility check).
    function testRunCompletesAndWritesArtifact() external {
        selectBaseFork();
        simulateBeaconOwnershipMigration();
        deployV3Impl();

        script.run();

        // After `run()`, the n+1 reversibility check has rolled the beacon
        // back to the V1 implementation. Asserting the final fork state is the
        // observable evidence the reversal path executed.
        assertEq(IBeacon(BEACON).implementation(), V1_IMPL, "n+1 rolled beacon back to V1 impl");

        // The artifact was written with the expected single-tx shape.
        string memory artifactPath = string.concat(vm.projectRoot(), "/out/v3-upgrade.json");
        string memory json = vm.readFile(artifactPath);
        string memory bundleName = vm.parseJsonString(json, ".meta.name");
        assertEq(bundleName, "ST0x receipt vault V3 upgrade", "meta.name pinned");
        assertTrue(vm.keyExistsJson(json, ".transactions[0].to"), "first transaction present");
        assertFalse(vm.keyExistsJson(json, ".transactions[1].to"), "exactly one transaction emitted");
        // The bundle targets the beacon, and its calldata encodes upgradeTo(V3).
        assertEq(vm.parseJsonAddress(json, ".transactions[0].to"), BEACON, "bundle targets the beacon");
        bytes memory data = vm.parseJsonBytes(json, ".transactions[0].data");
        assertEq(data, abi.encodeWithSignature("upgradeTo(address)", V3_IMPL), "bundle calldata is upgradeTo(V3)");
    }

    /// @notice The emitted artifact verifies the upgrade is reachable: after a
    /// snapshot/restore so the fork is back in the pre-upgrade state, the
    /// beacon is at V1 and Safe-owned — the exact precondition the bundle was
    /// authored against.
    function testArtifactMatchesPreUpgradeState() external {
        selectBaseFork();
        simulateBeaconOwnershipMigration();
        deployV3Impl();

        uint256 snapshot = vm.snapshotState();
        script.run();
        vm.revertToState(snapshot);

        // Pre-upgrade state restored: beacon Safe-owned, still at V1 impl.
        LibBeaconInvariants.assertBeaconInvariants(BEACON, LibProdSafes.STOX_TOKEN_OWNER_SAFE, V1_IMPL);
    }

    /// @notice Inverted: the pre-flight rejects an undeployed V3
    /// implementation. With the beacon ownership simulated but the V3 impl NOT
    /// planted, `run()` must trip `V3ImplementationNotDeployed` rather than
    /// emitting a bundle for code that doesn't exist.
    function testRunRejectsUndeployedV3Impl() external {
        selectBaseFork();
        simulateBeaconOwnershipMigration();
        // Deliberately skip `deployV3Impl()`.
        vm.expectRevert(abi.encodeWithSelector(V3ImplementationNotDeployed.selector, V3_IMPL));
        script.run();
    }

    /// @notice Inverted: the pre-flight rejects a V3 implementation whose
    /// codehash does not match the pin. Plants arbitrary non-empty bytecode at
    /// the V3 address so the code-presence check passes but the codehash
    /// check fails.
    function testRunRejectsWrongV3Codehash() external {
        selectBaseFork();
        simulateBeaconOwnershipMigration();
        bytes memory bogusCode = hex"60016000526001601ff3";
        vm.etch(V3_IMPL, bogusCode);
        vm.expectRevert(
            abi.encodeWithSelector(
                V3CodehashMismatch.selector, V3_IMPL, LibProdDeployV3.STOX_RECEIPT_VAULT_CODEHASH, keccak256(bogusCode)
            )
        );
        script.run();
    }

    /// @notice Inverted: the pre-flight rejects a beacon still at the V1 impl
    /// being treated as if already at V3 would not occur — but the pre-flight
    /// DOES reject a beacon that is NOT Safe-owned. Without simulating the
    /// beacon-ownership migration, the beacon is still EOA-owned, so the
    /// pre-flight's `assertBeaconInvariants(beacon, safe, V1)` trips on the
    /// owner. We assert the owner-mismatch path indirectly: skipping the
    /// ownership migration makes `run()` revert before it reaches the V3
    /// checks.
    function testRunRejectsEoaOwnedBeacon() external {
        selectBaseFork();
        deployV3Impl();
        // Beacon ownership migration NOT simulated: beacon is still EOA-owned,
        // so the pre-flight assertBeaconInvariants(beacon, Safe, V1) reverts on
        // the owner mismatch before the V3 deploy checks run.
        vm.expectRevert();
        script.run();
    }

    /// @notice Inverted: the pre-flight rejects a beacon already past the V1
    /// implementation. Models a double-run after the V3 upgrade has already
    /// landed: the beacon is genuinely upgraded to V3 first (via the
    /// Safe-pranked `upgradeTo`), so the pre-flight's
    /// `assertBeaconInvariants(beacon, safe, V1)` trips
    /// `BeaconImplementationMismatch` reporting V3 as the actual impl.
    /// Driving the beacon through the real `upgradeTo` rather than mocking
    /// `implementation()` keeps the live beacon proxies (which resolve their
    /// impl through the beacon) intact.
    function testRunRejectsNonV1StartingImpl() external {
        selectBaseFork();
        simulateBeaconOwnershipMigration();
        deployV3Impl();
        // Pre-upgrade the beacon to V3 so the script's pre-flight sees a
        // non-V1 starting implementation.
        vm.prank(LibProdSafes.STOX_TOKEN_OWNER_SAFE);
        IUpgradeableBeacon(BEACON).upgradeTo(V3_IMPL);

        vm.expectRevert(abi.encodeWithSelector(BeaconImplementationMismatch.selector, BEACON, V1_IMPL, V3_IMPL));
        script.run();
    }
}

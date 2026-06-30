// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";

import {IGnosisSafe} from "../../src/interface/IGnosisSafe.sol";
import {LibProdDeployV1} from "../../src/lib/LibProdDeployV1.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {BeaconOwnerMismatch} from "../../src/lib/LibBeaconInvariants.sol";
import {MigrateBeaconOwnersHarness} from "./MigrateBeaconOwnersHarness.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

/// @title MigrateBeaconOwnersTest
/// @notice End-to-end fork tests for the beacon-ownership migration. Because
/// the migration broadcasts from the rainlang.eth EOA (which owns the
/// beacons), the test simulates the broadcast's effect by pranking the EOA
/// to perform the `transferOwnership` calls, exercising the same pre-flight,
/// post-state, and n+1 reversibility steps the script runs.
/// @dev Uses an unpinned Base head fork (same precedent as
/// `MigrateMultisigThresholdTest`): any drift in the live beacon state
/// surfaces on the next CI run rather than being frozen against a stale
/// snapshot.
contract MigrateBeaconOwnersTest is Test {
    /// @notice Live Safe handle, reset per fork.
    IGnosisSafe internal safe;

    /// @notice The harness deployed fresh per fork.
    MigrateBeaconOwnersHarness internal harness;

    /// @notice The three beacons under migration, in the script's order.
    address[3] internal beaconList = [
        LibProdDeployV1.STOX_RECEIPT_BEACON_V1,
        LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1,
        LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1
    ];

    /// @notice Each beacon's pinned current implementation, index-aligned with
    /// `beaconList`.
    address[3] internal implList = [
        LibProdDeployV1.STOX_RECEIPT_IMPLEMENTATION,
        LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION,
        LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION
    ];

    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
        safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        harness = new MigrateBeaconOwnersHarness();
    }

    /// @notice Simulate the migration's on-chain effect: prank the EOA owner
    /// and transfer each beacon to the Safe. Models exactly what
    /// `MigrateBeaconOwners.run()`'s broadcast block does.
    function simulateTransfers() internal {
        for (uint256 i = 0; i < beaconList.length; i++) {
            vm.prank(LibProdDeployV1.BEACON_INITIAL_OWNER);
            Ownable(beaconList[i]).transferOwnership(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        }
    }

    /// @notice Pre-flight passes against the live EOA-owned state for all
    /// three beacons. This is the gate `run()` runs before broadcasting.
    function testPreflightPassesAgainstEoaOwnedState() external {
        selectBaseFork();
        for (uint256 i = 0; i < beaconList.length; i++) {
            // No revert == invariant holds.
            harness.callAssertBeaconInvariants(beaconList[i], LibProdDeployV1.BEACON_INITIAL_OWNER, implList[i]);
        }
    }

    /// @notice Full migration walk: pre-flight (EOA) passes, transfers
    /// applied, post-state (Safe) passes, n+1 reversibility passes for every
    /// beacon. This is the happy-path mirror of `MigrateBeaconOwners.run()`.
    function testFullMigrationWalk() external {
        selectBaseFork();

        // Pre-flight: every beacon EOA-owned.
        for (uint256 i = 0; i < beaconList.length; i++) {
            harness.callAssertBeaconInvariants(beaconList[i], LibProdDeployV1.BEACON_INITIAL_OWNER, implList[i]);
        }

        // Simulate the broadcast effect.
        simulateTransfers();

        // Post-state: every beacon now Safe-owned, implementations unchanged.
        for (uint256 i = 0; i < beaconList.length; i++) {
            harness.callAssertBeaconInvariants(beaconList[i], LibSafeInvariants.STOX_TOKEN_OWNER_SAFE, implList[i]);
            assertEq(Ownable(beaconList[i]).owner(), LibSafeInvariants.STOX_TOKEN_OWNER_SAFE, "beacon now Safe-owned");
            assertEq(IBeacon(beaconList[i]).implementation(), implList[i], "implementation unchanged by transfer");
        }

        // n+1 reversibility: the Safe can act on each beacon via an idempotent
        // upgradeTo routed through execTransaction. The post-condition inside
        // the helper asserts the implementation is preserved.
        for (uint256 i = 0; i < beaconList.length; i++) {
            harness.callSimulateBeaconNPlus1(
                safe, beaconList[i], implList[i], LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD
            );
            // After the idempotent n+1, the beacon still points at the same
            // implementation and is still Safe-owned.
            assertEq(IBeacon(beaconList[i]).implementation(), implList[i], "implementation preserved through n+1");
            assertEq(
                Ownable(beaconList[i]).owner(), LibSafeInvariants.STOX_TOKEN_OWNER_SAFE, "still Safe-owned after n+1"
            );
        }
    }

    /// @notice Inverted: the pre-flight rejects a wrong expected owner. The
    /// live beacon is EOA-owned; asserting it should be Safe-owned (before the
    /// transfer) trips `BeaconOwnerMismatch` with the actual EOA owner. This
    /// is the property that makes the post-state assertion meaningful — it
    /// would catch a transfer that silently failed.
    function testInvertedWrongExpectedOwnerReverts() external {
        selectBaseFork();
        address beacon = beaconList[0];
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconOwnerMismatch.selector,
                beacon,
                LibSafeInvariants.STOX_TOKEN_OWNER_SAFE,
                LibProdDeployV1.BEACON_INITIAL_OWNER
            )
        );
        harness.callAssertBeaconInvariants(beacon, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE, implList[0]);
    }

    /// @notice Inverted: after the transfers land, asserting the OLD EOA owner
    /// trips `BeaconOwnerMismatch` reporting the Safe as the actual owner.
    /// Confirms the post-state assertion is sensitive to the ownership flip in
    /// both directions.
    function testInvertedStaleEoaOwnerRevertsPostTransfer() external {
        selectBaseFork();
        simulateTransfers();
        address beacon = beaconList[0];
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconOwnerMismatch.selector,
                beacon,
                LibProdDeployV1.BEACON_INITIAL_OWNER,
                LibSafeInvariants.STOX_TOKEN_OWNER_SAFE
            )
        );
        harness.callAssertBeaconInvariants(beacon, LibProdDeployV1.BEACON_INITIAL_OWNER, implList[0]);
    }
}

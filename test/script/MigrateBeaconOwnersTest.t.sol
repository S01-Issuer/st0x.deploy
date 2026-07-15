// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";

import {IGnosisSafe} from "../../src/interface/IGnosisSafe.sol";
import {LibProdDeployV1} from "../../src/lib/LibProdDeployV1.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibBeaconInvariants, BeaconOwnerMismatch} from "../../src/lib/LibBeaconInvariants.sol";
import {MigrateBeaconOwnersHarness} from "./MigrateBeaconOwnersHarness.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

/// @title MigrateBeaconOwnersTest
/// @notice End-to-end fork tests for the beacon-ownership migration
/// (EXECUTED on Base, 2026-07 — every V1 beacon is now Safe-owned live).
/// The migration walk is still exercised in full: the pre-migration
/// EOA-owned state is reconstructed deterministically via `vm.store` on the
/// beacons' OZ `Ownable` owner slot (slot 0), so the coverage no longer
/// depends on the live chain being in the pre-execution state. The live
/// post-state (Safe-owned, real transfers) is asserted by
/// `testLivePostStateSafeOwned` and by the `BeaconOwnerMigrationPinTest`
/// migration-window cron invariant.
/// @dev Uses an unpinned Base head fork (same precedent as
/// `MigrateMultisigThresholdTest`): any drift in the live beacon state
/// surfaces on the next CI run rather than being frozen against a stale
/// snapshot.
contract MigrateBeaconOwnersTest is Test {
    /// @notice OZ `Ownable` stores `_owner` in slot 0 on the
    /// `UpgradeableBeacon`.
    bytes32 internal constant OWNABLE_OWNER_SLOT = bytes32(0);

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

    /// @notice Reconstruct the pre-migration state on the fork: write the
    /// rainlang.eth EOA back into each beacon's `Ownable` owner slot. The
    /// migration executed on Base in 2026-07, so the live fork starts
    /// Safe-owned; the walk tests rewind ownership deterministically
    /// instead of depending on live pre-execution state.
    function rewindToEoaOwned() internal {
        for (uint256 i = 0; i < beaconList.length; i++) {
            vm.store(beaconList[i], OWNABLE_OWNER_SLOT, bytes32(uint256(uint160(LibProdDeployV1.BEACON_INITIAL_OWNER))));
            assertEq(Ownable(beaconList[i]).owner(), LibProdDeployV1.BEACON_INITIAL_OWNER, "rewind failed: owner slot");
        }
    }

    /// @notice Simulate the migration's on-chain effect: prank the EOA owner
    /// and transfer each beacon to the Safe. Models exactly what
    /// `MigrateBeaconOwners.run()`'s broadcast block did.
    function simulateTransfers() internal {
        for (uint256 i = 0; i < beaconList.length; i++) {
            vm.prank(LibProdDeployV1.BEACON_INITIAL_OWNER);
            Ownable(beaconList[i]).transferOwnership(LibBeaconInvariants.PROD_BEACON_OWNER);
        }
    }

    /// @notice LIVE post-state: every beacon on Base head is Safe-owned with
    /// its implementation unchanged — the executed migration's outcome,
    /// asserted against the real chain with no state reconstruction.
    function testLivePostStateSafeOwned() external {
        selectBaseFork();
        for (uint256 i = 0; i < beaconList.length; i++) {
            harness.callAssertBeaconInvariants(beaconList[i], LibBeaconInvariants.PROD_BEACON_OWNER, implList[i]);
            assertEq(Ownable(beaconList[i]).owner(), LibBeaconInvariants.PROD_BEACON_OWNER, "beacon Safe-owned");
            assertEq(IBeacon(beaconList[i]).implementation(), implList[i], "implementation unchanged by migration");
        }
    }

    /// @notice Pre-flight passes against the (reconstructed) EOA-owned state
    /// for all three beacons. This is the gate `run()` ran before
    /// broadcasting.
    function testPreflightPassesAgainstEoaOwnedState() external {
        selectBaseFork();
        rewindToEoaOwned();
        for (uint256 i = 0; i < beaconList.length; i++) {
            // No revert == invariant holds.
            harness.callAssertBeaconInvariants(beaconList[i], LibProdDeployV1.BEACON_INITIAL_OWNER, implList[i]);
        }
    }

    /// @notice Full migration walk: pre-flight (EOA) passes, transfers
    /// applied, post-state (Safe) passes, n+1 reversibility passes for every
    /// beacon. This is the happy-path mirror of `MigrateBeaconOwners.run()`,
    /// replayed from the reconstructed pre-state.
    function testFullMigrationWalk() external {
        selectBaseFork();
        rewindToEoaOwned();

        // Pre-flight: every beacon EOA-owned.
        for (uint256 i = 0; i < beaconList.length; i++) {
            harness.callAssertBeaconInvariants(beaconList[i], LibProdDeployV1.BEACON_INITIAL_OWNER, implList[i]);
        }

        // Simulate the broadcast effect.
        simulateTransfers();

        // Post-state: every beacon now Safe-owned, implementations unchanged.
        for (uint256 i = 0; i < beaconList.length; i++) {
            harness.callAssertBeaconInvariants(beaconList[i], LibBeaconInvariants.PROD_BEACON_OWNER, implList[i]);
            assertEq(Ownable(beaconList[i]).owner(), LibBeaconInvariants.PROD_BEACON_OWNER, "beacon now Safe-owned");
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
                Ownable(beaconList[i]).owner(), LibBeaconInvariants.PROD_BEACON_OWNER, "still Safe-owned after n+1"
            );
        }
    }

    /// @notice Inverted: the pre-flight rejects a wrong expected owner. From
    /// the reconstructed EOA-owned state, asserting the beacon should be
    /// Safe-owned trips `BeaconOwnerMismatch` with the actual EOA owner.
    /// This is the property that makes the post-state assertion meaningful —
    /// it would catch a transfer that silently failed.
    function testInvertedWrongExpectedOwnerReverts() external {
        selectBaseFork();
        rewindToEoaOwned();
        address beacon = beaconList[0];
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconOwnerMismatch.selector,
                beacon,
                LibBeaconInvariants.PROD_BEACON_OWNER,
                LibProdDeployV1.BEACON_INITIAL_OWNER
            )
        );
        harness.callAssertBeaconInvariants(beacon, LibBeaconInvariants.PROD_BEACON_OWNER, implList[0]);
    }

    /// @notice Inverted: with the migration landed (live state), asserting
    /// the OLD EOA owner trips `BeaconOwnerMismatch` reporting the Safe as
    /// the actual owner. Confirms the post-state assertion is sensitive to
    /// the ownership flip in both directions — and doubles as the dispatch
    /// gate: a re-run of the script's pre-flight now reverts here.
    function testInvertedStaleEoaOwnerRevertsPostTransfer() external {
        selectBaseFork();
        address beacon = beaconList[0];
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconOwnerMismatch.selector,
                beacon,
                LibProdDeployV1.BEACON_INITIAL_OWNER,
                LibBeaconInvariants.PROD_BEACON_OWNER
            )
        );
        harness.callAssertBeaconInvariants(beacon, LibProdDeployV1.BEACON_INITIAL_OWNER, implList[0]);
    }
}

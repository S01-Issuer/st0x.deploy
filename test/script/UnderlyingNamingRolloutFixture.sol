// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.30/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.30/src/lib/LibSafeTxBuilderJson.sol";
import {SafeBundleScript} from "rain-deploy-0.1.30/src/abstract/SafeBundleScript.sol";

import {ExecuteUnderlyingNaming} from "../../script/20261021-execute-underlying-naming.s.sol";
import {
    scheduleUnderlyingNamingBeaconsDeclaration
} from "../../script/20261021-schedule-underlying-naming-beacons.s.sol";
import {ScheduleUnderlyingNamingBeaconsHarness} from "./ScheduleUnderlyingNamingBeaconsHarness.sol";
import {ScheduleUnderlyingNamingRenameHarness} from "./ScheduleUnderlyingNamingRenameHarness.sol";
import {BackfillMigrationRegistryV5Harness} from "./BackfillMigrationRegistryV5Harness.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {LibTestBeaconInitialOwnerBind} from "../lib/LibTestBeaconInitialOwnerBind.sol";
import {HandSafeOwnedBaseVaultsToTimelockHarness} from "./HandSafeOwnedBaseVaultsToTimelockHarness.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibUnderlyingNamingRollout} from "../../src/lib/LibUnderlyingNamingRollout.sol";

/// @title UnderlyingNamingRolloutFixture
/// @notice Brings a forked deployment network through the underlying-naming
/// rollout's steps as the Safe and the executing key would.
abstract contract UnderlyingNamingRolloutFixture is Test {
    /// @notice Lands, as the Safe would, the root-line records before the
    /// beacon schedule: the V5 backfill, the beacon-initial-owner bind, the
    /// orchestrator admin move, then the Safe-owned Base vault handover.
    function advanceRootLineToBeaconSchedule() internal {
        Safe safe = Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
        BackfillMigrationRegistryV5Harness backfill = new BackfillMigrationRegistryV5Harness("underlying-naming");
        backfill.callPreflight();
        LibSafeFork.executeBundle(vm, safe, backfill.callAuthorBundle());
        LibTestBeaconInitialOwnerBind.execute(vm, address(safe), "underlying-naming");
        OrchestratorAdminToTimelockHarness adminMove = new OrchestratorAdminToTimelockHarness("underlying-naming");
        adminMove.callPreflight();
        LibSafeFork.executeBundle(vm, safe, adminMove.callAuthorBundle());
        HandSafeOwnedBaseVaultsToTimelockHarness handover =
            new HandSafeOwnedBaseVaultsToTimelockHarness("underlying-naming");
        handover.callPreflight();
        LibSafeFork.executeBundle(vm, safe, handover.callAuthorBundle());
        assertEq(LibStoxMigrations.head(), scheduleUnderlyingNamingBeaconsDeclaration().onto, "line at the beacon onto");
    }

    /// @notice `run()` authors and proves the bundle on a snapshot, `verify`
    /// holds the artifact to the live re-derivation, and the artifact is then
    /// executed by the owners as the Safe UI would.
    function authorVerifyExecute(address script, string memory artifactPath) internal {
        uint256 preRun = vm.snapshotState();
        SafeBundleScript(script).run();
        vm.revertToState(preRun);
        SafeBundleScript(script).verify(artifactPath);
        (, address artifactSafe, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, vm.readFile(artifactPath));
        assertEq(artifactSafe, LibSafeInvariants.safeForChainId(block.chainid), "artifact Safe");
        uint256 gasBefore = gasleft();
        LibSafeFork.executeBundle(vm, Safe(payable(artifactSafe)), txs);
        console2.log("Safe bundle execution gas (upper bound, includes signing):", gasBefore - gasleft());
    }

    /// @notice Executes `txs[0 .. count)` from the chain's Safe.
    function executePrefix(SafeTx[] memory txs, uint256 count) internal {
        SafeTx[] memory prefix = new SafeTx[](count);
        for (uint256 txIndex = 0; txIndex < count; txIndex++) {
            prefix[txIndex] = txs[txIndex];
        }
        LibSafeFork.executeBundle(vm, Safe(payable(LibSafeInvariants.safeForChainId(block.chainid))), prefix);
    }

    /// @notice Plants the three implementations at their pinned addresses,
    /// running their constructors there (the facet's `_SELF`).
    function plantImplementations() internal {
        deployCodeTo(
            "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet", LibUnderlyingNamingRollout.FACET
        );
        deployCodeTo(
            "src/concrete/StoxReceiptVault.sol:StoxReceiptVault",
            LibUnderlyingNamingRollout.RECEIPT_VAULT_IMPLEMENTATION
        );
        deployCodeTo(
            "src/concrete/StoxWrappedTokenVault.sol:StoxWrappedTokenVault",
            LibUnderlyingNamingRollout.WRAPPED_TOKEN_VAULT_IMPLEMENTATION
        );
    }

    /// @notice Brings the forked chain to the point where the rename can be
    /// authored: the beacon batch registered and every vault owned by the
    /// timelock.
    function prepareRename() internal {
        advanceRootLineToBeaconSchedule();
        landBeaconSchedule();
    }

    /// @notice From the line at the beacon onto: plants the implementations
    /// and lands the beacon bundle.
    function landBeaconSchedule() internal {
        plantImplementations();
        ScheduleUnderlyingNamingBeaconsHarness beacons = new ScheduleUnderlyingNamingBeaconsHarness("prepare");
        LibSafeFork.executeBundle(
            vm, Safe(payable(LibSafeInvariants.safeForChainId(block.chainid))), beacons.callAuthorBundle()
        );
    }

    /// @notice Runs the rollout on the fork through to the executed rename
    /// batch.
    function executeRollout(ScheduleUnderlyingNamingRenameHarness rename) internal {
        prepareRename();
        LibSafeFork.executeBundle(
            vm, Safe(payable(LibSafeInvariants.safeForChainId(block.chainid))), rename.callAuthorBundle()
        );
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        ExecuteUnderlyingNaming executor = new ExecuteUnderlyingNaming();
        executor.execute();
        executor.execute();
    }
}

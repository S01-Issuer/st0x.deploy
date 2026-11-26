// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {SafeTx} from "rain-deploy-0.1.38/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.38/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.38/src/lib/LibSafeTxBuilderJson.sol";
import {SafeBundleScript} from "rain-deploy-0.1.38/src/abstract/SafeBundleScript.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";

import {
    ExecuteUnderlyingNaming,
    NoUnderlyingNamingOperationReady,
    UnderlyingNamingNotExecuted
} from "../../script/20261021-execute-underlying-naming.s.sol";
import {
    ImplementationNotDeployed,
    scheduleUnderlyingNamingBeaconsDeclaration
} from "../../script/20261021-schedule-underlying-naming-beacons.s.sol";
import {ExecuteUnderlyingNamingHarness} from "./ExecuteUnderlyingNamingHarness.sol";
import {ScheduleUnderlyingNamingBeaconsHarness} from "./ScheduleUnderlyingNamingBeaconsHarness.sol";
import {ScheduleUnderlyingNamingRenameHarness} from "./ScheduleUnderlyingNamingRenameHarness.sol";
import {ICorporateActionsV1} from "../../src/interface/ICorporateActionsV1.sol";
import {BackfillMigrationRegistryV5Harness} from "./BackfillMigrationRegistryV5Harness.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {LibTestBeaconInitialOwnerBind} from "../lib/LibTestBeaconInitialOwnerBind.sol";
import {HandSafeOwnedBaseVaultsToTimelockHarness} from "./HandSafeOwnedBaseVaultsToTimelockHarness.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations, UnexpectedMigrationLine} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibUnderlyingNamingRollout} from "../../src/lib/LibUnderlyingNamingRollout.sol";

/// @title UnderlyingNamingRolloutFixture
/// @notice Brings a forked deployment network through the underlying-naming
/// rollout's steps as the Safe and the executing key would.
abstract contract UnderlyingNamingRolloutFixture is Test {
    /// @notice Lands, as the Safe would, the root-line records before the
    /// beacon schedule: the V5 backfill, the 0G token creation record, the
    /// beacon-initial-owner bind, the orchestrator admin move, then the
    /// Safe-owned Base vault handover.
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

    /// @notice From the line at the beacon onto: authors, verifies and
    /// executes both batches on `network` as the Safe and a roleless key
    /// would, checking each step's refusals and the result.
    function assertRolloutFromTheBeaconOnto(string memory network) internal {
        uint256 chainId = block.chainid;
        address timelock = LibTimelockInvariants.timelockForChainId(chainId);
        TimelockController controller = TimelockController(payable(timelock));
        bytes32 beaconId = LibUnderlyingNamingRollout.beaconOperationId(timelock, chainId);
        bytes32 renameId = LibUnderlyingNamingRollout.renameOperationId(timelock, chainId);
        ScheduleUnderlyingNamingBeaconsHarness beacons = new ScheduleUnderlyingNamingBeaconsHarness(network);
        ScheduleUnderlyingNamingRenameHarness rename = new ScheduleUnderlyingNamingRenameHarness(network);
        ExecuteUnderlyingNamingHarness execution = new ExecuteUnderlyingNamingHarness(network);

        assertBeaconBatchExact(chainId, network);
        // Before step 1 the beacon batch refuses, and the rename refuses the
        // line until the beacon record lands.
        vm.expectPartialRevert(ImplementationNotDeployed.selector);
        beacons.callPreflight();
        vm.expectRevert(
            abi.encodeWithSelector(
                UnexpectedMigrationLine.selector, LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK
            )
        );
        rename.callPreflight();
        plantImplementations();
        authorVerifyExecute(address(beacons), beacons.callArtifactPath());
        assertEq(
            LibStoxMigrations.head(),
            LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS,
            string.concat(network, ": beacon record")
        );
        authorVerifyExecute(address(rename), rename.callArtifactPath());
        assertEq(
            LibStoxMigrations.head(),
            LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME,
            string.concat(network, ": rename record")
        );

        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        execution.execute();
        assertEq(
            IBeacon(LibUnderlyingNamingRollout.receiptVaultBeacon(chainId)).implementation(),
            LibUnderlyingNamingRollout.RECEIPT_VAULT_IMPLEMENTATION,
            string.concat(network, ": vault beacon upgraded")
        );
        vm.expectRevert(abi.encodeWithSelector(UnderlyingNamingNotExecuted.selector, renameId));
        execution.callPreflight();
        logRenameExecutionGas(controller, chainId, beaconId);
        execution.execute();
        assertTrue(controller.isOperationDone(renameId), string.concat(network, ": rename executed"));
        rename.callAssertRenamed(chainId);

        vm.expectPartialRevert(NoUnderlyingNamingOperationReady.selector);
        execution.execute();

        authorVerifyExecute(address(execution), execution.callArtifactPath());
        assertEq(
            LibStoxMigrations.head(),
            LibStoxMigrations.EXECUTE_UNDERLYING_NAMING,
            string.concat(network, ": line at the execution")
        );
    }

    /// @notice The beacon batch is exactly: the wrapper beacon upgrade, the
    /// vault beacon upgrade, then the facet probe on the first production
    /// vault.
    function assertBeaconBatchExact(uint256 chainId, string memory network) internal view {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            LibUnderlyingNamingRollout.beaconBatch(chainId);
        assertEq(targets.length, 3, string.concat(network, ": beacon batch length"));
        assertEq(
            targets[0],
            LibUnderlyingNamingRollout.wrappedTokenVaultBeacon(chainId),
            string.concat(network, ": wrapper beacon")
        );
        assertEq(
            payloads[0],
            abi.encodeCall(
                UpgradeableBeacon.upgradeTo, (LibUnderlyingNamingRollout.WRAPPED_TOKEN_VAULT_IMPLEMENTATION)
            ),
            string.concat(network, ": beacon upgrade 0")
        );
        assertEq(
            targets[1], LibUnderlyingNamingRollout.receiptVaultBeacon(chainId), string.concat(network, ": vault beacon")
        );
        assertEq(
            payloads[1],
            abi.encodeCall(UpgradeableBeacon.upgradeTo, (LibUnderlyingNamingRollout.RECEIPT_VAULT_IMPLEMENTATION)),
            string.concat(network, ": beacon upgrade 1")
        );
        assertEq(
            targets[2],
            LibUnderlyingNamingRollout.tokens(chainId)[0].receiptVault,
            string.concat(network, ": probe vault")
        );
        assertEq(
            payloads[2],
            abi.encodeCall(ICorporateActionsV1.completedActionCount, ()),
            string.concat(network, ": probe call")
        );
        for (uint256 callIndex = 0; callIndex < values.length; callIndex++) {
            assertEq(values[callIndex], 0, string.concat(network, ": value"));
        }
    }

    /// @notice Logs the gas the rename batch's `executeBatch` alone takes, on a
    /// snapshot: what the executing key must fit in one block.
    function logRenameExecutionGas(TimelockController controller, uint256 chainId, bytes32 beaconId) internal {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            LibUnderlyingNamingRollout.renameBatch(chainId);
        uint256 snapshot = vm.snapshotState();
        uint256 gasBefore = gasleft();
        controller.executeBatch(targets, values, payloads, beaconId, LibUnderlyingNamingRollout.RENAME_SALT);
        console2.log("Rename batch executeBatch gas:", gasBefore - gasleft());
        vm.revertToState(snapshot);
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

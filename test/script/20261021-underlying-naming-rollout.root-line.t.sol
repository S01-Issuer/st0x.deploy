// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {
    ExecuteUnderlyingNaming,
    ExecuteUnderlyingNamingRecorded
} from "../../script/20261021-execute-underlying-naming.s.sol";
import {BeaconBatchNotScheduled} from "../../script/20261021-schedule-underlying-naming-rename.s.sol";
import {ExecuteUnderlyingNamingHarness} from "./ExecuteUnderlyingNamingHarness.sol";
import {ScheduleUnderlyingNamingBeaconsHarness} from "./ScheduleUnderlyingNamingBeaconsHarness.sol";
import {ScheduleUnderlyingNamingRenameHarness} from "./ScheduleUnderlyingNamingRenameHarness.sol";
import {UnderlyingNamingRolloutFixture} from "./UnderlyingNamingRolloutFixture.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {RootLineRecordScriptTest} from "../lib/RootLineRecordScriptTest.sol";
import {SafeBundleScriptHooks} from "../lib/SafeBundleScriptHooks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibUnderlyingNamingRollout} from "../../src/lib/LibUnderlyingNamingRollout.sol";

/// @title ScheduleUnderlyingNamingBeaconsRootLineTest
/// @notice The beacon schedule on Base, from the line at genesis with the
/// implementations planted.
contract ScheduleUnderlyingNamingBeaconsRootLineTest is UnderlyingNamingRolloutFixture, RootLineRecordScriptTest {
    function newScript() internal override returns (SafeBundleScriptHooks) {
        return new ScheduleUnderlyingNamingBeaconsHarness("root-line");
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK;
    }

    function landBeforeOnto() internal override {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        plantImplementations();
    }

    function landOnto() internal override {
        advanceRootLineToBeaconSchedule();
    }

    function testBundleIsTheScheduleThenTheRecord() external view {
        SafeTx[] memory txs = sScript.callAuthorBundle();
        assertEq(txs.length, 2, "schedule then record");
        assertEq(txs[0].to, LibTimelockInvariants.timelockForChainId(block.chainid), "schedule target");
        assertEq(txs[0].data, LibUnderlyingNamingRollout.scheduleBeaconCalldata(block.chainid), "schedule calldata");
    }
}

/// @title ScheduleUnderlyingNamingRenameRootLineTest
/// @notice The rename schedule on Base, from the line at the orchestrator admin
/// move.
contract ScheduleUnderlyingNamingRenameRootLineTest is UnderlyingNamingRolloutFixture, RootLineRecordScriptTest {
    function newScript() internal override returns (SafeBundleScriptHooks) {
        return new ScheduleUnderlyingNamingRenameHarness("root-line");
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS;
    }

    function landBeforeOnto() internal override {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        advanceRootLineToBeaconSchedule();
    }

    function landOnto() internal override {
        landBeaconScheduleAndHandOver(ScheduleUnderlyingNamingRenameHarness(address(sScript)));
    }

    function testBundleIsTheScheduleThenTheRecord() external view {
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        SafeTx[] memory txs = sScript.callAuthorBundle();
        assertEq(txs.length, 2, "schedule then record");
        assertEq(txs[0].to, timelock, "schedule target");
        assertEq(
            txs[0].data, LibUnderlyingNamingRollout.scheduleRenameCalldata(timelock, block.chainid), "schedule calldata"
        );
    }

    /// @notice A cancelled beacon batch refuses even with its record standing.
    function testPreflightRefusesACancelledBeaconBatch() external {
        sScript.callPreflight();
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        bytes32 beaconId = LibUnderlyingNamingRollout.beaconOperationId(timelock, block.chainid);
        vm.prank(safeAddress());
        TimelockController(payable(timelock)).cancel(beaconId);
        vm.expectRevert(abi.encodeWithSelector(BeaconBatchNotScheduled.selector, beaconId));
        sScript.callPreflight();
    }
}

/// @title ExecuteUnderlyingNamingRootLineTest
/// @notice The execution record on Base, from both batches executed with the
/// rename scheduled but its record not yet landed.
contract ExecuteUnderlyingNamingRootLineTest is UnderlyingNamingRolloutFixture, RootLineRecordScriptTest {
    function newScript() internal override returns (SafeBundleScriptHooks) {
        return new ExecuteUnderlyingNamingHarness("root-line");
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.EXECUTE_UNDERLYING_NAMING;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME;
    }

    function landBeforeOnto() internal override {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        ScheduleUnderlyingNamingRenameHarness rename = new ScheduleUnderlyingNamingRenameHarness("execute-root-line");
        prepareRename(rename);
        executePrefix(rename.callAuthorBundle(), 1);
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        ExecuteUnderlyingNaming executor = new ExecuteUnderlyingNaming();
        executor.execute();
        executor.execute();
    }

    function landOnto() internal override {
        LibTestRootLine.write(
            vm,
            safeAddress(),
            LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME,
            LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS
        );
    }

    function testBundleIsTheRecordOnly() external view {
        assertEq(sScript.callAuthorBundle().length, 1, "record only");
    }

    function testPreflightRefusesOnceRecorded() external {
        executeBundle();
        vm.expectRevert(
            abi.encodeWithSelector(
                ExecuteUnderlyingNamingRecorded.selector, LibStoxMigrations.EXECUTE_UNDERLYING_NAMING
            )
        );
        sScript.callPreflight();
    }
}

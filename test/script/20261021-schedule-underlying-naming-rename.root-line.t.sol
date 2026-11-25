// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {LibRainDeploy} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";

import {BeaconBatchNotScheduled} from "../../script/20261021-schedule-underlying-naming-rename.s.sol";
import {ScheduleUnderlyingNamingRenameHarness} from "./ScheduleUnderlyingNamingRenameHarness.sol";
import {UnderlyingNamingRolloutFixture} from "./UnderlyingNamingRolloutFixture.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";
import {IRecordScriptHooks} from "../lib/RootLineRecordScriptTest.sol";
import {RootLineBatchRecordScriptTest} from "../lib/RootLineBatchRecordScriptTest.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibUnderlyingNamingRollout} from "../../src/lib/LibUnderlyingNamingRollout.sol";

/// @title ScheduleUnderlyingNamingRenameRootLineTest
/// @notice The rename schedule on Base, from the beacon batch scheduled with
/// the line at the Safe-owned Base vault handover.
contract ScheduleUnderlyingNamingRenameRootLineTest is UnderlyingNamingRolloutFixture, RootLineBatchRecordScriptTest {
    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new ScheduleUnderlyingNamingRenameHarness("root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS;
    }

    function landBeforeSchedule() internal override {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        prepareRename();
    }

    function batch() internal view override returns (address[] memory, uint256[] memory, bytes[] memory) {
        return LibUnderlyingNamingRollout.renameBatch(block.chainid);
    }

    function scheduleCalldata() internal view override returns (bytes memory) {
        return LibUnderlyingNamingRollout.scheduleRenameCalldata(timelock(), block.chainid);
    }

    function operationId() internal view override returns (bytes32) {
        return LibUnderlyingNamingRollout.renameOperationId(timelock(), block.chainid);
    }

    function beaconOperationId() internal view returns (bytes32) {
        return LibUnderlyingNamingRollout.beaconOperationId(timelock(), block.chainid);
    }

    function executePredecessors() internal override {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            LibUnderlyingNamingRollout.beaconBatch(block.chainid);
        vm.prank(rolelessExecutor());
        controller().executeBatch(targets, values, payloads, bytes32(0), LibUnderlyingNamingRollout.BEACON_SALT);
    }

    function executeBatch() internal override {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = batch();
        bytes32 predecessor = beaconOperationId();
        vm.prank(rolelessExecutor());
        controller().executeBatch(targets, values, payloads, predecessor, LibUnderlyingNamingRollout.RENAME_SALT);
    }

    function testPreflightRefusesACancelledBeaconBatch() external {
        sScript.callPreflight();
        bytes32 beaconId = beaconOperationId();
        vm.prank(safeAddress());
        controller().cancel(beaconId);
        vm.expectRevert(abi.encodeWithSelector(BeaconBatchNotScheduled.selector, beaconId));
        sScript.callPreflight();
    }

    function testPreflightAcceptsTheLineAtTheHandoverAndAfterTheBeaconRecord() external {
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK, "handover");
        sScript.callPreflight();
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        executePredecessors();
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS, "beacon record");
        sScript.callPreflight();
    }
}

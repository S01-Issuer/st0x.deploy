// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {LibRainDeploy} from "rain-deploy-0.1.41/src/lib/LibRainDeploy.sol";

import {ScheduleUnderlyingNamingBeaconsHarness} from "./ScheduleUnderlyingNamingBeaconsHarness.sol";
import {UnderlyingNamingRolloutFixture} from "./UnderlyingNamingRolloutFixture.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {IRecordScriptHooks} from "../lib/RootLineRecordScriptTest.sol";
import {RootLineBatchRecordScriptTest} from "../lib/RootLineBatchRecordScriptTest.sol";
import {LibStoxMigrations, UnexpectedMigrationLine} from "../../src/lib/LibStoxMigrations.sol";
import {LibUnderlyingNamingRollout} from "../../src/lib/LibUnderlyingNamingRollout.sol";

/// @title ScheduleUnderlyingNamingBeaconsRootLineTest
/// @notice The beacon schedule on Base, from the line at the Safe-owned Base
/// vault handover with the implementations planted.
contract ScheduleUnderlyingNamingBeaconsRootLineTest is UnderlyingNamingRolloutFixture, RootLineBatchRecordScriptTest {
    uint256 internal sBeforeOnto;

    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new ScheduleUnderlyingNamingBeaconsHarness("root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK;
    }

    function landBeforeSchedule() internal override {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        plantImplementations();
        sBeforeOnto = vm.snapshotState();
        advanceRootLineToBeaconSchedule();
    }

    function batch() internal view override returns (address[] memory, uint256[] memory, bytes[] memory) {
        return LibUnderlyingNamingRollout.beaconBatch(block.chainid);
    }

    function scheduleCalldata() internal view override returns (bytes memory) {
        return LibUnderlyingNamingRollout.scheduleBeaconCalldata(block.chainid);
    }

    function operationId() internal view override returns (bytes32) {
        return LibUnderlyingNamingRollout.beaconOperationId(timelock(), block.chainid);
    }

    function executePredecessors() internal override {}

    function executeBatch() internal override {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = batch();
        vm.prank(rolelessExecutor());
        controller().executeBatch(targets, values, payloads, bytes32(0), LibUnderlyingNamingRollout.BEACON_SALT);
    }

    function testPreflightRefusesTheLineBeforeItsOnto() external {
        assertTrue(vm.revertToState(sBeforeOnto), "snapshot before the onto");
        bytes32 lineHead = LibStoxMigrations.head();
        assertTrue(lineHead != declaredOnto(), "line before the onto");
        LibTestRootLine.approve(vm, timelock());
        ScheduleUnderlyingNamingBeaconsHarness beacons = new ScheduleUnderlyingNamingBeaconsHarness("before-onto");
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, lineHead));
        beacons.callPreflight();
    }

    function testPreflightRefusesALineMovedPastItsOnto(bytes32 next) external {
        assumeForeign(next);
        sScript.callPreflight();
        LibTestRootLine.write(vm, safeAddress(), next, declaredOnto());
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, next));
        sScript.callPreflight();
    }

    function testPreflightRefusesTheLineAtItsOwnRecord() external {
        sScript.callPreflight();
        LibTestRootLine.write(vm, timelock(), declaredId(), declaredOnto());
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, declaredId()));
        sScript.callPreflight();
    }
}

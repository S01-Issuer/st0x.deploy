// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {BeaconBatchNotScheduled} from "../../script/20261021-schedule-underlying-naming-rename.s.sol";
import {ScheduleUnderlyingNamingRenameHarness} from "./ScheduleUnderlyingNamingRenameHarness.sol";
import {UnderlyingNamingRolloutFixture} from "./UnderlyingNamingRolloutFixture.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";
import {IRecordScriptHooks, RootLineRecordScriptTest} from "../lib/RootLineRecordScriptTest.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibUnderlyingNamingRollout} from "../../src/lib/LibUnderlyingNamingRollout.sol";

/// @title ScheduleUnderlyingNamingRenameRootLineTest
/// @notice The rename schedule on Base, from the line at the orchestrator admin
/// move.
contract ScheduleUnderlyingNamingRenameRootLineTest is UnderlyingNamingRolloutFixture, RootLineRecordScriptTest {
    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new ScheduleUnderlyingNamingRenameHarness("root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME;
    }

    /// @dev With its own record at the head and its batch not registered, the pre-flight authors a reschedule.
    function ownRecordPreflightRefusal() internal pure override returns (bytes memory) {
        return "";
    }

    function acceptsAnEarlierRecord() internal pure override returns (bool) {
        return true;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS;
    }

    function landBeforeOnto() internal override {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        advanceRootLineToBeaconSchedule();
    }

    function landOnto() internal override {
        landBeaconSchedule();
    }

    /// @dev Past the delay the post-state refuses the ready operation before the record.
    function latestRecordAge() internal pure override returns (uint256) {
        return LibTimelockInvariants.TIMELOCK_MIN_DELAY - 1;
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

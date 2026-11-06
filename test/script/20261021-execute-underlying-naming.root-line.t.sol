// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";

import {
    ExecuteUnderlyingNaming,
    ExecuteUnderlyingNamingRecorded
} from "../../script/20261021-execute-underlying-naming.s.sol";
import {ExecuteUnderlyingNamingHarness} from "./ExecuteUnderlyingNamingHarness.sol";
import {ScheduleUnderlyingNamingRenameHarness} from "./ScheduleUnderlyingNamingRenameHarness.sol";
import {UnderlyingNamingRolloutFixture} from "./UnderlyingNamingRolloutFixture.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {IRecordScriptHooks, RootLineRecordScriptTest} from "../lib/RootLineRecordScriptTest.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @title ExecuteUnderlyingNamingRootLineTest
/// @notice The execution record on Base, from both batches executed with the
/// rename scheduled but its record not yet landed.
contract ExecuteUnderlyingNamingRootLineTest is UnderlyingNamingRolloutFixture, RootLineRecordScriptTest {
    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new ExecuteUnderlyingNamingHarness("root-line")));
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

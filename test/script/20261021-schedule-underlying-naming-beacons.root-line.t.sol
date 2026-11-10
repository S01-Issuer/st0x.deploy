// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {ScheduleUnderlyingNamingBeaconsHarness} from "./ScheduleUnderlyingNamingBeaconsHarness.sol";
import {UnderlyingNamingRolloutFixture} from "./UnderlyingNamingRolloutFixture.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";
import {IRecordScriptHooks, RootLineRecordScriptTest} from "../lib/RootLineRecordScriptTest.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibUnderlyingNamingRollout} from "../../src/lib/LibUnderlyingNamingRollout.sol";

/// @title ScheduleUnderlyingNamingBeaconsRootLineTest
/// @notice The beacon schedule on Base, from the line at genesis with the
/// implementations planted.
contract ScheduleUnderlyingNamingBeaconsRootLineTest is UnderlyingNamingRolloutFixture, RootLineRecordScriptTest {
    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new ScheduleUnderlyingNamingBeaconsHarness("root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS;
    }

    /// @dev With its own record at the head and its batch not registered, the pre-flight authors a reschedule.
    function ownRecordPreflightRefusal() internal pure override returns (bytes memory) {
        return "";
    }

    function acceptsAnEarlierRecord() internal pure override returns (bool) {
        return true;
    }

    /// @dev The rename schedule's record may head the line over this one after a reschedule, so it is not foreign.
    function assumeForeign(bytes32 record) internal view override {
        super.assumeForeign(record);
        vm.assume(record != LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME);
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK;
    }

    function landBeforeOnto() internal override {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        plantImplementations();
    }

    function landOnto() internal override {
        advanceRootLineToBeaconSchedule();
    }

    /// @dev Past the delay the post-state refuses the ready operation before the record.
    function latestRecordAge() internal pure override returns (uint256) {
        return LibTimelockInvariants.TIMELOCK_MIN_DELAY - 1;
    }

    function testBundleIsTheScheduleThenTheRecord() external view {
        SafeTx[] memory txs = sScript.callAuthorBundle();
        assertEq(txs.length, 2, "schedule then record");
        assertEq(txs[0].to, LibTimelockInvariants.timelockForChainId(block.chainid), "schedule target");
        assertEq(txs[0].data, LibUnderlyingNamingRollout.scheduleBeaconCalldata(block.chainid), "schedule calldata");
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.43/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy} from "rain-deploy-0.1.43/src/lib/LibRainDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.43/src/lib/LibSafeTx.sol";

import {
    ExecuteUnderlyingNaming,
    ExecuteUnderlyingNamingRecorded,
    UnderlyingNamingNotExecuted
} from "../../script/20261021-execute-underlying-naming.s.sol";
import {ExecuteUnderlyingNamingHarness} from "./ExecuteUnderlyingNamingHarness.sol";
import {ScheduleUnderlyingNamingRenameHarness} from "./ScheduleUnderlyingNamingRenameHarness.sol";
import {UnderlyingNamingRolloutFixture} from "./UnderlyingNamingRolloutFixture.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {IRecordScriptHooks, RootLineRecordScriptTest} from "../lib/RootLineRecordScriptTest.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibUnderlyingNamingRollout} from "../../src/lib/LibUnderlyingNamingRollout.sol";

/// @title ExecuteUnderlyingNamingRootLineTest
/// @notice The execution record on Base, onto the rename batch's record, from
/// both batches scheduled and the beacon batch executed.
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
        prepareRename();
        executePrefix(rename.callAuthorBundle(), 1);
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        new ExecuteUnderlyingNaming().execute();
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS, "beacon record");
    }

    /// @dev The rename batch, whose last call writes the onto.
    function landOnto() internal override {
        new ExecuteUnderlyingNaming().execute();
    }

    function renameOperationId() internal view returns (bytes32) {
        return LibUnderlyingNamingRollout.renameOperationId(
            LibTimelockInvariants.timelockForChainId(block.chainid), block.chainid
        );
    }

    function beforeOntoPreflightRefusal(bytes32) internal view override returns (bytes memory) {
        return abi.encodeWithSelector(UnderlyingNamingNotExecuted.selector, renameOperationId());
    }

    function ownRecordPreflightRefusal() internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(ExecuteUnderlyingNamingRecorded.selector, declaredId());
    }

    function testBundleIsTheRecordOntoTheRenameRecord() external view {
        SafeTx[] memory txs = sScript.callAuthorBundle();
        assertEq(txs.length, 1, "record only");
        assertEq(txs[0].to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, "record target");
        assertEq(txs[0].value, 0, "record value");
        assertEq(
            txs[0].data,
            LibTestRootLine.recordCalldata(
                LibStoxMigrations.EXECUTE_UNDERLYING_NAMING, LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME
            ),
            "record calldata"
        );
        assertEq(uint8(txs[0].operation), uint8(Enum.Operation.Call), "record operation");
    }

    /// @notice The line at the rename record does not stand in for the
    /// executed rename batch.
    function testPreflightRefusesTheRenameRecordWithoutTheRenameBatch() external {
        assertTrue(vm.revertToState(sBeforeOnto), "snapshot before the onto");
        LibTestRootLine.write(
            vm,
            safeAddress(),
            LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME,
            LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS
        );
        assertEq(LibStoxMigrations.head(), declaredOnto(), "line at the onto");
        vm.expectRevert(abi.encodeWithSelector(UnderlyingNamingNotExecuted.selector, renameOperationId()));
        sScript.callPreflight();
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

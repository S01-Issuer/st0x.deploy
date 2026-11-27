// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {IMigrationRegistryV5, MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.43/src/interface/IMigrationRegistryV5.sol";
import {IRegistryDelegatesV3} from "rain-deploy-0.1.43/src/interface/IRegistryDelegatesV3.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.43/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.43/src/lib/LibRegistryAuthority.sol";
import {SafeTx} from "rain-deploy-0.1.43/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.43/src/lib/LibSafeFork.sol";

import {IStoxScript, ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations, RootLineWriterNotApproved} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {IRecordScriptHooks} from "./RootLineRecordScriptTest.sol";
import {LibTestRootLine} from "./LibTestRootLine.sol";

/// @title RootLineBatchRecordScriptTest
/// @notice The root-line contract of a script whose Safe bundle schedules a
/// timelock batch that ends with the batch's own record: the bundle is the
/// `scheduleBatch` alone and writes no record, the batch's last call is the
/// record and the only call to the registry, the pre-flight refuses a timelock
/// the root does not approve, and the executed batch writes the record as the
/// timelock or reverts with the registry's own refusal.
abstract contract RootLineBatchRecordScriptTest is Test {
    IRecordScriptHooks internal sScript;

    function newScript() internal virtual returns (IRecordScriptHooks);

    function declaredId() internal pure virtual returns (bytes32);

    function declaredOnto() internal pure virtual returns (bytes32);

    /// @dev Everything the pre-flight needs.
    function landBeforeSchedule() internal virtual;

    function batch() internal view virtual returns (address[] memory, uint256[] memory, bytes[] memory);

    function scheduleCalldata() internal view virtual returns (bytes memory);

    function operationId() internal view virtual returns (bytes32);

    /// @dev Executes, past the delay, every operation the batch waits on.
    function executePredecessors() internal virtual;

    /// @dev Executes the batch from `rolelessExecutor()`.
    function executeBatch() internal virtual;

    function setUp() public virtual {
        landBeforeSchedule();
        sScript = newScript();
    }

    function externalExecuteBatch() external {
        executeBatch();
    }

    function rolelessExecutor() internal returns (address) {
        return makeAddr("roleless executor");
    }

    function safeAddress() internal view returns (address) {
        return LibSafeInvariants.safeForChainId(block.chainid);
    }

    function timelock() internal view returns (address) {
        return LibTimelockInvariants.timelockForChainId(block.chainid);
    }

    function controller() internal view returns (TimelockController) {
        return TimelockController(payable(timelock()));
    }

    function registry() internal pure returns (address) {
        return LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS;
    }

    function schedule() internal {
        LibSafeFork.executeBundle(vm, Safe(payable(safeAddress())), sScript.callAuthorBundle());
    }

    function scheduleThenExecutePredecessors() internal {
        schedule();
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        executePredecessors();
    }

    function assumeForeign(bytes32 record) internal view {
        vm.assume(record != bytes32(0) && record != MIGRATION_HEAD_GENESIS && LibStoxMigrations.applied(record) == 0);
        vm.assume(record != declaredId());
    }

    function testDeclarationIsTheBatchRecord(uint256 chainId) external view {
        ScriptDeclaration memory declaration = IStoxScript(address(sScript)).declaration(chainId);
        assertEq(declaration.id, declaredId(), "id");
        assertEq(declaration.onto, declaredOnto(), "onto");
        assertFalse(declaration.history, "history");
    }

    function testBundleIsTheScheduleAlone() external view {
        SafeTx[] memory txs = sScript.callAuthorBundle();
        assertEq(txs.length, 1, "one call");
        assertEq(txs[0].to, timelock(), "schedule target");
        assertEq(txs[0].value, 0, "schedule value");
        assertEq(txs[0].data, scheduleCalldata(), "schedule calldata");
        assertEq(uint8(txs[0].operation), uint8(Enum.Operation.Call), "schedule operation");
    }

    function testBatchEndsWithItsRecordAndNoEarlierCallTargetsTheRegistry() external view {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = batch();
        uint256 last = targets.length - 1;
        assertEq(targets[last], registry(), "record target");
        assertEq(values[last], 0, "record value");
        assertEq(payloads[last], LibTestRootLine.recordCalldata(declaredId(), declaredOnto()), "record calldata");
        for (uint256 callIndex = 0; callIndex < last; callIndex++) {
            assertTrue(targets[callIndex] != registry(), "earlier call to the registry");
        }
    }

    function testPreflightRefusesATimelockTheRootDoesNotApprove() external {
        sScript.callPreflight();
        LibTestRootLine.revoke(vm, timelock());
        vm.expectRevert(abi.encodeWithSelector(RootLineWriterNotApproved.selector, timelock()));
        sScript.callPreflight();
    }

    function testLandedBundleWritesNoRecord() external {
        bytes32 headBefore = LibStoxMigrations.head();
        schedule();
        assertEq(LibStoxMigrations.applied(declaredId()), 0, "no record");
        assertEq(LibStoxMigrations.head(), headBefore, "line unmoved");
        sScript.callAssertPostState();
    }

    function testExecutedBatchWritesItsRecordAsTheTimelock() external {
        scheduleThenExecutePredecessors();
        assertFalse(
            IAccessControl(timelock()).hasRole(LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE, rolelessExecutor()),
            "executor holds no role"
        );
        executeBatch();
        assertTrue(controller().isOperationDone(operationId()), "operation done");
        assertEq(LibStoxMigrations.applied(declaredId()), block.timestamp, "record stamped at the block");
        assertEq(LibStoxMigrations.head(), declaredId(), "record heads the line");
        IMigrationRegistryV5 migrations = IMigrationRegistryV5(registry());
        assertEq(
            migrations.appliedOntoV5(LibRegistryAuthority.ROOT_AUTHORITY, LibStoxMigrations.NAMESPACE, declaredId()),
            declaredOnto(),
            "record onto"
        );
        assertEq(
            migrations.appliedByV5(LibRegistryAuthority.ROOT_AUTHORITY, LibStoxMigrations.NAMESPACE, declaredId()),
            timelock(),
            "written by the timelock"
        );
    }

    /// A batch the Safe cancels, inside or after the delay, schedules again from the same
    /// script and its execution writes the record.
    function testACancelledBatchReschedulesAndWritesItsRecord(uint256 elapsed) external {
        elapsed = bound(elapsed, 0, 2 * LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        bytes32 headBefore = LibStoxMigrations.head();
        bytes32 id = operationId();
        schedule();
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + elapsed);
        vm.prank(safeAddress());
        controller().cancel(id);
        assertFalse(controller().isOperation(id), "cancelled");
        assertEq(LibStoxMigrations.applied(declaredId()), 0, "no record");
        assertEq(LibStoxMigrations.head(), headBefore, "line unmoved");
        sScript.callPreflight();
        scheduleThenExecutePredecessors();
        executeBatch();
        assertTrue(controller().isOperationDone(id), "rescheduled operation done");
        assertEq(LibStoxMigrations.applied(declaredId()), block.timestamp, "record stamped at the block");
        assertEq(LibStoxMigrations.head(), declaredId(), "record heads the line");
        assertEq(
            IMigrationRegistryV5(registry())
                .appliedByV5(LibRegistryAuthority.ROOT_AUTHORITY, LibStoxMigrations.NAMESPACE, declaredId()),
            timelock(),
            "written by the timelock"
        );
    }

    function testExecuteRefusesATimelockRevokedAfterScheduling() external {
        scheduleThenExecutePredecessors();
        LibTestRootLine.revoke(vm, timelock());
        vm.expectRevert(
            abi.encodeWithSelector(
                IRegistryDelegatesV3.NotApproved.selector,
                LibRegistryAuthority.ROOT_AUTHORITY,
                LibStoxMigrations.NAMESPACE,
                timelock()
            )
        );
        this.externalExecuteBatch();
        assertFalse(controller().isOperationDone(operationId()), "operation not done");
        assertEq(LibStoxMigrations.applied(declaredId()), 0, "no record");
    }

    function testExecuteRefusesAForeignRecordOntoItsOnto(bytes32 next) external {
        scheduleThenExecutePredecessors();
        assumeForeign(next);
        assertEq(LibStoxMigrations.head(), declaredOnto(), "line at the onto");
        LibTestRootLine.write(vm, safeAddress(), next, declaredOnto());
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV5.UnexpectedMigrationHead.selector,
                LibRegistryAuthority.ROOT_AUTHORITY,
                LibStoxMigrations.NAMESPACE,
                LibRegistryAuthority.ROOT_AUTHORITY,
                LibStoxMigrations.NAMESPACE,
                declaredOnto(),
                next
            )
        );
        this.externalExecuteBatch();
        assertFalse(controller().isOperationDone(operationId()), "operation not done");
        assertEq(LibStoxMigrations.applied(declaredId()), 0, "no record");
    }
}

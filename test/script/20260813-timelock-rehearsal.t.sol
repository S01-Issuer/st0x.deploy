// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";

import {
    TimelockRehearsalSchedule,
    RehearsalScheduleNotHistory,
    RehearsalScheduleRecordedByBackfill
} from "../../script/20260813-timelock-rehearsal-schedule.s.sol";
import {
    TimelockRehearsalCancel,
    RehearsalCancelNotHistory,
    RehearsalCancelRecordedByBackfill
} from "../../script/20260813-timelock-rehearsal-cancel.s.sol";
import {
    ExecuteTimelockOperations,
    ExecuteTimelockOperationsNotHistory,
    ExecuteTimelockOperationsRecordedByBackfill
} from "../../script/20260813-execute-timelock-operations.s.sol";
import {IStoxHistoryMigration, ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTimelockRehearsal} from "../../src/lib/LibTimelockRehearsal.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";

contract TimelockRehearsalTest is Test {
    TimelockRehearsalSchedule internal scheduleScript;
    TimelockRehearsalCancel internal cancelScript;
    ExecuteTimelockOperations internal executeScript;

    function setUp() external {
        scheduleScript = new TimelockRehearsalSchedule();
        cancelScript = new TimelockRehearsalCancel();
        executeScript = new ExecuteTimelockOperations();
        vm.makePersistent(address(scheduleScript), address(cancelScript), address(executeScript));
    }

    function baseTimelock() internal pure returns (address) {
        return LibTimelockInvariants.timelockForChainId(LibSafeInvariants.BASE_CHAIN_ID);
    }

    /// @dev Literal parameters hashed by the live timelock, so a library drift cannot agree with itself.
    function testRehearsalOperationIdMatchesTheLibrary() external {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        TimelockController timelock = TimelockController(payable(baseTimelock()));
        bytes32 expected = timelock.hashOperation(
            address(timelock),
            0,
            abi.encodeCall(TimelockController.updateDelay, (LibTimelockInvariants.TIMELOCK_MIN_DELAY)),
            bytes32(0),
            keccak256("st0x.timelock.rehearsal.20260813")
        );
        assertEq(LibTimelockRehearsal.operationId(address(timelock)), expected);
    }

    function assertDeclared(ScriptDeclaration memory declared, bytes32 id, bytes32 onto, bool history) internal pure {
        assertEq(declared.id, id);
        assertEq(declared.onto, onto);
        assertEq(declared.history, history);
    }

    function testScheduleOnBaseIsHistoryOntoTheMultisigThreshold() external view {
        assertDeclared(
            scheduleScript.declaration(LibSafeInvariants.BASE_CHAIN_ID),
            LibStoxMigrations.TIMELOCK_REHEARSAL_SCHEDULE,
            LibStoxMigrations.MULTISIG_THRESHOLD,
            true
        );
    }

    function testScheduleOffBaseIsARecordOntoTheEmergencyGrant(uint256 chainId) external view {
        vm.assume(chainId != LibSafeInvariants.BASE_CHAIN_ID);
        assertDeclared(
            scheduleScript.declaration(chainId),
            LibStoxMigrations.TIMELOCK_REHEARSAL_SCHEDULE,
            LibStoxMigrations.ORCHESTRATOR_EMERGENCY,
            false
        );
    }

    function testCancelFollowsTheScheduleAsHistoryOnlyOnBase(uint256 chainId) external view {
        assertDeclared(
            cancelScript.declaration(chainId),
            LibStoxMigrations.TIMELOCK_REHEARSAL_CANCEL,
            LibStoxMigrations.TIMELOCK_REHEARSAL_SCHEDULE,
            chainId == LibSafeInvariants.BASE_CHAIN_ID
        );
    }

    function testExecuteFollowsTheCancelAsHistoryOnlyOnBase(uint256 chainId) external view {
        assertDeclared(
            executeScript.declaration(chainId),
            LibStoxMigrations.EXECUTE_TIMELOCK_OPERATIONS,
            LibStoxMigrations.TIMELOCK_REHEARSAL_CANCEL,
            chainId == LibSafeInvariants.BASE_CHAIN_ID
        );
    }

    function testCancelOnBaseIsHistoryOntoTheSchedule() external view {
        assertDeclared(
            cancelScript.declaration(LibSafeInvariants.BASE_CHAIN_ID),
            LibStoxMigrations.TIMELOCK_REHEARSAL_CANCEL,
            LibStoxMigrations.TIMELOCK_REHEARSAL_SCHEDULE,
            true
        );
    }

    function testExecuteOnBaseIsHistoryOntoTheCancel() external view {
        assertDeclared(
            executeScript.declaration(LibSafeInvariants.BASE_CHAIN_ID),
            LibStoxMigrations.EXECUTE_TIMELOCK_OPERATIONS,
            LibStoxMigrations.TIMELOCK_REHEARSAL_CANCEL,
            true
        );
    }

    function assertNotHistoryOffBase(IStoxHistoryMigration script, bytes4 selector, uint256 chainId) internal {
        vm.assume(chainId != LibSafeInvariants.BASE_CHAIN_ID);
        vm.expectRevert(abi.encodeWithSelector(selector, chainId));
        script.executedAt(chainId);
    }

    function testScheduleExecutedAtRefusesOffBase(uint256 chainId) external {
        assertNotHistoryOffBase(scheduleScript, RehearsalScheduleNotHistory.selector, chainId);
    }

    function testCancelExecutedAtRefusesOffBase(uint256 chainId) external {
        assertNotHistoryOffBase(cancelScript, RehearsalCancelNotHistory.selector, chainId);
    }

    function testExecuteExecutedAtRefusesOffBase(uint256 chainId) external {
        assertNotHistoryOffBase(executeScript, ExecuteTimelockOperationsNotHistory.selector, chainId);
    }

    function testScheduleRunRefusesBecauseTheBackfillWritesTheRecord(uint256 chainId) external {
        chainId = bound(chainId, 0, type(uint64).max / 2 - 36);
        vm.chainId(chainId);
        vm.expectRevert(abi.encodeWithSelector(RehearsalScheduleRecordedByBackfill.selector, chainId));
        scheduleScript.run();
    }

    function testCancelRunRefusesBecauseTheBackfillWritesTheRecord(uint256 chainId) external {
        chainId = bound(chainId, 0, type(uint64).max / 2 - 36);
        vm.chainId(chainId);
        vm.expectRevert(abi.encodeWithSelector(RehearsalCancelRecordedByBackfill.selector, chainId));
        cancelScript.run();
    }

    function testExecuteRunRefusesBecauseTheBackfillWritesTheRecord(uint256 chainId) external {
        chainId = bound(chainId, 0, type(uint64).max / 2 - 36);
        vm.chainId(chainId);
        vm.expectRevert(abi.encodeWithSelector(ExecuteTimelockOperationsRecordedByBackfill.selector, chainId));
        executeScript.run();
    }

    function testRunRefusesOnChainZero() external {
        vm.chainId(0);
        vm.expectRevert(abi.encodeWithSelector(RehearsalScheduleRecordedByBackfill.selector, uint256(0)));
        scheduleScript.run();
        vm.expectRevert(abi.encodeWithSelector(RehearsalCancelRecordedByBackfill.selector, uint256(0)));
        cancelScript.run();
        vm.expectRevert(abi.encodeWithSelector(ExecuteTimelockOperationsRecordedByBackfill.selector, uint256(0)));
        executeScript.run();
    }

    function assertRehearsalEventAt(IStoxHistoryMigration script, string memory eventSignature, uint256 blockNumber)
        internal
    {
        // A fork at the block reads its header and logs; no state at that
        // block is touched, so no archive node is needed.
        vm.createSelectFork(LibRainDeploy.BASE, blockNumber);
        bytes32[] memory topics = new bytes32[](2);
        topics[0] = keccak256(bytes(eventSignature));
        topics[1] = LibTimelockRehearsal.operationId(baseTimelock());
        Vm.EthGetLogs[] memory logs = vm.eth_getLogs(blockNumber, blockNumber, baseTimelock(), topics);
        assertEq(logs.length, 1, eventSignature);
        assertEq(script.executedAt(LibSafeInvariants.BASE_CHAIN_ID), block.timestamp, eventSignature);
    }

    function testExecutedAtIsTheRehearsalBlockOnBase() external {
        assertRehearsalEventAt(
            scheduleScript, "CallScheduled(bytes32,uint256,address,uint256,bytes,bytes32,uint256)", 50143676
        );
        assertRehearsalEventAt(cancelScript, "Cancelled(bytes32)", 50181351);
        assertRehearsalEventAt(executeScript, "CallExecuted(bytes32,uint256,address,uint256,bytes)", 50273568);
    }
}

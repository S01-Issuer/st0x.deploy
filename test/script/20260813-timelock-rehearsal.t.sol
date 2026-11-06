// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {LibTimelockRehearsal} from "rain-deploy-0.1.30/src/lib/LibTimelockRehearsal.sol";
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
import {IStoxHistoryMigration} from "../../src/interface/IStoxScript.sol";
import {BackfilledHistoryScriptTest} from "../lib/HistoryMigrationScriptTest.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
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

    function rehearsalOperationId(address timelock) internal pure returns (bytes32) {
        return LibTimelockRehearsal.operationId(
            timelock, LibTimelockInvariants.TIMELOCK_MIN_DELAY, keccak256("st0x.timelock.rehearsal.20260813")
        );
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
        assertEq(rehearsalOperationId(address(timelock)), expected);
    }

    function assertRehearsalEventAt(IStoxHistoryMigration script, string memory eventSignature, uint256 blockNumber)
        internal
    {
        // A fork at the block reads its header and logs; no state at that
        // block is touched, so no archive node is needed.
        vm.createSelectFork(LibRainDeploy.BASE, blockNumber);
        bytes32[] memory topics = new bytes32[](2);
        topics[0] = keccak256(bytes(eventSignature));
        topics[1] = rehearsalOperationId(baseTimelock());
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

contract TimelockRehearsalScheduleHistoryTest is BackfilledHistoryScriptTest {
    function newHistoryScript() internal override returns (address) {
        return address(new TimelockRehearsalSchedule());
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.TIMELOCK_REHEARSAL_SCHEDULE;
    }

    function declaredOnto(uint256 chainId) internal pure override returns (bytes32) {
        return chainId == LibSafeInvariants.BASE_CHAIN_ID
            ? LibStoxMigrations.MULTISIG_THRESHOLD
            : LibStoxMigrations.ORCHESTRATOR_EMERGENCY;
    }

    function declaredHistory(uint256 chainId) internal pure override returns (bool) {
        return chainId == LibSafeInvariants.BASE_CHAIN_ID;
    }

    function ranOn(uint256 chainId) internal pure override returns (bool) {
        return chainId == LibSafeInvariants.BASE_CHAIN_ID;
    }

    function executedAtRefusal(uint256 chainId) internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(RehearsalScheduleNotHistory.selector, chainId);
    }

    function runRefusal(uint256 chainId) internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(RehearsalScheduleRecordedByBackfill.selector, chainId);
    }
}

contract TimelockRehearsalCancelHistoryTest is BackfilledHistoryScriptTest {
    function newHistoryScript() internal override returns (address) {
        return address(new TimelockRehearsalCancel());
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.TIMELOCK_REHEARSAL_CANCEL;
    }

    function declaredOnto(uint256) internal pure override returns (bytes32) {
        return LibStoxMigrations.TIMELOCK_REHEARSAL_SCHEDULE;
    }

    function declaredHistory(uint256 chainId) internal pure override returns (bool) {
        return chainId == LibSafeInvariants.BASE_CHAIN_ID;
    }

    function ranOn(uint256 chainId) internal pure override returns (bool) {
        return chainId == LibSafeInvariants.BASE_CHAIN_ID;
    }

    function executedAtRefusal(uint256 chainId) internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(RehearsalCancelNotHistory.selector, chainId);
    }

    function runRefusal(uint256 chainId) internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(RehearsalCancelRecordedByBackfill.selector, chainId);
    }
}

contract ExecuteTimelockOperationsHistoryTest is BackfilledHistoryScriptTest {
    function newHistoryScript() internal override returns (address) {
        return address(new ExecuteTimelockOperations());
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.EXECUTE_TIMELOCK_OPERATIONS;
    }

    function declaredOnto(uint256) internal pure override returns (bytes32) {
        return LibStoxMigrations.TIMELOCK_REHEARSAL_CANCEL;
    }

    function declaredHistory(uint256 chainId) internal pure override returns (bool) {
        return chainId == LibSafeInvariants.BASE_CHAIN_ID;
    }

    function ranOn(uint256 chainId) internal pure override returns (bool) {
        return chainId == LibSafeInvariants.BASE_CHAIN_ID;
    }

    function executedAtRefusal(uint256 chainId) internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(ExecuteTimelockOperationsNotHistory.selector, chainId);
    }

    function runRefusal(uint256 chainId) internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(ExecuteTimelockOperationsRecordedByBackfill.selector, chainId);
    }
}

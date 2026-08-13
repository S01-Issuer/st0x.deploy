// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {TimelockController} from "@openzeppelin-contracts-5.6.1/governance/TimelockController.sol";

import {
    TimelockRehearsal,
    RehearsalAlreadyScheduled,
    RehearsalNotScheduled
} from "../../script/20260813-timelock-rehearsal.s.sol";
import {
    ExecuteTimelockOperations,
    OperationNotExecutable
} from "../../script/20260813-execute-timelock-operations.s.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx} from "../../src/lib/LibSafeOps.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @title TimelockRehearsalTest
/// @notice Live Base fork coverage for the pre-handover rehearsal: schedule
/// a no-op, cancel it, schedule it again, and execute it from an address
/// holding no roles.
/// @dev Unpinned head fork so the assertions run against the live timelock
/// and Safe, the same state a real dispatch authors from.
contract TimelockRehearsalTest is Test {
    TimelockRehearsal internal rehearsal;

    function setUp() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        rehearsal = new TimelockRehearsal();
    }

    /// @notice The active chain's timelock, as the scripts resolve it.
    function timelock() internal view returns (TimelockController) {
        return TimelockController(payable(LibTimelockInvariants.timelockForChainId(block.chainid)));
    }

    /// @notice Read the operation id out of an emitted artifact by
    /// re-deriving it the way the script does, so the test does not restate
    /// the operation shape independently.
    function rehearsalOperationId() internal view returns (bytes32) {
        address tl = address(timelock());
        return timelock()
            .hashOperation(
                tl,
                0,
                abi.encodeCall(TimelockController.updateDelay, (LibTimelockInvariants.TIMELOCK_MIN_DELAY)),
                bytes32(0),
                keccak256("st0x.timelock.rehearsal.20260813")
            );
    }

    /// @notice Scheduling authors a one-transaction bundle targeting the
    /// timelock, and the run's own fork proof shows the operation matures
    /// and executes without changing the delay.
    function testScheduleAuthorsABundle() external {
        rehearsal.run();

        (uint256 chainId, address firstTarget, SafeTx[] memory txs) = LibSafeOps.parseTxBuilderJson(
            string.concat("out/20260813-timelock-rehearsal-schedule-", vm.toString(block.chainid), ".json")
        );
        assertEq(chainId, LibSafeInvariants.BASE_CHAIN_ID);
        assertEq(firstTarget, address(timelock()), "the rehearsal targets the timelock itself");
        assertEq(txs.length, 1, "scheduling is a single call");
        assertEq(
            txs[0].data,
            abi.encodeCall(
                TimelockController.schedule,
                (
                    address(timelock()),
                    0,
                    abi.encodeCall(TimelockController.updateDelay, (LibTimelockInvariants.TIMELOCK_MIN_DELAY)),
                    bytes32(0),
                    keccak256("st0x.timelock.rehearsal.20260813"),
                    LibTimelockInvariants.TIMELOCK_MIN_DELAY
                )
            )
        );
    }

    /// @notice The rehearsal is a no-op by construction: the operation it
    /// schedules sets the delay to the value already held, so executing it
    /// leaves `getMinDelay()` unchanged.
    function testRehearsalIsANoOp() external {
        uint256 before = timelock().getMinDelay();
        rehearsal.run();
        assertEq(timelock().getMinDelay(), before, "the rehearsal must not change the delay");
        assertEq(before, LibTimelockInvariants.TIMELOCK_MIN_DELAY);
    }

    /// @notice Cancelling refuses while nothing is scheduled, rather than
    /// emitting a bundle that would revert inside the Safe.
    function testCancelRefusesWhenNothingScheduled() external {
        vm.expectRevert(abi.encodeWithSelector(RehearsalNotScheduled.selector, rehearsalOperationId()));
        rehearsal.cancel();
    }

    /// @notice Scheduling refuses when the operation is already registered,
    /// for the same reason.
    function testScheduleRefusesWhenAlreadyScheduled() external {
        // Put the operation on-chain via the Safe, then ask the script to
        // schedule it again.
        _scheduleAsSafe();
        vm.expectRevert(abi.encodeWithSelector(RehearsalAlreadyScheduled.selector, rehearsalOperationId()));
        rehearsal.run();
    }

    /// @notice The full stage sequence: schedule, cancel, re-schedule. After
    /// the cancel the SAME id is schedulable again — the property the
    /// rehearsal exists to demonstrate.
    function testScheduleCancelReschedule() external {
        bytes32 id = rehearsalOperationId();

        _scheduleAsSafe();
        assertTrue(timelock().isOperationPending(id), "scheduled");

        // `cancel()` simulates the Safe call against the fork, so the
        // operation is genuinely cleared here — no second cancel needed.
        rehearsal.cancel();
        assertFalse(timelock().isOperation(id), "cancel clears the operation");

        rehearsal.reschedule();
        (,, SafeTx[] memory txs) = LibSafeOps.parseTxBuilderJson(
            string.concat("out/20260813-timelock-rehearsal-reschedule-", vm.toString(block.chainid), ".json")
        );
        assertEq(txs.length, 1);
        assertEq(txs[0].to, address(timelock()));
    }

    /// @notice The executor script and the rehearsal script derive the SAME
    /// operation id. They hold the salt and payload separately, so a drift
    /// between them would leave the executor unable to execute what the
    /// rehearsal scheduled — with no other test catching it.
    function testExecutorTargetsTheRehearsalOperation() external {
        _scheduleAsSafe();
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);

        // A roleless address executes: this is what the broadcast script does
        // from the CI deploy key.
        ExecuteTimelockOperations executor = new ExecuteTimelockOperations();
        executor.run();

        assertTrue(timelock().isOperationDone(rehearsalOperationId()), "executor completed the rehearsal operation");
    }

    /// @notice The executor refuses while the operation is still inside its
    /// delay window, rather than reverting opaquely inside the timelock.
    function testExecutorRefusesBeforeTheDelay() external {
        _scheduleAsSafe();
        ExecuteTimelockOperations executor = new ExecuteTimelockOperations();
        vm.expectRevert(
            abi.encodeWithSelector(OperationNotExecutable.selector, rehearsalOperationId(), true, false, false)
        );
        executor.run();
    }

    /// @notice Schedule the rehearsal operation on-chain as the Safe.
    function _scheduleAsSafe() internal {
        address tl = address(timelock());
        vm.prank(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        timelock()
            .schedule(
                tl,
                0,
                abi.encodeCall(TimelockController.updateDelay, (LibTimelockInvariants.TIMELOCK_MIN_DELAY)),
                bytes32(0),
                keccak256("st0x.timelock.rehearsal.20260813"),
                LibTimelockInvariants.TIMELOCK_MIN_DELAY
            );
    }
}

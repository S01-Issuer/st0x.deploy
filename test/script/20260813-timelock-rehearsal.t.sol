// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.6.1/governance/TimelockController.sol";

import {
    TimelockRehearsalSchedule,
    RehearsalAlreadyScheduled
} from "../../script/20260813-timelock-rehearsal-schedule.s.sol";
import {TimelockRehearsalCancel, RehearsalNotScheduled} from "../../script/20260813-timelock-rehearsal-cancel.s.sol";
import {
    ExecuteTimelockOperations,
    ExecutorHoldsRole,
    OperationNotExecutable
} from "../../script/20260813-execute-timelock-operations.s.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx} from "../../src/lib/LibSafeOps.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTimelockRehearsal} from "../../src/lib/LibTimelockRehearsal.sol";

/// @title TimelockRehearsalTest
/// @notice Live Base fork coverage for the pre-handover rehearsal: schedule
/// a no-op, cancel it, schedule it again, and execute it from an address
/// holding no roles.
/// @dev Unpinned head fork so the assertions run against the live timelock
/// and Safe, the same state a real dispatch authors from. That cuts both
/// ways: the rehearsal's operation id is fixed, so dispatching the stages
/// moves live Base out of the state most of these tests need. Each one that
/// drives `schedule` therefore guards on
/// `rehearsalIsRegisteredOnChain()` — see that function for why, and for what
/// keeps asserting once they are spent.
contract TimelockRehearsalTest is Test {
    TimelockRehearsalSchedule internal scheduleScript;
    TimelockRehearsalCancel internal cancelScript;

    function setUp() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        scheduleScript = new TimelockRehearsalSchedule();
        cancelScript = new TimelockRehearsalCancel();
    }

    /// @notice The active chain's timelock, as the scripts resolve it.
    function timelock() internal view returns (TimelockController) {
        return TimelockController(payable(LibTimelockInvariants.timelockForChainId(block.chainid)));
    }

    /// @notice The rehearsal operation id, derived by calling the live
    /// timelock's `hashOperation` over the operation's parameters restated as
    /// literals here.
    ///
    /// Restating them is the point: the salt and payload are owned by
    /// `LibTimelockRehearsal`, and re-deriving the id from that same library
    /// would make every assertion below agree with whatever the library said,
    /// including a drift. `testRehearsalOperationIdMatchesTheLibrary` compares
    /// the two.
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

    /// @notice True once the live timelock knows the rehearsal operation, in
    /// which case the tests below that drive `schedule` cannot run — logged so
    /// a spent run is visible rather than silently green.
    ///
    /// The fork is unpinned head and `REHEARSAL_SALT` is fixed, so the
    /// operation id is fixed on Base forever. While the rehearsal is pending
    /// the script's `!isOperation` pre-flight refuses; once it EXECUTES the
    /// refusal is permanent, because OZ writes `DONE_TIMESTAMP` and never
    /// clears it (`isOperation` is `getOperationState != Unset`). Dispatching
    /// this PR's own stages is therefore what spends these tests, and
    /// `testRehearsalIsOneShotOnceExecuted` pins that mechanism.
    ///
    /// A guarded early return is how
    /// `20260729-migrate-governance-to-timelock.t.sol::testRunRefusesUnpinnedTimelock`
    /// handles its own spent precondition; `vm.skip` is not an option because
    /// the static job bans it.
    function rehearsalIsRegisteredOnChain() internal returns (bool) {
        if (timelock().isOperation(rehearsalOperationId())) {
            emit log("SPENT: the rehearsal operation is registered on the live timelock; schedule cannot be driven");
            return true;
        }
        return false;
    }

    /// @notice The id every stage acts on is the one derived from the
    /// parameters this test owns — so a drift in `LibTimelockRehearsal`'s salt
    /// or payload is caught here, and caught for good: this reads no operation
    /// state, so it keeps asserting after the rehearsal has been spent on
    /// chain and the tests below have stopped running.
    function testRehearsalOperationIdMatchesTheLibrary() external view {
        assertEq(
            LibTimelockRehearsal.operationId(address(timelock())),
            rehearsalOperationId(),
            "the scripts and this test must agree on the rehearsal operation id"
        );
    }

    /// @notice Executing the rehearsal retires it permanently. The fixed salt
    /// fixes the id, and OZ keeps a Done operation registered forever, so the
    /// schedule script's pre-flight refuses from then on — repeating the
    /// rehearsal needs a new salt, i.e. a new dated script.
    function testRehearsalIsOneShotOnceExecuted() external {
        if (rehearsalIsRegisteredOnChain()) return;
        bytes32 id = rehearsalOperationId();

        _scheduleAsSafe();
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        new ExecuteTimelockOperations().run();
        assertTrue(timelock().isOperationDone(id), "the rehearsal executed");

        // Done, not cleared: unlike `cancel`, execution leaves the id known.
        assertTrue(timelock().isOperation(id), "a done operation stays registered");
        vm.expectRevert(abi.encodeWithSelector(RehearsalAlreadyScheduled.selector, id));
        scheduleScript.run();
    }

    /// @notice Scheduling authors a one-transaction bundle targeting the
    /// timelock, and the run's own fork proof shows the operation matures
    /// and executes without changing the delay.
    function testScheduleAuthorsABundle() external {
        if (rehearsalIsRegisteredOnChain()) return;
        scheduleScript.run();

        (uint256 chainId, address firstTarget, SafeTx[] memory txs) = LibSafeOps.parseTxBuilderJson(
            string.concat("out/20260813-timelock-rehearsal-schedule-", vm.toString(block.chainid), ".json")
        );
        assertEq(chainId, LibSafeInvariants.BASE_CHAIN_ID);
        assertEq(firstTarget, address(timelock()), "the rehearsal targets the timelock itself");
        assertEq(txs.length, 1, "scheduling is a single call");
        // The rehearsal moves no ether. `value` survives the Tx Builder
        // round-trip, so a bundle that asked the Safe to fund the timelock
        // would be caught here. `operation` does NOT survive it — the schema
        // carries no such field and `parseTxBuilderJson` writes 0
        // unconditionally — so CALL-vs-DELEGATECALL is pinned where it is
        // actually observable: `LibSafeOps._requireCallOperation` refuses to
        // serialise a non-CALL op at all, which is why `run()` above cannot
        // have emitted one.
        assertEq(txs[0].value, 0, "the rehearsal sends no value");
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
        if (rehearsalIsRegisteredOnChain()) return;
        uint256 before = timelock().getMinDelay();
        scheduleScript.run();
        assertEq(timelock().getMinDelay(), before, "the rehearsal must not change the delay");
        assertEq(before, LibTimelockInvariants.TIMELOCK_MIN_DELAY);
    }

    /// @notice Cancelling refuses while nothing is scheduled, rather than
    /// emitting a bundle that would revert inside the Safe.
    /// @dev Narrower precondition than the tests above: a DONE operation is
    /// still "nothing to cancel" (`isOperationPending` excludes it), so only a
    /// live rehearsal sitting inside its window spends this one.
    function testCancelRefusesWhenNothingScheduled() external {
        if (timelock().isOperationPending(rehearsalOperationId())) {
            emit log("SPENT: the rehearsal is pending on the live timelock; cancel has something to author");
            return;
        }
        vm.expectRevert(abi.encodeWithSelector(RehearsalNotScheduled.selector, rehearsalOperationId()));
        cancelScript.run();
    }

    /// @notice Scheduling refuses when the operation is already registered,
    /// for the same reason.
    function testScheduleRefusesWhenAlreadyScheduled() external {
        if (rehearsalIsRegisteredOnChain()) return;
        // Put the operation on-chain via the Safe, then ask the script to
        // schedule it again.
        _scheduleAsSafe();
        vm.expectRevert(abi.encodeWithSelector(RehearsalAlreadyScheduled.selector, rehearsalOperationId()));
        scheduleScript.run();
    }

    /// @notice The full stage sequence: schedule, cancel, schedule again.
    /// After the cancel the SAME id is schedulable again — which is why the
    /// re-propose stage is a re-dispatch of the schedule script rather than a
    /// separate script: there is no separate operation.
    function testScheduleCancelReschedule() external {
        if (rehearsalIsRegisteredOnChain()) return;
        bytes32 id = rehearsalOperationId();

        _scheduleAsSafe();
        assertTrue(timelock().isOperationPending(id), "scheduled");

        // `cancel()` simulates the Safe call against the fork, so the
        // operation is genuinely cleared here — no second cancel needed.
        cancelScript.run();
        assertFalse(timelock().isOperation(id), "cancel clears the operation");

        scheduleScript.run();
        (,, SafeTx[] memory txs) = LibSafeOps.parseTxBuilderJson(
            string.concat("out/20260813-timelock-rehearsal-schedule-", vm.toString(block.chainid), ".json")
        );
        assertEq(txs.length, 1);
        assertEq(txs[0].to, address(timelock()));
    }

    /// @notice The executor script and the rehearsal script derive the SAME
    /// operation id. They hold the salt and payload separately, so a drift
    /// between them would leave the executor unable to execute what the
    /// rehearsal scheduled — with no other test catching it.
    function testExecutorTargetsTheRehearsalOperation() external {
        if (rehearsalIsRegisteredOnChain()) return;
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
        if (rehearsalIsRegisteredOnChain()) return;
        _scheduleAsSafe();
        ExecuteTimelockOperations executor = new ExecuteTimelockOperations();
        vm.expectRevert(
            abi.encodeWithSelector(OperationNotExecutable.selector, rehearsalOperationId(), true, false, false)
        );
        executor.run();
    }

    /// @notice A key holding `EXECUTOR_ROLE` is refused BEFORE the execution
    /// is broadcast, not reported after it has landed. The operation is
    /// matured, so nothing but the key's own privilege stands between this
    /// call and a sent transaction — and the transaction must not be sent:
    /// executing under privilege would retire the fixed rehearsal salt
    /// (`isOperation` stays true on a Done operation) while proving nothing
    /// about permissionless execution, leaving the operator to reconstruct
    /// what happened from logs.
    function testExecutorRefusesAPrivilegedKeyBeforeBroadcasting() external {
        if (rehearsalIsRegisteredOnChain()) return;
        _scheduleAsSafe();
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);

        // The timelock self-administers, so it is the address that can grant
        // its own roles — the same path a governance action would take.
        address tl = address(timelock());
        vm.prank(tl);
        IAccessControl(tl).grantRole(LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE, address(this));

        ExecuteTimelockOperations executor = new ExecuteTimelockOperations();
        vm.expectRevert(abi.encodeWithSelector(ExecutorHoldsRole.selector, tl, address(this)));
        executor.run();

        assertFalse(
            timelock().isOperationDone(rehearsalOperationId()),
            "the refusal must precede the broadcast, so the operation stays unexecuted"
        );
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

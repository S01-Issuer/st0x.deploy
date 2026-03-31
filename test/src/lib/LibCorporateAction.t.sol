// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {
    LibCorporateAction,
    CorporateAction,
    CORPORATE_ACTION_STORAGE_LOCATION,
    CORPORATE_ACTION_STORAGE_ID,
    EXECUTION_WINDOW,
    STATUS_SCHEDULED,
    STATUS_IN_PROGRESS,
    STATUS_COMPLETE,
    STATUS_EXPIRED,
    EffectiveTimeInPast,
    ActionNotScheduled,
    ActionNotEffective,
    ActionExpired,
    ActionDoesNotExist,
    RebaseDoesNotExist
} from "../../../src/lib/LibCorporateAction.sol";
import {LibDecimalFloat, Float} from "rain.math.float/lib/LibDecimalFloat.sol";

/// @dev Thin harness that exposes LibCorporateAction internal functions for
/// testing. The library operates on its own ERC-7201 storage, so the harness
/// contract's storage layout is irrelevant — no conflicts possible.
contract LibCorporateActionHarness {
    function schedule(bytes32 actionType, uint64 effectiveTime, bytes memory parameters) external returns (uint256) {
        return LibCorporateAction.schedule(actionType, effectiveTime, parameters);
    }

    function beginExecution(uint256 actionId) external returns (bytes32, uint8, uint64, uint64) {
        CorporateAction storage action = LibCorporateAction.beginExecution(actionId);
        return (action.actionType, action.status, action.effectiveTime, action.executedTime);
    }

    function completeExecution(uint256 actionId) external {
        LibCorporateAction.completeExecution(actionId);
    }

    function completeExecutionWithMultiplier(uint256 actionId, Float multiplier) external {
        LibCorporateAction.completeExecutionWithMultiplier(actionId, multiplier);
    }

    function expire(uint256 actionId) external {
        LibCorporateAction.expire(actionId);
    }

    function getAction(uint256 actionId) external view returns (bytes32, uint8, uint64, uint64, bytes memory) {
        CorporateAction storage action = LibCorporateAction.getAction(actionId);
        return (action.actionType, action.status, action.effectiveTime, action.executedTime, action.parameters);
    }

    function getMultiplier(uint256 rebaseId) external view returns (Float) {
        return LibCorporateAction.getMultiplier(rebaseId);
    }

    function globalCAID() external view returns (uint256) {
        return LibCorporateAction.getStorage().globalCAID;
    }

    function rebaseCount() external view returns (uint256) {
        return LibCorporateAction.getStorage().rebaseCount;
    }

    function nextActionId() external view returns (uint256) {
        return LibCorporateAction.getStorage().nextActionId;
    }
}

contract LibCorporateActionStorageTest is Test {
    /// The storage location constant MUST match the ERC-7201 formula applied
    /// to the storage ID string.
    function testStorageLocationMatchesId() external pure {
        bytes32 expected = keccak256(abi.encode(uint256(keccak256(abi.encodePacked(CORPORATE_ACTION_STORAGE_ID))) - 1))
            & ~bytes32(uint256(0xff));
        assertEq(CORPORATE_ACTION_STORAGE_LOCATION, expected);
    }

    /// The storage slot MUST NOT collide with known vault storage slots.
    function testStorageLocationNoCollisionWithVault() external pure {
        bytes32[2] memory knownSlots = [
            bytes32(0x8d198d032a58038629cc32dfaad5ea74a8e78fabf390f3089701523102432600),
            bytes32(0xba9f160a0257aef2aa878e698d5363429ea67cc3c427f23f7cb9c3069b67bd00)
        ];
        for (uint256 i = 0; i < knownSlots.length; i++) {
            assertTrue(CORPORATE_ACTION_STORAGE_LOCATION != knownSlots[i]);
        }
    }

    /// Fuzz: storage location derivation is deterministic.
    function testStorageLocationDeterministic(uint256) external pure {
        bytes32 derived = keccak256(abi.encode(uint256(keccak256(abi.encodePacked(CORPORATE_ACTION_STORAGE_ID))) - 1))
            & ~bytes32(uint256(0xff));
        assertEq(CORPORATE_ACTION_STORAGE_LOCATION, derived);
    }

    /// Execution window is 4 hours.
    function testExecutionWindowIs4Hours() external pure {
        assertEq(EXECUTION_WINDOW, 4 hours);
    }
}

contract LibCorporateActionScheduleTest is Test {
    LibCorporateActionHarness harness;

    function setUp() external {
        harness = new LibCorporateActionHarness();
    }

    /// Scheduling an action returns sequential IDs starting from 1.
    function testScheduleSequentialIds() external {
        bytes32 actionType = keccak256("STOCK_SPLIT");
        uint64 future = uint64(block.timestamp + 1 days);

        uint256 id1 = harness.schedule(actionType, future, "");
        uint256 id2 = harness.schedule(actionType, future, "");
        uint256 id3 = harness.schedule(actionType, future, "");

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(id3, 3);
        assertEq(harness.nextActionId(), 3);
    }

    /// Scheduled action is stored with correct fields.
    function testScheduleStoresCorrectly() external {
        bytes32 actionType = keccak256("STOCK_SPLIT");
        uint64 future = uint64(block.timestamp + 1 days);
        bytes memory params = abi.encode(uint256(3), uint256(2));

        uint256 id = harness.schedule(actionType, future, params);

        (bytes32 storedType, uint8 status, uint64 effectiveTime, uint64 executedTime, bytes memory storedParams) =
            harness.getAction(id);

        assertEq(storedType, actionType);
        assertEq(status, STATUS_SCHEDULED);
        assertEq(effectiveTime, future);
        assertEq(executedTime, 0);
        assertEq(keccak256(storedParams), keccak256(params));
    }

    /// Cannot schedule with effective time in the past.
    function testScheduleRevertsIfPast() external {
        vm.warp(1000);
        vm.expectRevert(abi.encodeWithSelector(EffectiveTimeInPast.selector, 999, 1000));
        harness.schedule(keccak256("TEST"), 999, "");
    }

    /// Cannot schedule with effective time equal to current time.
    function testScheduleRevertsIfNow() external {
        vm.warp(1000);
        vm.expectRevert(abi.encodeWithSelector(EffectiveTimeInPast.selector, 1000, 1000));
        harness.schedule(keccak256("TEST"), 1000, "");
    }

    /// Fuzz: any future effective time succeeds, any past/current reverts.
    function testFuzzScheduleTiming(uint64 effectiveTime, uint64 currentTime) external {
        vm.warp(currentTime);
        if (effectiveTime <= currentTime) {
            vm.expectRevert(abi.encodeWithSelector(EffectiveTimeInPast.selector, effectiveTime, currentTime));
            harness.schedule(keccak256("TEST"), effectiveTime, "");
        } else {
            uint256 id = harness.schedule(keccak256("TEST"), effectiveTime, "");
            assertTrue(id > 0);
        }
    }

    /// Fuzz: sequential IDs are monotonically increasing and gap-free.
    function testFuzzSequentialIds(uint8 count) external {
        // Cap at 50 to keep gas reasonable.
        uint256 n = bound(count, 1, 50);
        uint64 future = uint64(block.timestamp + 1 days);

        for (uint256 i = 1; i <= n; i++) {
            uint256 id = harness.schedule(keccak256("TEST"), future, "");
            assertEq(id, i);
        }
        assertEq(harness.nextActionId(), n);
    }
}

contract LibCorporateActionExecutionTest is Test {
    LibCorporateActionHarness harness;
    bytes32 constant ACTION_TYPE = keccak256("STOCK_SPLIT");

    function setUp() external {
        harness = new LibCorporateActionHarness();
    }

    /// Full lifecycle: schedule → begin → complete.
    function testFullLifecycle() external {
        uint64 effectiveTime = uint64(block.timestamp + 1 days);
        uint256 id = harness.schedule(ACTION_TYPE, effectiveTime, "");

        // Warp to effective time.
        vm.warp(effectiveTime);
        (, uint8 statusBefore,,,) = harness.getAction(id);
        assertEq(statusBefore, STATUS_SCHEDULED);

        harness.beginExecution(id);
        (, uint8 statusDuring,,,) = harness.getAction(id);
        assertEq(statusDuring, STATUS_IN_PROGRESS);

        harness.completeExecution(id);
        (, uint8 statusAfter,,,) = harness.getAction(id);
        assertEq(statusAfter, STATUS_COMPLETE);
        assertEq(harness.globalCAID(), 1);
    }

    /// Cannot execute before effective time.
    function testExecuteBeforeEffectiveTimeReverts() external {
        uint64 effectiveTime = uint64(block.timestamp + 1 days);
        uint256 id = harness.schedule(ACTION_TYPE, effectiveTime, "");

        vm.expectRevert(abi.encodeWithSelector(ActionNotEffective.selector, id, effectiveTime, block.timestamp));
        harness.beginExecution(id);
    }

    /// Cannot execute after window expires.
    function testExecuteAfterWindowReverts() external {
        uint64 effectiveTime = uint64(block.timestamp + 1 days);
        uint256 id = harness.schedule(ACTION_TYPE, effectiveTime, "");

        uint256 deadline = effectiveTime + EXECUTION_WINDOW;
        vm.warp(deadline + 1);

        vm.expectRevert(abi.encodeWithSelector(ActionExpired.selector, id, deadline, deadline + 1));
        harness.beginExecution(id);
    }

    /// Executing at exactly the deadline succeeds (<=, not <).
    function testExecuteAtExactDeadlineSucceeds() external {
        uint64 effectiveTime = uint64(block.timestamp + 1 days);
        uint256 id = harness.schedule(ACTION_TYPE, effectiveTime, "");

        uint256 deadline = effectiveTime + EXECUTION_WINDOW;
        vm.warp(deadline);

        harness.beginExecution(id);
        (, uint8 status,,,) = harness.getAction(id);
        assertEq(status, STATUS_IN_PROGRESS);
    }

    /// Executing at exactly the effective time succeeds.
    function testExecuteAtExactEffectiveTimeSucceeds() external {
        uint64 effectiveTime = uint64(block.timestamp + 1 days);
        uint256 id = harness.schedule(ACTION_TYPE, effectiveTime, "");

        vm.warp(effectiveTime);
        harness.beginExecution(id);
        (, uint8 status,,,) = harness.getAction(id);
        assertEq(status, STATUS_IN_PROGRESS);
    }

    /// Cannot begin execution on a completed action.
    function testCannotReexecuteCompleted() external {
        uint64 effectiveTime = uint64(block.timestamp + 1 days);
        uint256 id = harness.schedule(ACTION_TYPE, effectiveTime, "");
        vm.warp(effectiveTime);

        harness.beginExecution(id);
        harness.completeExecution(id);

        vm.expectRevert(abi.encodeWithSelector(ActionNotScheduled.selector, id, STATUS_COMPLETE));
        harness.beginExecution(id);
    }

    /// Cannot begin execution on an expired action. The beginExecution call
    /// sets status to EXPIRED and reverts, but the revert rolls back the
    /// status change. Subsequent calls see the same ActionExpired error.
    function testCannotExecuteExpired() external {
        uint64 effectiveTime = uint64(block.timestamp + 1 days);
        uint256 id = harness.schedule(ACTION_TYPE, effectiveTime, "");

        uint256 deadline = effectiveTime + EXECUTION_WINDOW;
        vm.warp(deadline + 1);

        vm.expectRevert(abi.encodeWithSelector(ActionExpired.selector, id, deadline, deadline + 1));
        harness.beginExecution(id);

        // Use explicit expire() to persist the status change.
        harness.expire(id);
        (, uint8 status,,,) = harness.getAction(id);
        assertEq(status, STATUS_EXPIRED);

        // Now beginExecution sees EXPIRED status.
        vm.expectRevert(abi.encodeWithSelector(ActionNotScheduled.selector, id, STATUS_EXPIRED));
        harness.beginExecution(id);
    }

    /// Global CAID increments once per completed action.
    function testGlobalVersionIncrements() external {
        uint64 future = uint64(block.timestamp + 1 days);
        uint256 id1 = harness.schedule(ACTION_TYPE, future, "");
        uint256 id2 = harness.schedule(ACTION_TYPE, future, "");

        vm.warp(future);
        assertEq(harness.globalCAID(), 0);

        harness.beginExecution(id1);
        harness.completeExecution(id1);
        assertEq(harness.globalCAID(), 1);

        harness.beginExecution(id2);
        harness.completeExecution(id2);
        assertEq(harness.globalCAID(), 2);
    }

    /// Fuzz: execution only succeeds within the valid time window.
    function testFuzzExecutionWindow(uint64 effectiveTime, uint64 executionTime) external {
        // Bound effective time to something reasonable.
        effectiveTime = uint64(bound(effectiveTime, 2, type(uint64).max - EXECUTION_WINDOW - 1));
        vm.warp(effectiveTime - 1);

        uint256 id = harness.schedule(ACTION_TYPE, effectiveTime, "");

        vm.warp(executionTime);

        uint256 deadline = uint256(effectiveTime) + EXECUTION_WINDOW;

        if (executionTime < effectiveTime) {
            vm.expectRevert();
            harness.beginExecution(id);
        } else if (executionTime > deadline) {
            vm.expectRevert();
            harness.beginExecution(id);
        } else {
            harness.beginExecution(id);
            (, uint8 status,,,) = harness.getAction(id);
            assertEq(status, STATUS_IN_PROGRESS);
        }
    }
}

contract LibCorporateActionExpiryTest is Test {
    LibCorporateActionHarness harness;
    bytes32 constant ACTION_TYPE = keccak256("STOCK_SPLIT");

    function setUp() external {
        harness = new LibCorporateActionHarness();
    }

    /// Explicit expiry works after the window passes.
    function testExplicitExpiry() external {
        uint64 effectiveTime = uint64(block.timestamp + 1 days);
        uint256 id = harness.schedule(ACTION_TYPE, effectiveTime, "");

        vm.warp(effectiveTime + EXECUTION_WINDOW + 1);
        harness.expire(id);

        (, uint8 status,,,) = harness.getAction(id);
        assertEq(status, STATUS_EXPIRED);
    }

    /// Cannot expire an action that is still within its window.
    function testCannotExpireBeforeDeadline() external {
        uint64 effectiveTime = uint64(block.timestamp + 1 days);
        uint256 id = harness.schedule(ACTION_TYPE, effectiveTime, "");

        vm.warp(effectiveTime + EXECUTION_WINDOW);

        // Window hasn't passed yet (block.timestamp <= deadline).
        vm.expectRevert();
        harness.expire(id);
    }

    /// Cannot expire an already completed action.
    function testCannotExpireCompleted() external {
        uint64 effectiveTime = uint64(block.timestamp + 1 days);
        uint256 id = harness.schedule(ACTION_TYPE, effectiveTime, "");

        vm.warp(effectiveTime);
        harness.beginExecution(id);
        harness.completeExecution(id);

        vm.warp(effectiveTime + EXECUTION_WINDOW + 1);
        vm.expectRevert(abi.encodeWithSelector(ActionNotScheduled.selector, id, STATUS_COMPLETE));
        harness.expire(id);
    }
}

contract LibCorporateActionQueryTest is Test {
    LibCorporateActionHarness harness;

    function setUp() external {
        harness = new LibCorporateActionHarness();
    }

    /// Querying action ID 0 reverts.
    function testGetActionZeroReverts() external {
        vm.expectRevert(abi.encodeWithSelector(ActionDoesNotExist.selector, 0));
        harness.getAction(0);
    }

    /// Querying a non-existent action ID reverts.
    function testGetActionNonExistentReverts() external {
        vm.expectRevert(abi.encodeWithSelector(ActionDoesNotExist.selector, 1));
        harness.getAction(1);
    }

    /// Fuzz: querying any ID beyond nextActionId reverts.
    function testFuzzGetActionBoundsCheck(uint256 queryId) external {
        // Schedule one action so nextActionId = 1.
        harness.schedule(keccak256("TEST"), uint64(block.timestamp + 1 days), "");

        if (queryId == 0 || queryId > 1) {
            vm.expectRevert(abi.encodeWithSelector(ActionDoesNotExist.selector, queryId));
            harness.getAction(queryId);
        } else {
            // queryId == 1 should succeed.
            harness.getAction(queryId);
        }
    }
}

contract LibCorporateActionRebaseTest is Test {
    LibCorporateActionHarness harness;
    bytes32 constant ACTION_TYPE = keccak256("STOCK_SPLIT");

    function setUp() external {
        harness = new LibCorporateActionHarness();
    }

    /// Rebase count starts at 0.
    function testRebaseCountStartsAtZero() external view {
        assertEq(harness.rebaseCount(), 0);
    }

    /// completeExecutionWithMultiplier increments both CAID and rebase count.
    function testRebaseCountIncrements() external {
        uint64 future = uint64(block.timestamp + 1 days);
        uint256 id = harness.schedule(ACTION_TYPE, future, "");
        vm.warp(future);

        harness.beginExecution(id);
        Float multiplier = LibDecimalFloat.packLossless(2, 0);
        harness.completeExecutionWithMultiplier(id, multiplier);

        assertEq(harness.globalCAID(), 1);
        assertEq(harness.rebaseCount(), 1);
    }

    /// completeExecution (without multiplier) increments CAID but NOT rebase
    /// count. This is how non-balance-affecting actions work.
    function testNonRebaseActionDoesNotIncrementRebaseCount() external {
        uint64 future = uint64(block.timestamp + 1 days);
        uint256 id = harness.schedule(ACTION_TYPE, future, "");
        vm.warp(future);

        harness.beginExecution(id);
        harness.completeExecution(id);

        assertEq(harness.globalCAID(), 1);
        assertEq(harness.rebaseCount(), 0);
    }

    /// Multiplier is stored and retrievable by rebase ID.
    function testGetMultiplier() external {
        uint64 future = uint64(block.timestamp + 1 days);
        uint256 id = harness.schedule(ACTION_TYPE, future, "");
        vm.warp(future);

        harness.beginExecution(id);
        Float multiplier = LibDecimalFloat.packLossless(3, 0);
        harness.completeExecutionWithMultiplier(id, multiplier);

        Float stored = harness.getMultiplier(1);
        assertTrue(LibDecimalFloat.eq(stored, multiplier));
    }

    /// Querying rebase ID 0 reverts.
    function testGetMultiplierZeroReverts() external {
        vm.expectRevert(abi.encodeWithSelector(RebaseDoesNotExist.selector, 0));
        harness.getMultiplier(0);
    }

    /// Querying a non-existent rebase ID reverts.
    function testGetMultiplierNonExistentReverts() external {
        vm.expectRevert(abi.encodeWithSelector(RebaseDoesNotExist.selector, 1));
        harness.getMultiplier(1);
    }

    /// Multiple rebases produce sequential rebase IDs with correct multipliers.
    function testMultipleRebases() external {
        uint64 future = uint64(block.timestamp + 1 days);
        Float twoX = LibDecimalFloat.packLossless(2, 0);
        Float halfX = LibDecimalFloat.packLossless(5, -1);

        uint256 id1 = harness.schedule(ACTION_TYPE, future, "");
        uint256 id2 = harness.schedule(ACTION_TYPE, future, "");

        vm.warp(future);

        harness.beginExecution(id1);
        harness.completeExecutionWithMultiplier(id1, twoX);

        harness.beginExecution(id2);
        harness.completeExecutionWithMultiplier(id2, halfX);

        assertEq(harness.rebaseCount(), 2);
        assertTrue(LibDecimalFloat.eq(harness.getMultiplier(1), twoX));
        assertTrue(LibDecimalFloat.eq(harness.getMultiplier(2), halfX));
    }

    /// Fuzz: rebase IDs beyond rebaseCount revert.
    function testFuzzGetMultiplierBoundsCheck(uint256 queryId) external {
        // Create one rebase.
        uint64 future = uint64(block.timestamp + 1 days);
        uint256 id = harness.schedule(ACTION_TYPE, future, "");
        vm.warp(future);
        harness.beginExecution(id);
        harness.completeExecutionWithMultiplier(id, LibDecimalFloat.packLossless(2, 0));

        if (queryId == 0 || queryId > 1) {
            vm.expectRevert(abi.encodeWithSelector(RebaseDoesNotExist.selector, queryId));
            harness.getMultiplier(queryId);
        } else {
            harness.getMultiplier(queryId);
        }
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {ICorporateActionsV1} from "../../../src/interface/ICorporateActionsV1.sol";
import {
    LibCorporateAction,
    CorporateActionNode,
    CORPORATE_ACTION_STORAGE_LOCATION,
    SCHEDULE_CORPORATE_ACTION,
    CANCEL_CORPORATE_ACTION,
    STATUS_SCHEDULED,
    STATUS_COMPLETE,
    ACTION_TYPE_STOCK_SPLIT,
    EffectiveTimeInPast,
    NotScheduled,
    NodeDoesNotExist,
    RebaseDoesNotExist,
    MonotonicIdDoesNotExist,
    UnknownActionType,
    ZeroMultiplier
} from "../../../src/lib/LibCorporateAction.sol";
import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";

/// @dev Minimal harness that delegates calls to a facet, simulating how the
/// vault would route unknown selectors via its fallback.
contract DelegatecallHarness {
    address public immutable facet;

    constructor(address facet_) {
        facet = facet_;
    }

    fallback() external payable {
        address target = facet;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), target, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch success
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}

/// @dev Thin harness that exposes LibCorporateAction functions directly for
/// unit testing without needing authorization.
contract LibCorporateActionHarness {
    using LibDecimalFloat for Float;

    function schedule(uint256 actionType, uint64 effectiveTime, bytes calldata parameters) external returns (uint256) {
        return LibCorporateAction.schedule(actionType, effectiveTime, parameters);
    }

    function cancel(uint256 nodeId) external {
        LibCorporateAction.cancel(nodeId);
    }

    function processCompletions() external {
        LibCorporateAction.processCompletions();
    }

    function getNode(uint256 nodeId) external view returns (CorporateActionNode memory) {
        CorporateActionNode storage node = LibCorporateAction.getNode(nodeId);
        return node;
    }

    function getActionByMonotonicId(uint256 monotonicId) external view returns (CorporateActionNode memory) {
        CorporateActionNode storage node = LibCorporateAction.getActionByMonotonicId(monotonicId);
        return node;
    }

    function getMultiplier(uint256 rebaseId) external view returns (Float) {
        return LibCorporateAction.getMultiplier(rebaseId);
    }

    function getPendingActions(uint256 mask, uint256 maxResults) external view returns (uint256[] memory) {
        return LibCorporateAction.getPendingActions(mask, maxResults);
    }

    function getRecentAction(uint256 mask) external view returns (uint256) {
        return LibCorporateAction.getRecentAction(mask);
    }

    function globalCAID() external view returns (uint256) {
        return LibCorporateAction.getStorage().globalCAID;
    }

    function rebaseCount() external view returns (uint256) {
        return LibCorporateAction.getStorage().rebaseCount;
    }

    function head() external view returns (uint256) {
        return LibCorporateAction.getStorage().head;
    }

    function tail() external view returns (uint256) {
        return LibCorporateAction.getStorage().tail;
    }
}

contract StoxCorporateActionsFacetTest is Test {
    StoxCorporateActionsFacet internal facetImpl;
    DelegatecallHarness internal harness;
    ICorporateActionsV1 internal facetViaHarness;

    function setUp() public {
        facetImpl = new StoxCorporateActionsFacet();
        harness = new DelegatecallHarness(address(facetImpl));
        facetViaHarness = ICorporateActionsV1(address(harness));
    }

    /// globalCAID() returns 0 on a fresh deployment.
    function testGlobalCAIDInitiallyZero() external view {
        assertEq(facetViaHarness.globalCAID(), 0);
    }

    /// Facet routing: calling globalCAID() via delegatecall harness works.
    function testFacetRoutingViaDelegatecall() external view {
        uint256 caid = facetViaHarness.globalCAID();
        assertEq(caid, 0);
    }

    /// Storage isolation: two harnesses sharing the same facet have independent storage.
    function testStorageIsolationBetweenHarnesses() external {
        DelegatecallHarness harness2 = new DelegatecallHarness(address(facetImpl));
        ICorporateActionsV1 facet2 = ICorporateActionsV1(address(harness2));

        assertEq(facetViaHarness.globalCAID(), 0);
        assertEq(facet2.globalCAID(), 0);

        bytes32 storageSlot = CORPORATE_ACTION_STORAGE_LOCATION;
        vm.store(address(harness), storageSlot, bytes32(uint256(42)));

        assertEq(facetViaHarness.globalCAID(), 42);
        assertEq(facet2.globalCAID(), 0);
    }

    /// ERC-7201 storage slot matches the documented formula.
    function testStorageSlotCalculation() external pure {
        bytes32 expected =
            keccak256(abi.encode(uint256(keccak256("rain.storage.corporate-action.1")) - 1)) & ~bytes32(uint256(0xff));
        assertEq(CORPORATE_ACTION_STORAGE_LOCATION, expected);
    }

    /// Auth permission constants are correct keccak256 hashes.
    function testAuthPermissionConstants() external pure {
        assertEq(SCHEDULE_CORPORATE_ACTION, keccak256("SCHEDULE_CORPORATE_ACTION"));
        assertEq(CANCEL_CORPORATE_ACTION, keccak256("CANCEL_CORPORATE_ACTION"));
    }
}

contract LibCorporateActionLinkedListTest is Test {
    using LibDecimalFloat for Float;

    LibCorporateActionHarness internal lib;

    /// Encode a stock split multiplier (e.g. 3x).
    function encodeSplitParams(int256 coefficient, int256 exponent) internal pure returns (bytes memory) {
        return abi.encode(LibDecimalFloat.packLossless(coefficient, exponent));
    }

    function setUp() public {
        lib = new LibCorporateActionHarness();
        vm.warp(1000);
    }

    /// Scheduling a single action creates a one-element list.
    function testScheduleSingleAction() external {
        uint256 nodeId = lib.schedule(ACTION_TYPE_STOCK_SPLIT, 2000, encodeSplitParams(3, 0));
        assertEq(nodeId, 1);
        assertEq(lib.head(), 1);
        assertEq(lib.tail(), 1);

        CorporateActionNode memory node = lib.getNode(1);
        assertEq(node.actionType, ACTION_TYPE_STOCK_SPLIT);
        assertEq(node.effectiveTime, 2000);
        assertEq(node.status, STATUS_SCHEDULED);
        assertEq(node.monotonicId, 0);
    }

    /// Scheduling with effectiveTime in the past reverts.
    function testScheduleInPastReverts() external {
        vm.expectRevert(abi.encodeWithSelector(EffectiveTimeInPast.selector, 500, 1000));
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 500, encodeSplitParams(3, 0));
    }

    /// Scheduling with effectiveTime == block.timestamp reverts.
    function testScheduleAtCurrentTimeReverts() external {
        vm.expectRevert(abi.encodeWithSelector(EffectiveTimeInPast.selector, 1000, 1000));
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 1000, encodeSplitParams(3, 0));
    }

    /// Scheduling an unknown action type reverts.
    function testScheduleUnknownActionTypeReverts() external {
        vm.expectRevert(abi.encodeWithSelector(UnknownActionType.selector, 1 << 5));
        lib.schedule(1 << 5, 2000, "");
    }

    /// Scheduling a zero multiplier stock split reverts.
    function testScheduleZeroMultiplierReverts() external {
        vm.expectRevert(abi.encodeWithSelector(ZeroMultiplier.selector));
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 2000, abi.encode(LibDecimalFloat.FLOAT_ZERO));
    }

    /// Insertion at tail (chronological order).
    function testInsertionAtTail() external {
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 2000, encodeSplitParams(2, 0));
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 3000, encodeSplitParams(2, 0));
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 4000, encodeSplitParams(2, 0));

        assertEq(lib.head(), 1);
        assertEq(lib.tail(), 3);

        CorporateActionNode memory n1 = lib.getNode(1);
        CorporateActionNode memory n2 = lib.getNode(2);
        CorporateActionNode memory n3 = lib.getNode(3);

        assertEq(n1.prev, 0);
        assertEq(n1.next, 2);
        assertEq(n2.prev, 1);
        assertEq(n2.next, 3);
        assertEq(n3.prev, 2);
        assertEq(n3.next, 0);
    }

    /// Insertion at head (reverse chronological order).
    function testInsertionAtHead() external {
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 4000, encodeSplitParams(2, 0));
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 3000, encodeSplitParams(2, 0));
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 2000, encodeSplitParams(2, 0));

        assertEq(lib.head(), 3);
        assertEq(lib.tail(), 1);

        CorporateActionNode memory n3 = lib.getNode(3);
        CorporateActionNode memory n2 = lib.getNode(2);
        CorporateActionNode memory n1 = lib.getNode(1);

        assertEq(n3.prev, 0);
        assertEq(n3.next, 2);
        assertEq(n2.prev, 3);
        assertEq(n2.next, 1);
        assertEq(n1.prev, 2);
        assertEq(n1.next, 0);
    }

    /// Insertion in the middle.
    function testInsertionInMiddle() external {
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 2000, encodeSplitParams(2, 0));
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 4000, encodeSplitParams(2, 0));
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 3000, encodeSplitParams(2, 0));

        CorporateActionNode memory n1 = lib.getNode(1);
        CorporateActionNode memory n3 = lib.getNode(3);
        CorporateActionNode memory n2 = lib.getNode(2);

        assertEq(n1.next, 3);
        assertEq(n3.prev, 1);
        assertEq(n3.next, 2);
        assertEq(n2.prev, 3);
    }

    /// Same effectiveTime inserts after existing (stable insertion).
    function testSameEffectiveTimeInsertsAfter() external {
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 2000, encodeSplitParams(2, 0));
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 2000, encodeSplitParams(3, 0));

        assertEq(lib.head(), 1);
        assertEq(lib.tail(), 2);
    }

    /// Cancellation of a single-node list empties the list.
    function testCancelSingleNode() external {
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 2000, encodeSplitParams(2, 0));
        lib.cancel(1);
        assertEq(lib.head(), 0);
        assertEq(lib.tail(), 0);
    }

    /// Cancelling the head updates head pointer.
    function testCancelHead() external {
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 2000, encodeSplitParams(2, 0));
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 3000, encodeSplitParams(2, 0));
        lib.cancel(1);
        assertEq(lib.head(), 2);
        assertEq(lib.tail(), 2);
    }

    /// Cancelling the tail updates tail pointer.
    function testCancelTail() external {
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 2000, encodeSplitParams(2, 0));
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 3000, encodeSplitParams(2, 0));
        lib.cancel(2);
        assertEq(lib.head(), 1);
        assertEq(lib.tail(), 1);
    }

    /// Cancelling a middle node updates prev/next pointers.
    function testCancelMiddle() external {
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 2000, encodeSplitParams(2, 0));
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 3000, encodeSplitParams(2, 0));
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 4000, encodeSplitParams(2, 0));
        lib.cancel(2);

        CorporateActionNode memory n1 = lib.getNode(1);
        CorporateActionNode memory n3 = lib.getNode(3);
        assertEq(n1.next, 3);
        assertEq(n3.prev, 1);
    }

    /// Cannot cancel a completed action.
    function testCannotCancelCompleted() external {
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, encodeSplitParams(2, 0));
        vm.warp(2000);
        lib.processCompletions();
        vm.expectRevert(abi.encodeWithSelector(NotScheduled.selector, 1, STATUS_COMPLETE));
        lib.cancel(1);
    }

    /// Automatic completion assigns monotonic IDs and records multipliers.
    function testAutomaticCompletion() external {
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, encodeSplitParams(3, 0));
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 1800, encodeSplitParams(2, 0));

        vm.warp(2000);
        lib.processCompletions();

        CorporateActionNode memory n1 = lib.getNode(1);
        CorporateActionNode memory n2 = lib.getNode(2);

        assertEq(n1.status, STATUS_COMPLETE);
        assertEq(n1.monotonicId, 1);
        assertEq(n2.status, STATUS_COMPLETE);
        assertEq(n2.monotonicId, 2);
        assertEq(lib.globalCAID(), 2);
        assertEq(lib.rebaseCount(), 2);

        // Verify multipliers were stored.
        Float m1 = lib.getMultiplier(1);
        Float m2 = lib.getMultiplier(2);
        (int256 c1,) = m1.unpack();
        (int256 c2,) = m2.unpack();
        assertEq(c1, 3);
        assertEq(c2, 2);
    }

    /// Only actions past effectiveTime complete; future ones stay scheduled.
    function testPartialCompletion() external {
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, encodeSplitParams(3, 0));
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 3000, encodeSplitParams(2, 0));

        vm.warp(2000);
        lib.processCompletions();

        CorporateActionNode memory n1 = lib.getNode(1);
        CorporateActionNode memory n2 = lib.getNode(2);

        assertEq(n1.status, STATUS_COMPLETE);
        assertEq(n2.status, STATUS_SCHEDULED);
        assertEq(lib.globalCAID(), 1);
        assertEq(lib.rebaseCount(), 1);
    }

    /// Querying a non-existent node reverts.
    function testGetNodeNonExistentReverts() external {
        vm.expectRevert(abi.encodeWithSelector(NodeDoesNotExist.selector, 0));
        lib.getNode(0);
    }

    /// Querying a non-existent rebase ID reverts.
    function testGetMultiplierNonExistentReverts() external {
        vm.expectRevert(abi.encodeWithSelector(RebaseDoesNotExist.selector, 1));
        lib.getMultiplier(1);
    }

    /// Querying a non-existent monotonic ID reverts.
    function testGetActionByMonotonicIdNonExistentReverts() external {
        vm.expectRevert(abi.encodeWithSelector(MonotonicIdDoesNotExist.selector, 1));
        lib.getActionByMonotonicId(1);
    }

    /// getActionByMonotonicId returns the correct node.
    function testGetActionByMonotonicId() external {
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, encodeSplitParams(3, 0));
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 1800, encodeSplitParams(7, 0));

        vm.warp(2000);
        lib.processCompletions();

        CorporateActionNode memory action1 = lib.getActionByMonotonicId(1);
        CorporateActionNode memory action2 = lib.getActionByMonotonicId(2);

        assertEq(action1.effectiveTime, 1500);
        assertEq(action2.effectiveTime, 1800);
    }

    /// getPendingActions returns only scheduled actions matching the mask.
    function testGetPendingActions() external {
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 2000, encodeSplitParams(2, 0));
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 3000, encodeSplitParams(3, 0));

        uint256[] memory pending = lib.getPendingActions(ACTION_TYPE_STOCK_SPLIT, 10);
        assertEq(pending.length, 2);
        // Most recent first (from tail backwards).
        assertEq(pending[0], 2);
        assertEq(pending[1], 1);
    }

    /// getPendingActions with zero mask returns empty.
    function testGetPendingActionsZeroMask() external {
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 2000, encodeSplitParams(2, 0));

        uint256[] memory pending = lib.getPendingActions(0, 10);
        assertEq(pending.length, 0);
    }

    /// getPendingActions with non-matching mask returns empty.
    function testGetPendingActionsNonMatchingMask() external {
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 2000, encodeSplitParams(2, 0));

        // Use a different bit that doesn't match stock split.
        uint256[] memory pending = lib.getPendingActions(1 << 1, 10);
        assertEq(pending.length, 0);
    }

    /// getPendingActions excludes completed actions.
    function testGetPendingActionsExcludesCompleted() external {
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, encodeSplitParams(2, 0));
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 3000, encodeSplitParams(3, 0));

        vm.warp(2000);
        lib.processCompletions();

        uint256[] memory pending = lib.getPendingActions(ACTION_TYPE_STOCK_SPLIT, 10);
        assertEq(pending.length, 1);
        assertEq(pending[0], 2);
    }

    /// getRecentAction returns the most recently completed matching action.
    function testGetRecentAction() external {
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, encodeSplitParams(2, 0));
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 1800, encodeSplitParams(3, 0));

        vm.warp(2000);
        lib.processCompletions();

        uint256 recent = lib.getRecentAction(ACTION_TYPE_STOCK_SPLIT);
        assertEq(recent, 2);
    }

    /// getRecentAction returns 0 when no matches.
    function testGetRecentActionNoMatches() external {
        uint256 recent = lib.getRecentAction(ACTION_TYPE_STOCK_SPLIT);
        assertEq(recent, 0);
    }

    /// Stock split lifecycle: schedule -> complete -> query multiplier.
    function testStockSplitFullLifecycle() external {
        // Schedule a 3x split.
        Float threeX = LibDecimalFloat.packLossless(3, 0);
        uint256 nodeId = lib.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, abi.encode(threeX));
        assertEq(nodeId, 1);

        // Not yet effective.
        assertEq(lib.rebaseCount(), 0);

        // Advance time past effectiveTime.
        vm.warp(2000);
        lib.processCompletions();

        // Verify completion.
        assertEq(lib.globalCAID(), 1);
        assertEq(lib.rebaseCount(), 1);

        // Verify multiplier retrieval.
        Float stored = lib.getMultiplier(1);
        assertEq(Float.unwrap(stored), Float.unwrap(threeX));
    }

    /// Fuzz: random insertion sequences always maintain time ordering.
    function testFuzzInsertionOrdering(uint8 count, uint256 seed) external {
        count = uint8(bound(count, 1, 20));
        bytes memory params = encodeSplitParams(2, 0);

        for (uint256 i = 0; i < count; i++) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint64 time = uint64(bound(seed, 1001, type(uint64).max));
            lib.schedule(ACTION_TYPE_STOCK_SPLIT, time, params);
        }

        uint256 current = lib.head();
        uint64 prevTime = 0;
        uint256 nodeCount = 0;
        while (current != 0) {
            CorporateActionNode memory node = lib.getNode(current);
            assertGe(node.effectiveTime, prevTime, "list not time-ordered");
            prevTime = node.effectiveTime;
            current = node.next;
            nodeCount++;
        }
        assertEq(nodeCount, count, "node count mismatch");
    }

    /// Fuzz: monotonic ID assignment is sequential and gap-free.
    function testFuzzMonotonicIdSequential(uint8 count, uint256 seed) external {
        count = uint8(bound(count, 1, 15));
        bytes memory params = encodeSplitParams(2, 0);

        for (uint256 i = 0; i < count; i++) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint64 time = uint64(bound(seed, 1001, 5000));
            lib.schedule(ACTION_TYPE_STOCK_SPLIT, time, params);
        }

        // Complete all.
        vm.warp(6000);
        lib.processCompletions();

        assertEq(lib.globalCAID(), count);
        assertEq(lib.rebaseCount(), count);

        // Verify sequential monotonic IDs.
        for (uint256 i = 1; i <= count; i++) {
            CorporateActionNode memory action = lib.getActionByMonotonicId(i);
            assertEq(action.monotonicId, i);
            assertEq(action.status, STATUS_COMPLETE);
        }
    }

    /// Fuzz: bitmap filtering correctness.
    function testFuzzBitmapFiltering(uint256 mask) external {
        // Schedule some stock splits.
        bytes memory params = encodeSplitParams(2, 0);
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 2000, params);
        lib.schedule(ACTION_TYPE_STOCK_SPLIT, 3000, params);

        uint256[] memory pending = lib.getPendingActions(mask, 10);

        if (mask & ACTION_TYPE_STOCK_SPLIT != 0) {
            assertEq(pending.length, 2);
        } else {
            assertEq(pending.length, 0);
        }
    }
}

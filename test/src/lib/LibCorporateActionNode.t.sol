// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibCorporateAction} from "src/lib/LibCorporateAction.sol";
import {
    ACTION_TYPE_INIT_V1,
    ACTION_TYPE_STOCK_SPLIT_V1,
    ACTION_TYPE_STABLES_DIVIDEND_V1,
    VALID_ACTION_TYPES_MASK
} from "src/interface/ICorporateActionsV1.sol";

import {
    CompletionFilter,
    CorporateActionNode,
    LibCorporateActionNode,
    NODE_NONE
} from "src/lib/LibCorporateActionNode.sol";
import {InvalidMask} from "src/error/ErrCorporateAction.sol";

/// @dev Mask covering every test-scheduled action type — `STOCK_SPLIT_V1` and
/// `STABLES_DIVIDEND_V1` — without the bootstrap `ACTION_TYPE_INIT_V1` bit.
/// These tests exercise pure linked-list traversal over user-scheduled
/// nodes; including INIT in the mask would surface the bootstrap node at
/// idx 1, which is implementation detail of `LibCorporateAction.schedule`
/// rather than the traversal API being tested. The lifecycle /
/// effective-supply tests in `LibTotalSupply.t.sol` and `LibRebase.t.sol`
/// do exercise the bootstrap node via `BALANCE_MIGRATION_TYPES_MASK`.
uint256 constant USER_TYPES_TEST_MASK = ACTION_TYPE_STOCK_SPLIT_V1 | ACTION_TYPE_STABLES_DIVIDEND_V1;

/// @dev Thin harness: exposes the four tuple-returning traversal getters via
/// external calls so the library functions can be exercised directly (not
/// through the facet). Also schedules actions into the harness's own storage
/// namespace so there is no ambient state between tests.
contract TraversalHarness {
    function schedule(uint256 actionType, uint64 effectiveTime, bytes memory parameters) external returns (uint256) {
        return LibCorporateAction.schedule(actionType, effectiveTime, parameters);
    }

    function cancel(uint256 actionIndex) external {
        LibCorporateAction.cancel(actionIndex);
    }

    function latest(uint256 mask, CompletionFilter filter)
        external
        view
        returns (uint256 cursor, uint256 actionType, uint64 effectiveTime)
    {
        return LibCorporateActionNode.latestActionOfType(mask, filter);
    }

    function earliest(uint256 mask, CompletionFilter filter)
        external
        view
        returns (uint256 cursor, uint256 actionType, uint64 effectiveTime)
    {
        return LibCorporateActionNode.earliestActionOfType(mask, filter);
    }

    function nextOf(uint256 cursor, uint256 mask, CompletionFilter filter)
        external
        view
        returns (uint256 nextCursor, uint256 actionType, uint64 effectiveTime)
    {
        return LibCorporateActionNode.nextActionOfType(cursor, mask, filter);
    }

    function prevOf(uint256 cursor, uint256 mask, CompletionFilter filter)
        external
        view
        returns (uint256 prevCursor, uint256 actionType, uint64 effectiveTime)
    {
        return LibCorporateActionNode.prevActionOfType(cursor, mask, filter);
    }

    function nodeAt(uint256 index) external view returns (uint256 actionType, uint64 effectiveTime) {
        CorporateActionNode storage node = LibCorporateAction.getStorage().nodes[index];
        actionType = node.actionType;
        effectiveTime = node.effectiveTime;
    }
}

contract LibCorporateActionNodeTest is Test {
    TraversalHarness internal h;

    function setUp() public {
        h = new TraversalHarness();
        vm.warp(1000);
    }

    /// Empty list: every tuple-returning getter returns all zeros regardless
    /// of the mask or filter. Exercises the `cursor == 0` short-circuit in
    /// the `_resolve` helper.
    function testEmptyListReturnsZeros() external view {
        (uint256 c1, uint256 t1, uint64 e1) = h.latest(USER_TYPES_TEST_MASK, CompletionFilter.ALL);
        assertEq(c1, NODE_NONE);
        assertEq(t1, 0);
        assertEq(e1, 0);

        (uint256 c2, uint256 t2, uint64 e2) = h.earliest(USER_TYPES_TEST_MASK, CompletionFilter.ALL);
        assertEq(c2, NODE_NONE);
        assertEq(t2, 0);
        assertEq(e2, 0);

        (uint256 c3, uint256 t3, uint64 e3) = h.nextOf(NODE_NONE, USER_TYPES_TEST_MASK, CompletionFilter.ALL);
        assertEq(c3, NODE_NONE);
        assertEq(t3, 0);
        assertEq(e3, 0);

        (uint256 c4, uint256 t4, uint64 e4) = h.prevOf(NODE_NONE, USER_TYPES_TEST_MASK, CompletionFilter.ALL);
        assertEq(c4, NODE_NONE);
        assertEq(t4, 0);
        assertEq(e4, 0);
    }

    /// Single pending node: `earliest` and `latest` both resolve to it with the
    /// matching mask and ALL / PENDING filters. COMPLETED filter returns zeros
    /// because the single node has not reached effective time.
    function testSingleNodeResolution() external {
        uint256 id = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");

        (uint256 cursor, uint256 actionType, uint64 effectiveTime) =
            h.latest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL);
        assertEq(cursor, id);
        assertEq(actionType, ACTION_TYPE_STOCK_SPLIT_V1);
        assertEq(effectiveTime, 1500);

        (cursor, actionType, effectiveTime) = h.earliest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL);
        assertEq(cursor, id);
        assertEq(actionType, ACTION_TYPE_STOCK_SPLIT_V1);
        assertEq(effectiveTime, 1500);

        // Pending filter also matches (effectiveTime > now).
        (cursor,,) = h.latest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(cursor, id);

        // Completed filter does NOT match yet.
        (cursor,,) = h.latest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
        assertEq(cursor, NODE_NONE);
    }

    /// Mask = 0 can never match any node (every node's `actionType` has at
    /// least one bit set, so `actionType & 0 == 0` for every node). The
    /// traversal primitives revert with `InvalidMask` so a caller bug
    /// surfaces rather than being silently conflated with an empty-list
    /// "no match" result.
    function testMaskZeroReverts() external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");

        vm.expectRevert(InvalidMask.selector);
        h.latest(0, CompletionFilter.ALL);

        vm.expectRevert(InvalidMask.selector);
        h.earliest(0, CompletionFilter.ALL);

        vm.expectRevert(InvalidMask.selector);
        h.nextOf(0, 0, CompletionFilter.ALL);

        vm.expectRevert(InvalidMask.selector);
        h.prevOf(0, 0, CompletionFilter.ALL);
    }

    /// Masks with only undefined bits reference no known action type.
    /// `mask & VALID_ACTION_TYPES_MASK == 0` for these, so the traversal
    /// reverts. Mixed masks (valid + undefined bits) pass — the valid bit
    /// matches, and undefined bits contribute nothing because no node's
    /// `actionType` has them set. The permissive handling of mixed masks
    /// is intentional: a caller written against a future version that
    /// adds new types still works against the current deployment.
    function testMaskWithOnlyUndefinedBitsReverts() external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");

        // Bit 3 alone — no action type uses bit 3 today (defined types
        // occupy bits 0/1/2).
        vm.expectRevert(InvalidMask.selector);
        h.latest(1 << 3, CompletionFilter.ALL);

        // Bits 3 and 4 — both undefined.
        vm.expectRevert(InvalidMask.selector);
        h.latest((1 << 3) | (1 << 4), CompletionFilter.ALL);
    }

    /// Fuzz: any mask with no valid bits (i.e. `mask & VALID_ACTION_TYPES_MASK
    /// == 0`) reverts with `InvalidMask`, regardless of list state. Generated
    /// masks are forced into the invalid-only space by ANDing with the
    /// complement of the valid mask; the result is either 0 (mask=0) or a
    /// purely-undefined bitfield, both of which must revert.
    function testFuzzMaskWithNoValidBitsAlwaysReverts(uint256 rawMask) external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");

        uint256 mask = rawMask & ~VALID_ACTION_TYPES_MASK;

        vm.expectRevert(InvalidMask.selector);
        h.latest(mask, CompletionFilter.ALL);

        vm.expectRevert(InvalidMask.selector);
        h.earliest(mask, CompletionFilter.ALL);

        vm.expectRevert(InvalidMask.selector);
        h.nextOf(0, mask, CompletionFilter.ALL);

        vm.expectRevert(InvalidMask.selector);
        h.prevOf(0, mask, CompletionFilter.ALL);
    }

    /// Fuzz: any mask containing at least one valid bit passes the guard.
    /// Force the `VALID_ACTION_TYPES_MASK` bits to be set, add arbitrary
    /// undefined bits on top, and assert all four getters succeed (i.e.
    /// do not revert on the guard). The returned cursor may still be zero
    /// if filters don't match — but reaching that return means the mask
    /// check passed.
    function testFuzzMaskWithAtLeastOneValidBitPasses(uint256 extraBits) external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");

        uint256 mask = VALID_ACTION_TYPES_MASK | extraBits;

        // None of these should revert on the InvalidMask guard.
        h.latest(mask, CompletionFilter.ALL);
        h.earliest(mask, CompletionFilter.ALL);
        h.nextOf(0, mask, CompletionFilter.ALL);
        h.prevOf(0, mask, CompletionFilter.ALL);
    }

    /// Mixed masks that include at least one valid bit pass and match on
    /// the valid portion. The undefined bits contribute nothing since no
    /// node has them set.
    function testMaskWithMixedBitsPasses() external {
        uint256 id = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");

        // Stock split bit (valid) + bit 3 (undefined).
        (uint256 cursor,,) = h.latest(ACTION_TYPE_STOCK_SPLIT_V1 | (1 << 3), CompletionFilter.ALL);
        assertEq(cursor, id, "valid bit in mask matches node with that bit set");

        // USER_TYPES_TEST_MASK includes the stock-split bit.
        (cursor,,) = h.latest(USER_TYPES_TEST_MASK, CompletionFilter.ALL);
        assertEq(cursor, id, "user-types mask matches via its valid bits");
    }

    /// With two defined action types (stock split and stables dividend),
    /// masks select between them: mask = stock split only matches the
    /// stock-split node, mask = dividend only matches the dividend node,
    /// and the union mask matches both.
    function testMaskSelectsBetweenDefinedTypes() external {
        uint256 splitId = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");
        uint256 divId = h.schedule(ACTION_TYPE_STABLES_DIVIDEND_V1, 2500, hex"");

        // mask = stock split only.
        (uint256 cursor, uint256 actionType,) = h.earliest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL);
        assertEq(cursor, splitId);
        assertEq(actionType, ACTION_TYPE_STOCK_SPLIT_V1);

        (cursor, actionType,) = h.latest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL);
        assertEq(cursor, splitId, "latest with split-only mask skips dividend tail");

        // mask = dividend only.
        (cursor, actionType,) = h.earliest(ACTION_TYPE_STABLES_DIVIDEND_V1, CompletionFilter.ALL);
        assertEq(cursor, divId, "earliest with dividend-only mask skips split head");
        assertEq(actionType, ACTION_TYPE_STABLES_DIVIDEND_V1);

        (cursor,,) = h.latest(ACTION_TYPE_STABLES_DIVIDEND_V1, CompletionFilter.ALL);
        assertEq(cursor, divId);

        // mask = union finds both; order determined by walk direction.
        uint256 both = ACTION_TYPE_STOCK_SPLIT_V1 | ACTION_TYPE_STABLES_DIVIDEND_V1;
        (cursor,,) = h.earliest(both, CompletionFilter.ALL);
        assertEq(cursor, splitId, "walking forward from head, split comes first");
        (cursor,,) = h.latest(both, CompletionFilter.ALL);
        assertEq(cursor, divId, "walking backward from tail, dividend comes first");
    }

    /// Pending/completed filter moves the result as time passes. Schedule two
    /// nodes at different effective times; before either completes all
    /// matches are PENDING, after the first completes `latest(COMPLETED)`
    /// resolves to it and `earliest(PENDING)` advances to the remaining one.
    function testFilterTracksEffectiveTimeTransitions() external {
        uint256 id1 = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");
        uint256 id2 = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, hex"");

        // Pre-1500: both pending.
        (uint256 cursor,,) = h.latest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
        assertEq(cursor, NODE_NONE);
        (cursor,,) = h.earliest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(cursor, id1);

        // Warp past id1's effective time only.
        vm.warp(2000);

        (cursor,,) = h.latest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
        assertEq(cursor, id1, "only id1 has completed");
        (cursor,,) = h.earliest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(cursor, id2, "only id2 still pending");

        // Warp past both.
        vm.warp(3000);
        (cursor,,) = h.latest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
        assertEq(cursor, id2, "tail becomes latest completed");
        (cursor,,) = h.earliest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(cursor, NODE_NONE, "no pending actions remain");
    }

    /// After a middle node is cancelled, traversal re-links the list so
    /// `nextActionOfType` skips the cancelled cursor and `prevActionOfType`
    /// from the tail no longer touches it. Pins the linked-list integrity
    /// under cancellation through the traversal API surface.
    function testCancelMiddleNodeRelinksTraversal() external {
        uint256 id1 = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");
        uint256 id2 = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, hex"");
        uint256 id3 = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 3500, hex"");

        h.cancel(id2);

        // nextActionOfType from id1 now skips past id2 to id3.
        (uint256 cursor,,) = h.nextOf(id1, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL);
        assertEq(cursor, id3, "next(id1) must skip cancelled id2");

        // prevActionOfType from id3 now skips id2 back to id1.
        (cursor,,) = h.prevOf(id3, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL);
        assertEq(cursor, id1, "prev(id3) must skip cancelled id2");

        // earliest + latest remain unchanged — id2 was never at either end.
        (cursor,,) = h.earliest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL);
        assertEq(cursor, id1, "earliest is still id1");
        (cursor,,) = h.latest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL);
        assertEq(cursor, id3, "latest is still id3");
    }

    /// Cancelling the head advances `earliestActionOfType` to the next node.
    /// Verifies the head pointer updates and traversal from the new head
    /// works.
    function testCancelHeadAdvancesEarliest() external {
        uint256 id1 = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");
        uint256 id2 = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, hex"");

        h.cancel(id1);

        (uint256 cursor,,) = h.earliest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL);
        assertEq(cursor, id2, "earliest advances to id2 after id1 cancelled");

        // Walking prev from the new earliest returns 0 (head has no prev).
        (cursor,,) = h.prevOf(id2, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL);
        assertEq(cursor, NODE_NONE, "prev of new head is 0");
    }

    /// Cancelling the tail moves `latestActionOfType` back to the prior node.
    /// Verifies the tail pointer updates.
    function testCancelTailRetreatsLatest() external {
        uint256 id1 = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");
        uint256 id2 = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, hex"");

        h.cancel(id2);

        (uint256 cursor,,) = h.latest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL);
        assertEq(cursor, id1, "latest retreats to id1 after id2 cancelled");

        (cursor,,) = h.nextOf(id1, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL);
        assertEq(cursor, NODE_NONE, "next of new tail is 0");
    }

    /// `nextActionOfType(from, ...)` / `prevActionOfType(from, ...)` walk from
    /// a cursor. Verify they skip masks that don't match and report the
    /// neighbouring node.
    function testNextAndPrevFromSpecificCursor() external {
        uint256 id1 = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");
        uint256 id2 = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, hex"");
        uint256 id3 = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 3500, hex"");

        // next from id1 → id2.
        (uint256 cursor,,) = h.nextOf(id1, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL);
        assertEq(cursor, id2);

        // next from id3 → none (tail).
        (cursor,,) = h.nextOf(id3, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL);
        assertEq(cursor, NODE_NONE);

        // prev from id3 → id2.
        (cursor,,) = h.prevOf(id3, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL);
        assertEq(cursor, id2);

        // prev from id1 → none (head).
        (cursor,,) = h.prevOf(id1, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL);
        assertEq(cursor, NODE_NONE);
    }

    // Shared list layout (effectiveTime ascending — block.timestamp warps to 2700):
    //   id1 type=1 t=1500   completed
    //   id2 type=2 t=1700   completed
    //   id3 type=1 t=1900   completed
    //   id4 type=1 t=2100   completed
    //   id5 type=2 t=2300   completed
    //   id6 type=1 t=3500   pending
    //   id7 type=2 t=3700   pending
    //   id8 type=1 t=3900   pending

    uint256 internal id1;
    uint256 internal id2;
    uint256 internal id3;
    uint256 internal id4;
    uint256 internal id5;
    uint256 internal id6;
    uint256 internal id7;
    uint256 internal id8;

    function buildMixedCompletedPendingList() internal {
        id1 = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");
        id2 = h.schedule(ACTION_TYPE_STABLES_DIVIDEND_V1, 1700, hex"");
        id3 = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1900, hex"");
        id4 = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2100, hex"");
        id5 = h.schedule(ACTION_TYPE_STABLES_DIVIDEND_V1, 2300, hex"");
        id6 = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 3500, hex"");
        id7 = h.schedule(ACTION_TYPE_STABLES_DIVIDEND_V1, 3700, hex"");
        id8 = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 3900, hex"");
        vm.warp(2700);
    }

    function testForwardAllVisitsEveryNodeRespectingMask() external {
        buildMixedCompletedPendingList();
        assertForwardSequence(
            USER_TYPES_TEST_MASK, CompletionFilter.ALL, cursors8(id1, id2, id3, id4, id5, id6, id7, id8)
        );
        assertForwardSequence(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL, cursors5(id1, id3, id4, id6, id8));
        assertForwardSequence(ACTION_TYPE_STABLES_DIVIDEND_V1, CompletionFilter.ALL, cursors3(id2, id5, id7));
    }

    function testForwardCompletedStopsAtFirstPendingRespectingMask() external {
        buildMixedCompletedPendingList();
        assertForwardSequence(USER_TYPES_TEST_MASK, CompletionFilter.COMPLETED, cursors5(id1, id2, id3, id4, id5));
        assertForwardSequence(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED, cursors3(id1, id3, id4));
        assertForwardSequence(ACTION_TYPE_STABLES_DIVIDEND_V1, CompletionFilter.COMPLETED, cursors2(id2, id5));
    }

    function testForwardPendingSkipsCompletedPrefixRespectingMask() external {
        buildMixedCompletedPendingList();
        assertForwardSequence(USER_TYPES_TEST_MASK, CompletionFilter.PENDING, cursors3(id6, id7, id8));
        assertForwardSequence(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING, cursors2(id6, id8));
        assertForwardSequence(ACTION_TYPE_STABLES_DIVIDEND_V1, CompletionFilter.PENDING, cursors1(id7));
    }

    function testBackwardAllVisitsEveryNodeRespectingMask() external {
        buildMixedCompletedPendingList();
        assertBackwardSequence(
            USER_TYPES_TEST_MASK, CompletionFilter.ALL, cursors8(id8, id7, id6, id5, id4, id3, id2, id1)
        );
        assertBackwardSequence(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL, cursors5(id8, id6, id4, id3, id1));
        assertBackwardSequence(ACTION_TYPE_STABLES_DIVIDEND_V1, CompletionFilter.ALL, cursors3(id7, id5, id2));
    }

    function testBackwardCompletedSkipsPendingSuffixRespectingMask() external {
        buildMixedCompletedPendingList();
        assertBackwardSequence(USER_TYPES_TEST_MASK, CompletionFilter.COMPLETED, cursors5(id5, id4, id3, id2, id1));
        assertBackwardSequence(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED, cursors3(id4, id3, id1));
        assertBackwardSequence(ACTION_TYPE_STABLES_DIVIDEND_V1, CompletionFilter.COMPLETED, cursors2(id5, id2));
    }

    function testBackwardPendingStopsAtFirstCompletedRespectingMask() external {
        buildMixedCompletedPendingList();
        assertBackwardSequence(USER_TYPES_TEST_MASK, CompletionFilter.PENDING, cursors3(id8, id7, id6));
        assertBackwardSequence(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING, cursors2(id8, id6));
        assertBackwardSequence(ACTION_TYPE_STABLES_DIVIDEND_V1, CompletionFilter.PENDING, cursors1(id7));
    }

    /// COMPLETED filter on a list where every node is pending returns 0
    /// in both directions.
    function testAllPendingListReturnsZeroForCompletedFilter() external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");
        h.schedule(ACTION_TYPE_STABLES_DIVIDEND_V1, 2500, hex"");
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 3500, hex"");
        // No warp — block.timestamp stays at 1000 < every effectiveTime.

        (uint256 cursor,,) = h.earliest(USER_TYPES_TEST_MASK, CompletionFilter.COMPLETED);
        assertEq(cursor, NODE_NONE, "earliest COMPLETED on all-pending list");
        (cursor,,) = h.latest(USER_TYPES_TEST_MASK, CompletionFilter.COMPLETED);
        assertEq(cursor, NODE_NONE, "latest COMPLETED on all-pending list");
    }

    /// PENDING filter on a list where every node is completed returns 0
    /// in both directions.
    function testAllCompletedListReturnsZeroForPendingFilter() external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1100, hex"");
        h.schedule(ACTION_TYPE_STABLES_DIVIDEND_V1, 1200, hex"");
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1300, hex"");
        vm.warp(1500); // every node is now completed.

        (uint256 cursor,,) = h.earliest(USER_TYPES_TEST_MASK, CompletionFilter.PENDING);
        assertEq(cursor, NODE_NONE, "earliest PENDING on all-completed list");
        (cursor,,) = h.latest(USER_TYPES_TEST_MASK, CompletionFilter.PENDING);
        assertEq(cursor, NODE_NONE, "latest PENDING on all-completed list");
    }

    /// PENDING traversal returns 0 when the completion segment has no
    /// matching nodes, even when nodes matching the mask exist in the
    /// other segment. Cancel id7 (the only type-2 pending node) — type-2
    /// nodes still exist in the completed segment.
    function testNonMatchingMaskInSegmentReturnsZero() external {
        buildMixedCompletedPendingList();
        h.cancel(id7);

        (uint256 cursor,,) = h.earliest(ACTION_TYPE_STABLES_DIVIDEND_V1, CompletionFilter.PENDING);
        assertEq(cursor, NODE_NONE, "PENDING type-2 segment empty after cancel");
        (cursor,,) = h.latest(ACTION_TYPE_STABLES_DIVIDEND_V1, CompletionFilter.PENDING);
        assertEq(cursor, NODE_NONE, "PENDING type-2 segment empty after cancel");

        (cursor,,) = h.earliest(ACTION_TYPE_STABLES_DIVIDEND_V1, CompletionFilter.COMPLETED);
        assertEq(cursor, id2, "COMPLETED type-2 still finds id2");
    }

    /// A node whose `effectiveTime` equals `block.timestamp` is treated
    /// as COMPLETED, not PENDING — the predicate is
    /// `effectiveTime <= block.timestamp`.
    function testNodeAtExactTimestampIsCompleted() external {
        uint256 idA = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2000, hex"");
        uint256 idB = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, hex"");
        vm.warp(2000); // idA at exact boundary; idB still pending.

        (uint256 cursor,,) = h.earliest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
        assertEq(cursor, idA, "node at block.timestamp is COMPLETED forward");
        (cursor,,) = h.latest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
        assertEq(cursor, idA, "node at block.timestamp is COMPLETED backward");

        // PENDING filter must not include idA, only idB.
        (cursor,,) = h.earliest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(cursor, idB, "node at block.timestamp is NOT PENDING forward");
        (cursor,,) = h.latest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(cursor, idB, "node at block.timestamp is NOT PENDING backward");
    }

    /// Cancelled nodes are skipped during traversal under COMPLETED and
    /// PENDING filters, both directions.
    function testCancelMiddleNodeSkippedUnderCompletedAndPendingFilters() external {
        uint256 idA = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1100, hex""); // will be completed
        uint256 idB = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1200, hex""); // will be completed, then cancelled
        uint256 idC = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1300, hex""); // will be completed
        uint256 idD = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 3500, hex""); // pending
        uint256 idE = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 3600, hex""); // pending, then cancelled
        uint256 idF = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 3700, hex""); // pending

        // Cancel idB and idE BEFORE warp — both still pending so cancel is allowed.
        h.cancel(idB);
        h.cancel(idE);

        vm.warp(2000); // idA, idC completed; idD, idF pending.

        // COMPLETED forward must skip idB.
        (uint256 cursor,,) = h.earliest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
        assertEq(cursor, idA);
        (cursor,,) = h.nextOf(cursor, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
        assertEq(cursor, idC, "COMPLETED forward skips cancelled idB");
        (cursor,,) = h.nextOf(cursor, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
        assertEq(cursor, NODE_NONE);

        // COMPLETED backward must skip idB.
        (cursor,,) = h.latest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
        assertEq(cursor, idC);
        (cursor,,) = h.prevOf(cursor, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
        assertEq(cursor, idA, "COMPLETED backward skips cancelled idB");
        (cursor,,) = h.prevOf(cursor, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
        assertEq(cursor, NODE_NONE);

        // PENDING forward must skip idE.
        (cursor,,) = h.earliest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(cursor, idD);
        (cursor,,) = h.nextOf(cursor, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(cursor, idF, "PENDING forward skips cancelled idE");
        (cursor,,) = h.nextOf(cursor, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(cursor, NODE_NONE);

        // PENDING backward must skip idE.
        (cursor,,) = h.latest(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(cursor, idF);
        (cursor,,) = h.prevOf(cursor, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(cursor, idD, "PENDING backward skips cancelled idE");
        (cursor,,) = h.prevOf(cursor, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(cursor, NODE_NONE);
    }

    /// `nextOf` from the tail and `prevOf` from the head return 0 across
    /// every filter.
    function testTraversalAtBoundariesReturnsZero() external {
        buildMixedCompletedPendingList();

        // nextOf from the tail (id8) → 0 across all filters that match it.
        (uint256 cursor,,) = h.nextOf(id8, USER_TYPES_TEST_MASK, CompletionFilter.ALL);
        assertEq(cursor, NODE_NONE, "next from tail ALL");
        (cursor,,) = h.nextOf(id8, USER_TYPES_TEST_MASK, CompletionFilter.PENDING);
        assertEq(cursor, NODE_NONE, "next from tail PENDING");
        // From the last completed node, nextOf COMPLETED → 0 (early-break).
        (cursor,,) = h.nextOf(id5, USER_TYPES_TEST_MASK, CompletionFilter.COMPLETED);
        assertEq(cursor, NODE_NONE, "next from last completed under COMPLETED");

        // prevOf from the head (id1) → 0 across all filters that match it.
        (cursor,,) = h.prevOf(id1, USER_TYPES_TEST_MASK, CompletionFilter.ALL);
        assertEq(cursor, NODE_NONE, "prev from head ALL");
        (cursor,,) = h.prevOf(id1, USER_TYPES_TEST_MASK, CompletionFilter.COMPLETED);
        assertEq(cursor, NODE_NONE, "prev from head COMPLETED");
        // From the first pending node, prevOf PENDING → 0 (early-break).
        (cursor,,) = h.prevOf(id6, USER_TYPES_TEST_MASK, CompletionFilter.PENDING);
        assertEq(cursor, NODE_NONE, "prev from first pending under PENDING");
    }

    /// `nextOf` / `prevOf` from a previously-cancelled cursor return 0
    /// across every filter — cancellation zeros `node.prev` and
    /// `node.next`.
    function testTraversalFromCancelledCursorReturnsZero() external {
        uint256 idA = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");
        uint256 idB = h.schedule(ACTION_TYPE_STABLES_DIVIDEND_V1, 2500, hex"");
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 3500, hex"");
        h.cancel(idA);
        h.cancel(idB);

        // nextOf from a cancelled cursor — every filter returns 0.
        (uint256 cursor,,) = h.nextOf(idA, USER_TYPES_TEST_MASK, CompletionFilter.ALL);
        assertEq(cursor, NODE_NONE, "next from cancelled idA ALL");
        (cursor,,) = h.nextOf(idA, USER_TYPES_TEST_MASK, CompletionFilter.COMPLETED);
        assertEq(cursor, NODE_NONE, "next from cancelled idA COMPLETED");
        (cursor,,) = h.nextOf(idA, USER_TYPES_TEST_MASK, CompletionFilter.PENDING);
        assertEq(cursor, NODE_NONE, "next from cancelled idA PENDING");

        // prevOf from a cancelled cursor — every filter returns 0.
        (cursor,,) = h.prevOf(idB, USER_TYPES_TEST_MASK, CompletionFilter.ALL);
        assertEq(cursor, NODE_NONE, "prev from cancelled idB ALL");
        (cursor,,) = h.prevOf(idB, USER_TYPES_TEST_MASK, CompletionFilter.COMPLETED);
        assertEq(cursor, NODE_NONE, "prev from cancelled idB COMPLETED");
        (cursor,,) = h.prevOf(idB, USER_TYPES_TEST_MASK, CompletionFilter.PENDING);
        assertEq(cursor, NODE_NONE, "prev from cancelled idB PENDING");
    }

    /// A multi-bit mask matches any node sharing at least one bit with
    /// the mask — the predicate is `actionType & mask != 0`, not
    /// `& mask == mask`.
    function testMultiBitMaskMatchesAnyBit() external {
        uint256 idSplit = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");
        uint256 idDividend = h.schedule(ACTION_TYPE_STABLES_DIVIDEND_V1, 2500, hex"");
        vm.warp(3000);

        // Mask = stock-split | stables-dividend — both nodes match.
        (uint256 cursor,,) = h.earliest(USER_TYPES_TEST_MASK, CompletionFilter.ALL);
        assertEq(cursor, idSplit, "first match under multi-bit mask");
        (cursor,,) = h.nextOf(cursor, USER_TYPES_TEST_MASK, CompletionFilter.ALL);
        assertEq(cursor, idDividend, "second match under multi-bit mask");
        (cursor,,) = h.nextOf(cursor, USER_TYPES_TEST_MASK, CompletionFilter.ALL);
        assertEq(cursor, NODE_NONE);

        // Multi-bit mask under COMPLETED filter — same matches because
        // both nodes are now completed.
        (cursor,,) = h.earliest(USER_TYPES_TEST_MASK, CompletionFilter.COMPLETED);
        assertEq(cursor, idSplit);
        (cursor,,) = h.nextOf(cursor, USER_TYPES_TEST_MASK, CompletionFilter.COMPLETED);
        assertEq(cursor, idDividend);
    }

    /// Nodes scheduled with the same `effectiveTime` are returned in
    /// insertion order forward and reverse-insertion order backward.
    function testTraversalRespectsTiedEffectiveTimeOrdering() external {
        uint256 first = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");
        uint256 second = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");
        uint256 third = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");
        vm.warp(2000);

        // Forward across all three filters: insertion order.
        assertForwardSequence(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL, cursors3(first, second, third));
        assertForwardSequence(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED, cursors3(first, second, third));

        // Backward: reverse insertion order.
        assertBackwardSequence(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL, cursors3(third, second, first));
        assertBackwardSequence(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED, cursors3(third, second, first));
    }

    /// `latest` / `earliest` / `nextOf` / `prevOf` return
    /// `(cursor, actionType, effectiveTime)`. A zero cursor returns all
    /// zeros; a non-zero cursor returns the resolved node's stored
    /// `actionType` and `effectiveTime`.
    function testTupleReturnsActionTypeAndEffectiveTime() external {
        buildMixedCompletedPendingList();

        (uint256 cursor, uint256 actionType, uint64 effectiveTime) =
            h.earliest(USER_TYPES_TEST_MASK, CompletionFilter.ALL);
        assertEq(cursor, id1);
        assertEq(actionType, ACTION_TYPE_STOCK_SPLIT_V1);
        assertEq(effectiveTime, 1500);

        (cursor, actionType, effectiveTime) = h.earliest(USER_TYPES_TEST_MASK, CompletionFilter.PENDING);
        assertEq(cursor, id6);
        assertEq(actionType, ACTION_TYPE_STOCK_SPLIT_V1);
        assertEq(effectiveTime, 3500);

        (cursor, actionType, effectiveTime) = h.latest(USER_TYPES_TEST_MASK, CompletionFilter.COMPLETED);
        assertEq(cursor, id5);
        assertEq(actionType, ACTION_TYPE_STABLES_DIVIDEND_V1);
        assertEq(effectiveTime, 2300);

        (cursor, actionType, effectiveTime) = h.nextOf(id5, USER_TYPES_TEST_MASK, CompletionFilter.ALL);
        assertEq(cursor, id6);
        assertEq(actionType, ACTION_TYPE_STOCK_SPLIT_V1);
        assertEq(effectiveTime, 3500);

        (cursor, actionType, effectiveTime) = h.prevOf(id3, USER_TYPES_TEST_MASK, CompletionFilter.COMPLETED);
        assertEq(cursor, id2);
        assertEq(actionType, ACTION_TYPE_STABLES_DIVIDEND_V1);
        assertEq(effectiveTime, 1700);

        (cursor, actionType, effectiveTime) = h.nextOf(id8, USER_TYPES_TEST_MASK, CompletionFilter.ALL);
        assertEq(cursor, NODE_NONE);
        assertEq(actionType, 0);
        assertEq(effectiveTime, 0);
    }

    /// For any random list, `earliest(mask, filter)` returns 0 if and
    /// only if no node satisfies both `mask` and `filter`. The brute-force
    /// scan computes the expected answer by checking every cursor index
    /// against the node-storage tuple directly.
    function testFuzzEarliestCompletenessVsBruteForce(uint8 nodeCount, uint64 warpTo, uint256 seed) external {
        nodeCount = uint8(bound(nodeCount, 1, 12));
        warpTo = uint64(bound(warpTo, 1, 10_000));
        vm.warp(warpTo);

        uint256[] memory ids = new uint256[](nodeCount);
        for (uint256 i = 0; i < nodeCount; i++) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint256 actionType = (seed & 1) == 0 ? ACTION_TYPE_STOCK_SPLIT_V1 : ACTION_TYPE_STABLES_DIVIDEND_V1;
            uint64 effectiveTime = uint64(warpTo + 1 + (seed >> 8) % 100);
            ids[i] = h.schedule(actionType, effectiveTime, hex"");
        }
        vm.warp(warpTo + uint64((seed >> 16) % 100));

        uint256[3] memory masks = [ACTION_TYPE_STOCK_SPLIT_V1, ACTION_TYPE_STABLES_DIVIDEND_V1, USER_TYPES_TEST_MASK];
        CompletionFilter[3] memory filters =
            [CompletionFilter.ALL, CompletionFilter.COMPLETED, CompletionFilter.PENDING];

        for (uint256 m = 0; m < 3; m++) {
            for (uint256 f = 0; f < 3; f++) {
                bool anyMatch = false;
                for (uint256 i = 0; i < nodeCount; i++) {
                    (uint256 actionType, uint64 effectiveTime) = h.nodeAt(ids[i]);
                    if (actionType & masks[m] == 0) continue;
                    if (filters[f] == CompletionFilter.COMPLETED && effectiveTime > block.timestamp) continue;
                    if (filters[f] == CompletionFilter.PENDING && effectiveTime <= block.timestamp) continue;
                    anyMatch = true;
                    break;
                }

                (uint256 earliestCursor,,) = h.earliest(masks[m], filters[f]);
                (uint256 latestCursor,,) = h.latest(masks[m], filters[f]);

                if (anyMatch) {
                    assertTrue(earliestCursor != 0, "earliest must find an existing match");
                    assertTrue(latestCursor != 0, "latest must find an existing match");
                } else {
                    assertEq(earliestCursor, NODE_NONE, "earliest must be 0 when no node matches");
                    assertEq(latestCursor, NODE_NONE, "latest must be 0 when no node matches");
                }
            }
        }
    }

    /// For any random list and any (mask, filter), walking forward from
    /// `earliest` via repeated `nextOf` calls visits every matching
    /// cursor in time-ascending order and terminates at the cursor
    /// returned by `latest`.
    function testFuzzForwardWalkFromEarliestReachesLatest(uint8 nodeCount, uint64 warpTo, uint256 seed) external {
        nodeCount = uint8(bound(nodeCount, 1, 12));
        warpTo = uint64(bound(warpTo, 1, 10_000));
        vm.warp(warpTo);

        for (uint256 i = 0; i < nodeCount; i++) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint256 actionType = (seed & 1) == 0 ? ACTION_TYPE_STOCK_SPLIT_V1 : ACTION_TYPE_STABLES_DIVIDEND_V1;
            uint64 effectiveTime = uint64(warpTo + 1 + (seed >> 8) % 100);
            h.schedule(actionType, effectiveTime, hex"");
        }
        vm.warp(warpTo + uint64((seed >> 16) % 100));

        uint256[3] memory masks = [ACTION_TYPE_STOCK_SPLIT_V1, ACTION_TYPE_STABLES_DIVIDEND_V1, USER_TYPES_TEST_MASK];
        CompletionFilter[3] memory filters =
            [CompletionFilter.ALL, CompletionFilter.COMPLETED, CompletionFilter.PENDING];

        for (uint256 m = 0; m < 3; m++) {
            for (uint256 f = 0; f < 3; f++) {
                (uint256 cursor,,) = h.earliest(masks[m], filters[f]);
                (uint256 latestCursor,,) = h.latest(masks[m], filters[f]);

                if (cursor == 0) {
                    assertEq(latestCursor, NODE_NONE, "earliest 0 implies latest 0");
                    continue;
                }

                uint256 hops;
                while (cursor != latestCursor) {
                    (cursor,,) = h.nextOf(cursor, masks[m], filters[f]);
                    hops++;
                    assertTrue(cursor != 0, "forward walk hit 0 before reaching latest");
                    assertLt(hops, nodeCount, "forward walk exceeded node count");
                }
                assertEq(cursor, latestCursor, "forward walk lands on latest");
            }
        }
    }

    /// Backward walk from `latest` via repeated `prevOf` calls reaches
    /// `earliest` for any random list and any (mask, filter).
    function testFuzzBackwardWalkFromLatestReachesEarliest(uint8 nodeCount, uint64 warpTo, uint256 seed) external {
        nodeCount = uint8(bound(nodeCount, 1, 12));
        warpTo = uint64(bound(warpTo, 1, 10_000));
        vm.warp(warpTo);

        for (uint256 i = 0; i < nodeCount; i++) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint256 actionType = (seed & 1) == 0 ? ACTION_TYPE_STOCK_SPLIT_V1 : ACTION_TYPE_STABLES_DIVIDEND_V1;
            uint64 effectiveTime = uint64(warpTo + 1 + (seed >> 8) % 100);
            h.schedule(actionType, effectiveTime, hex"");
        }
        vm.warp(warpTo + uint64((seed >> 16) % 100));

        uint256[3] memory masks = [ACTION_TYPE_STOCK_SPLIT_V1, ACTION_TYPE_STABLES_DIVIDEND_V1, USER_TYPES_TEST_MASK];
        CompletionFilter[3] memory filters =
            [CompletionFilter.ALL, CompletionFilter.COMPLETED, CompletionFilter.PENDING];

        for (uint256 m = 0; m < 3; m++) {
            for (uint256 f = 0; f < 3; f++) {
                (uint256 cursor,,) = h.latest(masks[m], filters[f]);
                (uint256 earliestCursor,,) = h.earliest(masks[m], filters[f]);

                if (cursor == 0) {
                    assertEq(earliestCursor, NODE_NONE, "latest 0 implies earliest 0");
                    continue;
                }

                uint256 hops;
                while (cursor != earliestCursor) {
                    (cursor,,) = h.prevOf(cursor, masks[m], filters[f]);
                    hops++;
                    assertTrue(cursor != 0, "backward walk hit 0 before reaching earliest");
                    assertLt(hops, nodeCount, "backward walk exceeded node count");
                }
                assertEq(cursor, earliestCursor, "backward walk lands on earliest");
            }
        }
    }

    /// Random schedule + cancel sequences preserve every traversal
    /// invariant: returned cursors satisfy filter+mask, completeness
    /// matches brute force, and walks reach the opposite end.
    function testFuzzInvariantsHoldUnderCancellations(uint8 nodeCount, uint64 warpTo, uint256 seed) external {
        nodeCount = uint8(bound(nodeCount, 2, 12));
        warpTo = uint64(bound(warpTo, 1, 10_000));
        vm.warp(warpTo);

        uint256[] memory ids = new uint256[](nodeCount);
        for (uint256 i = 0; i < nodeCount; i++) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint256 actionType = (seed & 1) == 0 ? ACTION_TYPE_STOCK_SPLIT_V1 : ACTION_TYPE_STABLES_DIVIDEND_V1;
            uint64 effectiveTime = uint64(warpTo + 1 + (seed >> 8) % 100);
            ids[i] = h.schedule(actionType, effectiveTime, hex"");
        }

        // Cancel a random subset of nodes BEFORE warp (only pending nodes
        // can be cancelled, and at this point all are pending).
        bool[] memory cancelled = new bool[](nodeCount);
        for (uint256 i = 0; i < nodeCount; i++) {
            seed = uint256(keccak256(abi.encode(seed, "cancel", i)));
            if ((seed & 3) == 0) {
                h.cancel(ids[i]);
                cancelled[i] = true;
            }
        }

        vm.warp(warpTo + uint64((seed >> 16) % 100));

        uint256[3] memory masks = [ACTION_TYPE_STOCK_SPLIT_V1, ACTION_TYPE_STABLES_DIVIDEND_V1, USER_TYPES_TEST_MASK];
        CompletionFilter[3] memory filters =
            [CompletionFilter.ALL, CompletionFilter.COMPLETED, CompletionFilter.PENDING];

        for (uint256 m = 0; m < 3; m++) {
            for (uint256 f = 0; f < 3; f++) {
                bool anyMatch = false;
                for (uint256 i = 0; i < nodeCount; i++) {
                    if (cancelled[i]) continue;
                    (uint256 actionType, uint64 effectiveTime) = h.nodeAt(ids[i]);
                    if (actionType & masks[m] == 0) continue;
                    if (filters[f] == CompletionFilter.COMPLETED && effectiveTime > block.timestamp) continue;
                    if (filters[f] == CompletionFilter.PENDING && effectiveTime <= block.timestamp) continue;
                    anyMatch = true;
                    break;
                }

                (uint256 earliestCursor,,) = h.earliest(masks[m], filters[f]);
                if (anyMatch) {
                    assertTrue(earliestCursor != 0, "earliest must find a non-cancelled match");
                } else {
                    assertEq(earliestCursor, NODE_NONE, "earliest must be 0 when no live node matches");
                }

                assertCursorSatisfiesInvariants(earliestCursor, masks[m], filters[f]);
            }
        }
    }

    /// For any randomly-shaped list, every (direction × filter × mask)
    /// call returns a cursor that is either 0 or whose node has at
    /// least one bit in common with `mask` and a completion state
    /// consistent with `filter`.
    function testFuzzReturnedCursorSatisfiesFilterAndMask(uint8 nodeCount, uint64 warpTo, uint256 seed) external {
        nodeCount = uint8(bound(nodeCount, 1, 12));
        warpTo = uint64(bound(warpTo, 1, 10_000));
        vm.warp(warpTo);

        for (uint256 i = 0; i < nodeCount; i++) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint256 actionType = (seed & 1) == 0 ? ACTION_TYPE_STOCK_SPLIT_V1 : ACTION_TYPE_STABLES_DIVIDEND_V1;
            uint64 effectiveTime = uint64(warpTo + 1 + (seed >> 8) % 100);
            h.schedule(actionType, effectiveTime, hex"");
        }

        // Warp forward so a subset of nodes becomes completed.
        vm.warp(warpTo + uint64((seed >> 16) % 100));

        uint256[3] memory masks = [ACTION_TYPE_STOCK_SPLIT_V1, ACTION_TYPE_STABLES_DIVIDEND_V1, USER_TYPES_TEST_MASK];
        CompletionFilter[3] memory filters =
            [CompletionFilter.ALL, CompletionFilter.COMPLETED, CompletionFilter.PENDING];

        for (uint256 m = 0; m < 3; m++) {
            for (uint256 f = 0; f < 3; f++) {
                (uint256 cursor,,) = h.earliest(masks[m], filters[f]);
                assertCursorSatisfiesInvariants(cursor, masks[m], filters[f]);

                (cursor,,) = h.latest(masks[m], filters[f]);
                assertCursorSatisfiesInvariants(cursor, masks[m], filters[f]);
            }
        }
    }

    function assertCursorSatisfiesInvariants(uint256 cursor, uint256 mask, CompletionFilter filter) internal view {
        if (cursor == 0) return;

        (uint256 actionType, uint64 effectiveTime) = h.nodeAt(cursor);

        assertTrue(actionType & mask != 0, "returned cursor's actionType matches mask");

        if (filter == CompletionFilter.COMPLETED) {
            assertTrue(effectiveTime <= block.timestamp, "COMPLETED cursor is at or past effectiveTime");
        } else if (filter == CompletionFilter.PENDING) {
            assertTrue(effectiveTime > block.timestamp, "PENDING cursor is in the future");
        }
    }

    /// `nextOfType` and `prevOfType` start at the cursor after / before
    /// `fromIndex` — the `fromIndex` node itself is never returned, even
    /// when it matches the mask and filter.
    function testFromIndexExcludesSelf() external {
        buildMixedCompletedPendingList();

        // ALL forward: from id3 → id4 (skip id3 itself).
        (uint256 cursor,,) = h.nextOf(id3, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL);
        assertEq(cursor, id4, "ALL forward excludes fromIndex");

        // COMPLETED forward: from id3 → id4 (id3 itself is completed and
        // matches type-1 but is excluded by `next` step).
        (cursor,,) = h.nextOf(id3, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
        assertEq(cursor, id4, "COMPLETED forward excludes fromIndex");

        // PENDING forward: from id6 → id8 (id6 itself is pending and
        // matches type-1 but is excluded).
        (cursor,,) = h.nextOf(id6, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(cursor, id8, "PENDING forward excludes fromIndex");

        // ALL backward: from id4 → id3.
        (cursor,,) = h.prevOf(id4, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL);
        assertEq(cursor, id3, "ALL backward excludes fromIndex");

        // COMPLETED backward: from id4 → id3.
        (cursor,,) = h.prevOf(id4, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
        assertEq(cursor, id3, "COMPLETED backward excludes fromIndex");

        // PENDING backward: from id8 → id6.
        (cursor,,) = h.prevOf(id8, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(cursor, id6, "PENDING backward excludes fromIndex");
    }

    /// Walk forward from before-the-head and assert the visit order matches
    /// `expected`. After the last expected cursor, the next call must return
    /// 0 (terminator).
    function assertForwardSequence(uint256 mask, CompletionFilter filter, uint256[] memory expected) internal view {
        (uint256 cursor,,) = h.earliest(mask, filter);
        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(cursor, expected[i], "forward cursor mismatch");
            (cursor,,) = h.nextOf(cursor, mask, filter);
        }
        assertEq(cursor, NODE_NONE, "forward cursor not terminated");
    }

    /// Walk backward from after-the-tail and assert the visit order matches
    /// `expected`. After the last expected cursor, the next call must return
    /// 0 (terminator).
    function assertBackwardSequence(uint256 mask, CompletionFilter filter, uint256[] memory expected) internal view {
        (uint256 cursor,,) = h.latest(mask, filter);
        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(cursor, expected[i], "backward cursor mismatch");
            (cursor,,) = h.prevOf(cursor, mask, filter);
        }
        assertEq(cursor, NODE_NONE, "backward cursor not terminated");
    }

    function cursors1(uint256 a) internal pure returns (uint256[] memory r) {
        r = new uint256[](1);
        r[0] = a;
    }

    function cursors2(uint256 a, uint256 b) internal pure returns (uint256[] memory r) {
        r = new uint256[](2);
        r[0] = a;
        r[1] = b;
    }

    function cursors3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256[] memory r) {
        r = new uint256[](3);
        r[0] = a;
        r[1] = b;
        r[2] = c;
    }

    function cursors5(uint256 a, uint256 b, uint256 c, uint256 d, uint256 e)
        internal
        pure
        returns (uint256[] memory r)
    {
        r = new uint256[](5);
        r[0] = a;
        r[1] = b;
        r[2] = c;
        r[3] = d;
        r[4] = e;
    }

    function cursors8(uint256 a, uint256 b, uint256 c, uint256 d, uint256 e, uint256 f, uint256 g, uint256 h_)
        internal
        pure
        returns (uint256[] memory r)
    {
        r = new uint256[](8);
        r[0] = a;
        r[1] = b;
        r[2] = c;
        r[3] = d;
        r[4] = e;
        r[5] = f;
        r[6] = g;
        r[7] = h_;
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibCorporateAction} from "src/lib/LibCorporateAction.sol";
import {
    ACTION_TYPE_STOCK_SPLIT_V1,
    ACTION_TYPE_STABLES_DIVIDEND_V1,
    VALID_ACTION_TYPES_MASK
} from "src/interface/ICorporateActionsV1.sol";
import {CompletionFilter, LibCorporateActionNode} from "src/lib/LibCorporateActionNode.sol";
import {InvalidMask} from "src/error/ErrCorporateAction.sol";

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
        (uint256 c1, uint256 t1, uint64 e1) = h.latest(type(uint256).max, CompletionFilter.ALL);
        assertEq(c1, 0);
        assertEq(t1, 0);
        assertEq(e1, 0);

        (uint256 c2, uint256 t2, uint64 e2) = h.earliest(type(uint256).max, CompletionFilter.ALL);
        assertEq(c2, 0);
        assertEq(t2, 0);
        assertEq(e2, 0);

        (uint256 c3, uint256 t3, uint64 e3) = h.nextOf(0, type(uint256).max, CompletionFilter.ALL);
        assertEq(c3, 0);
        assertEq(t3, 0);
        assertEq(e3, 0);

        (uint256 c4, uint256 t4, uint64 e4) = h.prevOf(0, type(uint256).max, CompletionFilter.ALL);
        assertEq(c4, 0);
        assertEq(t4, 0);
        assertEq(e4, 0);
    }

    /// Single pending node: `earliest` and `latest` both resolve to it with the
    /// matching mask and ALL / PENDING filters. COMPLETED filter returns zeros
    /// because the single node has not reached effective time.
    function testSingleNodeResolution() external {
        uint256 id = h.schedule(1, 1500, hex"");

        (uint256 cursor, uint256 actionType, uint64 effectiveTime) = h.latest(1, CompletionFilter.ALL);
        assertEq(cursor, id);
        assertEq(actionType, 1);
        assertEq(effectiveTime, 1500);

        (cursor, actionType, effectiveTime) = h.earliest(1, CompletionFilter.ALL);
        assertEq(cursor, id);
        assertEq(actionType, 1);
        assertEq(effectiveTime, 1500);

        // Pending filter also matches (effectiveTime > now).
        (cursor,,) = h.latest(1, CompletionFilter.PENDING);
        assertEq(cursor, id);

        // Completed filter does NOT match yet.
        (cursor,,) = h.latest(1, CompletionFilter.COMPLETED);
        assertEq(cursor, 0);
    }

    /// Mask = 0 can never match any node (every node's `actionType` has at
    /// least one bit set, so `actionType & 0 == 0` for every node). The
    /// traversal primitives revert with `InvalidMask` so a caller bug
    /// surfaces rather than being silently conflated with an empty-list
    /// "no match" result.
    function testMaskZeroReverts() external {
        h.schedule(1, 1500, hex"");

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
        h.schedule(1, 1500, hex"");

        // Bit 2 alone — no action type uses bit 2 today.
        vm.expectRevert(InvalidMask.selector);
        h.latest(1 << 2, CompletionFilter.ALL);

        // Bits 2 and 3 — both undefined.
        vm.expectRevert(InvalidMask.selector);
        h.latest((1 << 2) | (1 << 3), CompletionFilter.ALL);
    }

    /// Fuzz: any mask with no valid bits (i.e. `mask & VALID_ACTION_TYPES_MASK
    /// == 0`) reverts with `InvalidMask`, regardless of list state. Generated
    /// masks are forced into the invalid-only space by ANDing with the
    /// complement of the valid mask; the result is either 0 (mask=0) or a
    /// purely-undefined bitfield, both of which must revert.
    function testFuzzMaskWithNoValidBitsAlwaysReverts(uint256 rawMask) external {
        h.schedule(1, 1500, hex"");

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
        h.schedule(1, 1500, hex"");

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
        uint256 id = h.schedule(1, 1500, hex"");

        // Bit 0 (valid, stock split) + bit 2 (undefined).
        (uint256 cursor,,) = h.latest((1 << 0) | (1 << 2), CompletionFilter.ALL);
        assertEq(cursor, id, "valid bit in mask matches node with that bit set");

        // type(uint256).max has every bit including bit 0.
        (cursor,,) = h.latest(type(uint256).max, CompletionFilter.ALL);
        assertEq(cursor, id, "max-value mask still matches via its valid bits");
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
        uint256 id1 = h.schedule(1, 1500, hex"");
        uint256 id2 = h.schedule(1, 2500, hex"");

        // Pre-1500: both pending.
        (uint256 cursor,,) = h.latest(1, CompletionFilter.COMPLETED);
        assertEq(cursor, 0);
        (cursor,,) = h.earliest(1, CompletionFilter.PENDING);
        assertEq(cursor, id1);

        // Warp past id1's effective time only.
        vm.warp(2000);

        (cursor,,) = h.latest(1, CompletionFilter.COMPLETED);
        assertEq(cursor, id1, "only id1 has completed");
        (cursor,,) = h.earliest(1, CompletionFilter.PENDING);
        assertEq(cursor, id2, "only id2 still pending");

        // Warp past both.
        vm.warp(3000);
        (cursor,,) = h.latest(1, CompletionFilter.COMPLETED);
        assertEq(cursor, id2, "tail becomes latest completed");
        (cursor,,) = h.earliest(1, CompletionFilter.PENDING);
        assertEq(cursor, 0, "no pending actions remain");
    }

    /// After a middle node is cancelled, traversal re-links the list so
    /// `nextActionOfType` skips the cancelled cursor and `prevActionOfType`
    /// from the tail no longer touches it. Pins the linked-list integrity
    /// under cancellation through the traversal API surface.
    function testCancelMiddleNodeRelinksTraversal() external {
        uint256 id1 = h.schedule(1, 1500, hex"");
        uint256 id2 = h.schedule(1, 2500, hex"");
        uint256 id3 = h.schedule(1, 3500, hex"");

        h.cancel(id2);

        // nextActionOfType from id1 now skips past id2 to id3.
        (uint256 cursor,,) = h.nextOf(id1, 1, CompletionFilter.ALL);
        assertEq(cursor, id3, "next(id1) must skip cancelled id2");

        // prevActionOfType from id3 now skips id2 back to id1.
        (cursor,,) = h.prevOf(id3, 1, CompletionFilter.ALL);
        assertEq(cursor, id1, "prev(id3) must skip cancelled id2");

        // earliest + latest remain unchanged — id2 was never at either end.
        (cursor,,) = h.earliest(1, CompletionFilter.ALL);
        assertEq(cursor, id1, "earliest is still id1");
        (cursor,,) = h.latest(1, CompletionFilter.ALL);
        assertEq(cursor, id3, "latest is still id3");
    }

    /// Cancelling the head advances `earliestActionOfType` to the next node.
    /// Verifies the head pointer updates and traversal from the new head
    /// works.
    function testCancelHeadAdvancesEarliest() external {
        uint256 id1 = h.schedule(1, 1500, hex"");
        uint256 id2 = h.schedule(1, 2500, hex"");

        h.cancel(id1);

        (uint256 cursor,,) = h.earliest(1, CompletionFilter.ALL);
        assertEq(cursor, id2, "earliest advances to id2 after id1 cancelled");

        // Walking prev from the new earliest returns 0 (head has no prev).
        (cursor,,) = h.prevOf(id2, 1, CompletionFilter.ALL);
        assertEq(cursor, 0, "prev of new head is 0");
    }

    /// Cancelling the tail moves `latestActionOfType` back to the prior node.
    /// Verifies the tail pointer updates.
    function testCancelTailRetreatsLatest() external {
        uint256 id1 = h.schedule(1, 1500, hex"");
        uint256 id2 = h.schedule(1, 2500, hex"");

        h.cancel(id2);

        (uint256 cursor,,) = h.latest(1, CompletionFilter.ALL);
        assertEq(cursor, id1, "latest retreats to id1 after id2 cancelled");

        (cursor,,) = h.nextOf(id1, 1, CompletionFilter.ALL);
        assertEq(cursor, 0, "next of new tail is 0");
    }

    /// `nextActionOfType(from, ...)` / `prevActionOfType(from, ...)` walk from
    /// a cursor. Verify they skip masks that don't match and report the
    /// neighbouring node.
    function testNextAndPrevFromSpecificCursor() external {
        uint256 id1 = h.schedule(1, 1500, hex"");
        uint256 id2 = h.schedule(1, 2500, hex"");
        uint256 id3 = h.schedule(1, 3500, hex"");

        // next from id1 → id2.
        (uint256 cursor,,) = h.nextOf(id1, 1, CompletionFilter.ALL);
        assertEq(cursor, id2);

        // next from id3 → none (tail).
        (cursor,,) = h.nextOf(id3, 1, CompletionFilter.ALL);
        assertEq(cursor, 0);

        // prev from id3 → id2.
        (cursor,,) = h.prevOf(id3, 1, CompletionFilter.ALL);
        assertEq(cursor, id2);

        // prev from id1 → none (head).
        (cursor,,) = h.prevOf(id1, 1, CompletionFilter.ALL);
        assertEq(cursor, 0);
    }
}

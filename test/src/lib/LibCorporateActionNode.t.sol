// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {TraversalHarness} from "./TraversalHarness.sol";
import {
    ACTION_TYPE_STOCK_SPLIT_V1,
    ACTION_TYPE_STABLES_DIVIDEND_V1,
    VALID_ACTION_TYPES_MASK
} from "src/interface/ICorporateActionsV1.sol";

import {CompletionFilter, NODE_NONE} from "src/lib/LibCorporateActionNode.sol";
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

contract LibCorporateActionNodeTest is Test {
    TraversalHarness internal h;

    function setUp() public {
        h = new TraversalHarness();
        vm.warp(1000);
    }

    /// Empty list: every tuple-returning getter returns all zeros regardless
    /// of the mask or filter. Exercises the `cursor == NODE_NONE` short-circuit in
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

    /// A mask with no valid bit (zero, undefined bits only, or any fuzzed
    /// `rawMask` with the valid bits cleared) reverts `InvalidMask` from every
    /// getter, on the empty list (the mask check precedes the empty-list early
    /// return) and on a populated one.
    function testFuzzMaskWithNoValidBitsReverts(uint256 rawMask) external {
        uint256 mask = rawMask & ~VALID_ACTION_TYPES_MASK;
        assertEveryGetterRefusesMask(0);
        assertEveryGetterRefusesMask(mask);

        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");
        assertEveryGetterRefusesMask(0);
        assertEveryGetterRefusesMask(1 << 3);
        assertEveryGetterRefusesMask((1 << 3) | (1 << 4));
        assertEveryGetterRefusesMask(mask);
    }

    /// Any mask holding a valid bit passes the guard on every getter, and
    /// undefined bits beside a valid bit leave the match on that bit intact —
    /// a caller written against a future version that adds types still works.
    function testFuzzMaskWithAValidBitPasses(uint256 extraBits) external {
        uint256 id = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");

        uint256 mask = VALID_ACTION_TYPES_MASK | extraBits;
        h.latest(mask, CompletionFilter.ALL);
        h.earliest(mask, CompletionFilter.ALL);
        h.nextOf(NODE_NONE, mask, CompletionFilter.ALL);
        h.prevOf(NODE_NONE, mask, CompletionFilter.ALL);

        (uint256 cursor,,) = h.latest(ACTION_TYPE_STOCK_SPLIT_V1 | (1 << 3), CompletionFilter.ALL);
        assertEq(cursor, id, "valid bit in mask matches node with that bit set");
        (cursor,,) = h.latest(ACTION_TYPE_STOCK_SPLIT_V1 | (extraBits & ~VALID_ACTION_TYPES_MASK), CompletionFilter.ALL);
        assertEq(cursor, id, "fuzzed undefined bits beside the valid bit");
        (cursor,,) = h.latest(USER_TYPES_TEST_MASK, CompletionFilter.ALL);
        assertEq(cursor, id, "user-types mask matches via its valid bits");
    }

    /// Pending/completed filter moves the result as time passes. A node whose
    /// `effectiveTime` equals `block.timestamp` is COMPLETED, not PENDING —
    /// the predicate is `effectiveTime <= block.timestamp`.
    function testFilterTracksEffectiveTimeTransitions() external {
        uint256 a1 = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");
        uint256 a2 = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, hex"");

        assertWalksBothWays(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED, new uint256[](0));
        assertWalksBothWays(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING, cursors2(a1, a2));

        vm.warp(1500);
        assertWalksBothWays(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED, cursors1(a1));
        assertWalksBothWays(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING, cursors1(a2));

        vm.warp(3000);
        assertWalksBothWays(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED, cursors2(a1, a2));
        assertWalksBothWays(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING, new uint256[](0));
    }

    /// Cancelling the head, a middle node or the tail re-links the list: both
    /// walks visit exactly the surviving nodes, so `earliest` advances past a
    /// cancelled head, `latest` retreats past a cancelled tail, and
    /// `nextOf` / `prevOf` skip a cancelled middle node.
    function testCancelAnyNodeRelinksTraversal() external {
        uint256[3] memory ids = [
            h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex""),
            h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, hex""),
            h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 3500, hex"")
        ];
        for (uint256 k = 0; k < 3; k++) {
            uint256 snapshot = vm.snapshotState();
            h.cancel(ids[k]);
            uint256[] memory survivors = new uint256[](2);
            uint256 n;
            for (uint256 i = 0; i < 3; i++) {
                if (i != k) survivors[n++] = ids[i];
            }
            assertWalksBothWays(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL, survivors);
            vm.revertToState(snapshot);
        }
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

    /// Every (mask, filter) pair over the mixed list: the forward walk from
    /// `earliest` and the backward walk from `latest` visit exactly the
    /// matching nodes in list order, skipping non-matching types, never
    /// returning the `from` cursor itself, and ending in NODE_NONE at the
    /// list ends and at the completed/pending boundary. A multi-bit mask
    /// matches a node sharing any bit (`actionType & mask != 0`).
    function testWalksVisitMatchingNodesPerMaskAndFilter() external {
        buildMixedCompletedPendingList();
        assertWalksBothWays(
            USER_TYPES_TEST_MASK, CompletionFilter.ALL, cursors8(id1, id2, id3, id4, id5, id6, id7, id8)
        );
        assertWalksBothWays(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL, cursors5(id1, id3, id4, id6, id8));
        assertWalksBothWays(ACTION_TYPE_STABLES_DIVIDEND_V1, CompletionFilter.ALL, cursors3(id2, id5, id7));
        assertWalksBothWays(USER_TYPES_TEST_MASK, CompletionFilter.COMPLETED, cursors5(id1, id2, id3, id4, id5));
        assertWalksBothWays(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED, cursors3(id1, id3, id4));
        assertWalksBothWays(ACTION_TYPE_STABLES_DIVIDEND_V1, CompletionFilter.COMPLETED, cursors2(id2, id5));
        assertWalksBothWays(USER_TYPES_TEST_MASK, CompletionFilter.PENDING, cursors3(id6, id7, id8));
        assertWalksBothWays(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING, cursors2(id6, id8));
        assertWalksBothWays(ACTION_TYPE_STABLES_DIVIDEND_V1, CompletionFilter.PENDING, cursors1(id7));
    }

    /// A filter opposite to every node's completion state finds nothing in
    /// either direction.
    function testFilterOppositeToEveryNodeFindsNothing() external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");
        h.schedule(ACTION_TYPE_STABLES_DIVIDEND_V1, 2500, hex"");
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 3500, hex"");
        assertWalksBothWays(USER_TYPES_TEST_MASK, CompletionFilter.COMPLETED, new uint256[](0));

        vm.warp(4000);
        assertWalksBothWays(USER_TYPES_TEST_MASK, CompletionFilter.PENDING, new uint256[](0));
    }

    /// PENDING traversal returns 0 when the completion segment has no
    /// matching nodes, even when nodes matching the mask exist in the
    /// other segment. Cancel id7 (the only type-2 pending node) — type-2
    /// nodes still exist in the completed segment.
    function testNonMatchingMaskInSegmentReturnsZero() external {
        buildMixedCompletedPendingList();
        h.cancel(id7);

        assertWalksBothWays(ACTION_TYPE_STABLES_DIVIDEND_V1, CompletionFilter.PENDING, new uint256[](0));
        assertWalksBothWays(ACTION_TYPE_STABLES_DIVIDEND_V1, CompletionFilter.COMPLETED, cursors2(id2, id5));
    }

    /// Cancelled nodes are skipped during traversal under COMPLETED and
    /// PENDING filters, both directions.
    function testCancelMiddleNodeSkippedUnderCompletedAndPendingFilters() external {
        uint256 idA = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1100, hex"");
        uint256 idB = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1200, hex"");
        uint256 idC = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1300, hex"");
        uint256 idD = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 3500, hex"");
        uint256 idE = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 3600, hex"");
        uint256 idF = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 3700, hex"");

        // Cancel idB and idE BEFORE warp — both still pending so cancel is allowed.
        h.cancel(idB);
        h.cancel(idE);

        vm.warp(2000);
        assertWalksBothWays(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED, cursors2(idA, idC));
        assertWalksBothWays(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING, cursors2(idD, idF));
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

        CompletionFilter[3] memory filters =
            [CompletionFilter.ALL, CompletionFilter.COMPLETED, CompletionFilter.PENDING];
        for (uint256 f = 0; f < 3; f++) {
            (uint256 cursor,,) = h.nextOf(idA, USER_TYPES_TEST_MASK, filters[f]);
            assertEq(cursor, NODE_NONE, "next from cancelled idA");
            (cursor,,) = h.prevOf(idB, USER_TYPES_TEST_MASK, filters[f]);
            assertEq(cursor, NODE_NONE, "prev from cancelled idB");
        }
    }

    /// Nodes scheduled with the same `effectiveTime` are returned in
    /// insertion order forward and reverse-insertion order backward.
    function testTraversalRespectsTiedEffectiveTimeOrdering() external {
        uint256 first = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");
        uint256 second = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");
        uint256 third = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, hex"");
        vm.warp(2000);

        assertWalksBothWays(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL, cursors3(first, second, third));
        assertWalksBothWays(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED, cursors3(first, second, third));
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

    /// For any random list, every traversal invariant holds for every
    /// (mask, filter) — see `assertTraversalInvariants`.
    function testFuzzTraversalInvariants(uint8 nodeCount, uint64 warpTo, uint256 seed) external {
        warpTo = uint64(bound(warpTo, 1, 10_000));
        uint256[] memory ids;
        (ids, seed) = scheduleRandomList(bound(nodeCount, 1, 12), warpTo, seed);
        vm.warp(warpTo + uint64((seed >> 16) % 100));
        assertTraversalInvariants(ids, new bool[](ids.length));
    }

    /// Random schedule + cancel sequences preserve every traversal
    /// invariant, with cancelled nodes excluded from the brute force.
    function testFuzzTraversalInvariantsUnderCancellations(uint8 nodeCount, uint64 warpTo, uint256 seed) external {
        warpTo = uint64(bound(warpTo, 1, 10_000));
        uint256[] memory ids;
        (ids, seed) = scheduleRandomList(bound(nodeCount, 2, 12), warpTo, seed);

        // Every node is still pending here, so any of them can be cancelled.
        bool[] memory cancelled = new bool[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            seed = uint256(keccak256(abi.encode(seed, "cancel", i)));
            if ((seed & 3) == 0) {
                h.cancel(ids[i]);
                cancelled[i] = true;
            }
        }

        vm.warp(warpTo + uint64((seed >> 16) % 100));
        assertTraversalInvariants(ids, cancelled);
    }

    /// Schedules `nodeCount` random split/dividend nodes, each effective
    /// after `warpTo`, returning their ids and the advanced seed.
    function scheduleRandomList(uint256 nodeCount, uint64 warpTo, uint256 seed)
        internal
        returns (uint256[] memory, uint256)
    {
        vm.warp(warpTo);
        uint256[] memory ids = new uint256[](nodeCount);
        for (uint256 i = 0; i < nodeCount; i++) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint256 actionType = (seed & 1) == 0 ? ACTION_TYPE_STOCK_SPLIT_V1 : ACTION_TYPE_STABLES_DIVIDEND_V1;
            ids[i] = h.schedule(actionType, uint64(warpTo + 1 + (seed >> 8) % 100), hex"");
        }
        return (ids, seed);
    }

    /// For every (mask, filter): `earliest` and `latest` are NODE_NONE iff no
    /// live node matches (brute force over `ids`), each returned cursor
    /// matches mask and filter, and walking forward from `earliest` reaches
    /// `latest` (and backward from `latest` reaches `earliest`) through
    /// matching cursors in fewer hops than there are nodes.
    function assertTraversalInvariants(uint256[] memory ids, bool[] memory cancelled) internal view {
        uint256[3] memory masks = [ACTION_TYPE_STOCK_SPLIT_V1, ACTION_TYPE_STABLES_DIVIDEND_V1, USER_TYPES_TEST_MASK];
        CompletionFilter[3] memory filters =
            [CompletionFilter.ALL, CompletionFilter.COMPLETED, CompletionFilter.PENDING];

        for (uint256 m = 0; m < 3; m++) {
            for (uint256 f = 0; f < 3; f++) {
                bool anyMatch = false;
                for (uint256 i = 0; i < ids.length; i++) {
                    if (!cancelled[i] && nodeMatches(ids[i], masks[m], filters[f])) {
                        anyMatch = true;
                        break;
                    }
                }

                (uint256 earliestCursor,,) = h.earliest(masks[m], filters[f]);
                (uint256 latestCursor,,) = h.latest(masks[m], filters[f]);
                assertEq(earliestCursor != NODE_NONE, anyMatch, "earliest finds a node iff a live node matches");
                assertEq(latestCursor != NODE_NONE, anyMatch, "latest finds a node iff a live node matches");
                if (!anyMatch) continue;

                assertTrue(nodeMatches(earliestCursor, masks[m], filters[f]), "earliest matches mask and filter");
                assertTrue(nodeMatches(latestCursor, masks[m], filters[f]), "latest matches mask and filter");
                assertWalkReaches(earliestCursor, latestCursor, masks[m], filters[f], true, ids.length);
                assertWalkReaches(latestCursor, earliestCursor, masks[m], filters[f], false, ids.length);
            }
        }
    }

    function assertWalkReaches(
        uint256 cursor,
        uint256 target,
        uint256 mask,
        CompletionFilter filter,
        bool forward,
        uint256 nodeCount
    ) internal view {
        uint256 hops;
        while (cursor != target) {
            if (forward) {
                (cursor,,) = h.nextOf(cursor, mask, filter);
            } else {
                (cursor,,) = h.prevOf(cursor, mask, filter);
            }
            hops++;
            assertTrue(cursor != NODE_NONE, "walk hit NODE_NONE before reaching the other end");
            assertLt(hops, nodeCount, "walk exceeded node count");
            assertTrue(nodeMatches(cursor, mask, filter), "walked cursor matches mask and filter");
        }
    }

    function nodeMatches(uint256 cursor, uint256 mask, CompletionFilter filter) internal view returns (bool) {
        (uint256 actionType, uint64 effectiveTime) = h.nodeAt(cursor);
        if (actionType & mask == 0) return false;
        if (filter == CompletionFilter.ALL) return true;
        // The test's own oracle, re-deriving the complete/pending split from the
        // same rule the library uses. Skew would move both sides together.
        // forge-lint: disable-next-line(block-timestamp)
        return (effectiveTime <= block.timestamp) == (filter == CompletionFilter.COMPLETED);
    }

    function assertEveryGetterRefusesMask(uint256 mask) internal {
        vm.expectRevert(InvalidMask.selector);
        h.latest(mask, CompletionFilter.ALL);
        vm.expectRevert(InvalidMask.selector);
        h.earliest(mask, CompletionFilter.ALL);
        vm.expectRevert(InvalidMask.selector);
        h.nextOf(NODE_NONE, mask, CompletionFilter.ALL);
        vm.expectRevert(InvalidMask.selector);
        h.prevOf(NODE_NONE, mask, CompletionFilter.ALL);
    }

    /// Walks forward from `earliest` asserting the visit order is `expected`,
    /// then backward from `latest` asserting the reverse order; both walks
    /// must end in NODE_NONE after the last expected cursor.
    function assertWalksBothWays(uint256 mask, CompletionFilter filter, uint256[] memory expected) internal view {
        (uint256 cursor,,) = h.earliest(mask, filter);
        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(cursor, expected[i], "forward cursor mismatch");
            (cursor,,) = h.nextOf(cursor, mask, filter);
        }
        assertEq(cursor, NODE_NONE, "forward cursor not terminated");

        (cursor,,) = h.latest(mask, filter);
        for (uint256 i = expected.length; i > 0; i--) {
            assertEq(cursor, expected[i - 1], "backward cursor mismatch");
            (cursor,,) = h.prevOf(cursor, mask, filter);
        }
        assertEq(cursor, NODE_NONE, "backward cursor not terminated");
    }

    function cursors1(uint256 a) internal pure returns (uint256[] memory) {
        uint256[] memory r = new uint256[](1);
        r[0] = a;
        return r;
    }

    function cursors2(uint256 a, uint256 b) internal pure returns (uint256[] memory) {
        uint256[] memory r = new uint256[](2);
        r[0] = a;
        r[1] = b;
        return r;
    }

    function cursors3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256[] memory) {
        uint256[] memory r = new uint256[](3);
        r[0] = a;
        r[1] = b;
        r[2] = c;
        return r;
    }

    function cursors5(uint256 a, uint256 b, uint256 c, uint256 d, uint256 e) internal pure returns (uint256[] memory) {
        uint256[] memory r = new uint256[](5);
        r[0] = a;
        r[1] = b;
        r[2] = c;
        r[3] = d;
        r[4] = e;
        return r;
    }

    function cursors8(uint256 a, uint256 b, uint256 c, uint256 d, uint256 e, uint256 f, uint256 g, uint256 h_)
        internal
        pure
        returns (uint256[] memory)
    {
        uint256[] memory r = new uint256[](8);
        r[0] = a;
        r[1] = b;
        r[2] = c;
        r[3] = d;
        r[4] = e;
        r[5] = f;
        r[6] = g;
        r[7] = h_;
        return r;
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibCorporateAction} from "src/lib/LibCorporateAction.sol";
import {CompletionFilter, LibCorporateActionNode} from "src/lib/LibCorporateActionNode.sol";

/// @dev Thin harness: exposes the four tuple-returning traversal getters via
/// external calls so the library functions can be exercised directly (not
/// through the facet). Also schedules actions into the harness's own storage
/// namespace so there is no ambient state between tests.
contract TraversalHarness {
    function schedule(uint256 actionType, uint64 effectiveTime, bytes memory parameters) external returns (uint256) {
        return LibCorporateAction.schedule(actionType, effectiveTime, parameters);
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

    /// Mask filtering: nodes of action type `2` must not surface when the
    /// caller queries with mask `1`, and vice versa. Exercises the bitmap
    /// check in the underlying `next/prevOfType` walk.
    function testMaskFiltersOutNonMatchingType() external {
        h.schedule(1, 1500, hex"");
        uint256 id2 = h.schedule(2, 2500, hex"");

        // Query with mask=2 skips the mask=1 node.
        (uint256 cursor,,) = h.earliest(2, CompletionFilter.ALL);
        assertEq(cursor, id2);

        (cursor,,) = h.latest(2, CompletionFilter.ALL);
        assertEq(cursor, id2);

        // Combined mask (1 | 2) picks whichever direction is walked.
        (cursor,,) = h.earliest(3, CompletionFilter.ALL);
        assertEq(cursor, 1, "earliest of ALL types is the head");

        (cursor,,) = h.latest(3, CompletionFilter.ALL);
        assertEq(cursor, id2, "latest of ALL types is the tail");
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

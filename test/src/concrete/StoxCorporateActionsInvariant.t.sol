// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {BALANCE_MIGRATION_TYPES_MASK} from "../../../src/interface/ICorporateActionsV1.sol";
import {CorporateActionNode, CompletionFilter, NODE_NONE} from "../../../src/lib/LibCorporateActionNode.sol";
import {InvariantVault} from "./InvariantVault.sol";
import {InvariantReceipt} from "./InvariantReceipt.sol";
import {StoxCorporateActionsHandler} from "./StoxCorporateActionsHandler.sol";

/// @title StoxCorporateActionsInvariantTest
/// @notice Stateful invariant suite for the corporate-actions system. A
/// `StoxCorporateActionsHandler` drives the vault through random sequences of
/// schedule / cancel / warp / mint / burn / transfer / touch operations. After
/// every handler call, the invariant sweep asserts that the six system
/// properties defined below still hold.
contract StoxCorporateActionsInvariantTest is Test {
    InvariantVault internal vault;
    InvariantReceipt internal receipt;
    StoxCorporateActionsHandler internal handler;

    function setUp() public {
        vault = new InvariantVault();
        receipt = new InvariantReceipt();
        receipt.testInit(address(vault));
        handler = new StoxCorporateActionsHandler(vault, receipt);
        targetContract(address(handler));
    }

    /// `InvariantVault.nextOfType` on an empty (pre-bootstrap) list returns
    /// `(NODE_NONE, 0, 0)`: the metadata read is skipped when the walk
    /// returns `NODE_NONE`.
    function testInvariantVaultNextOfTypeGuardsOnNodeNone() external view {
        (uint256 cursor, uint256 actionType, uint64 effectiveTime) =
            vault.nextOfType(NODE_NONE, BALANCE_MIGRATION_TYPES_MASK, CompletionFilter.COMPLETED);
        assertEq(cursor, NODE_NONE, "no-match returns NODE_NONE cursor");
        assertEq(actionType, 0, "no-match returns zero actionType (read skipped)");
        assertEq(uint256(effectiveTime), 0, "no-match returns zero effectiveTime (read skipped)");
    }

    /// Invariant 1: list integrity. Walking from head forward along `next`
    /// pointers and from tail backward along `prev` pointers visits the same
    /// set of reachable nodes. Same count both ways; no cycles in either
    /// direction (enforced by bounding the walk to nodesLength iterations).
    function invariantListIntegrity() external view {
        uint256 len = vault.nodesLength();

        if (len == 0) {
            return; // pre-bootstrap: array empty, head/tail unread.
        }

        uint256 head = vault.listHead();
        uint256 tail = vault.listTail();

        // Once `nodes.length > 0`, bootstrap guarantees at least one
        // reachable node, so head and tail are real indices.
        assertTrue(head != NODE_NONE, "invariant 1: head must be a real index when nodes.length > 0");
        assertTrue(tail != NODE_NONE, "invariant 1: tail must be a real index when nodes.length > 0");

        // Forward walk from head: pin each `prev` link points back to the
        // previously visited node, node indices are in-bounds, and the walk
        // terminates exactly at `tail`.
        uint256 forwardCount = 0;
        uint256 current = head;
        uint256 previous = NODE_NONE;
        while (current != NODE_NONE && forwardCount <= len) {
            assertLt(current, len, "invariant 1: forward node index must be in bounds");
            CorporateActionNode memory node = vault.getNode(current);
            assertEq(node.prev, previous, "invariant 1: forward prev link must point back to previous");
            forwardCount++;
            previous = current;
            current = node.next;
        }
        assertTrue(forwardCount <= len, "invariant 1: forward walk must terminate (no cycles)");
        assertEq(previous, tail, "invariant 1: forward walk must end at tail");

        // Backward walk from tail: pin each `next` link points forward to the
        // previously visited node and the walk terminates exactly at `head`.
        uint256 backwardCount = 0;
        current = tail;
        uint256 next = NODE_NONE;
        while (current != NODE_NONE && backwardCount <= len) {
            assertLt(current, len, "invariant 1: backward node index must be in bounds");
            CorporateActionNode memory node = vault.getNode(current);
            assertEq(node.next, next, "invariant 1: backward next link must point forward to next");
            backwardCount++;
            next = current;
            current = node.prev;
        }
        assertTrue(backwardCount <= len, "invariant 1: backward walk must terminate (no cycles)");
        assertEq(next, head, "invariant 1: backward walk must end at head");

        assertEq(forwardCount, backwardCount, "invariant 1: forward and backward walks must visit same count");
    }

    /// Invariant 2: time ordering. Adjacent reachable nodes have
    /// non-decreasing `effectiveTime`. Ties are permitted (stable insertion
    /// places later-scheduled equal-time nodes after earlier ones).
    function invariantTimeOrdering() external view {
        uint256 len = vault.nodesLength();
        if (len == 0) return;

        uint256 current = vault.listHead();
        uint64 lastTime = 0;
        uint256 iterations = 0;

        while (current != NODE_NONE && iterations <= len) {
            iterations++;
            CorporateActionNode memory node = vault.getNode(current);
            assertGe(node.effectiveTime, lastTime, "invariant 2: adjacent nodes must be time-ordered");
            lastTime = node.effectiveTime;
            current = node.next;
        }
    }

    /// Invariant 3: per-actor cursor monotonicity in list order. Each
    /// actor's current cursor is the last observed one or reachable forward
    /// from it along `next` pointers. Also enforced inline in the handler
    /// via `_recordCursor`.
    function invariantCursorMonotonicity() external view {
        uint256 actorCount = handler.actorCount();
        for (uint256 i = 0; i < actorCount; i++) {
            address a = handler.actor(i);
            uint256 current = vault.migrationCursor(a);
            uint256 last = handler.lastSeenCursor(a);
            assertTrue(
                handler.cursorReachableForward(last, current),
                "invariant 3: per-actor cursor must advance forward in list order"
            );
        }
    }

    /// Invariant 4 is a post-call property: after `migrateAccount(account)`
    /// returns inside `_update`, that account's cursor equals
    /// `totalSupplyLatestCursor`. An actor not touched since a later split
    /// completed sits at an older cursor, so it is enforced inline in the
    /// handler (`_assertCursorInvariant`) rather than at rest here.

    /// Invariant 5: the sum of per-actor effective balances does not exceed
    /// `totalSupply()`. Equality holds once every actor has migrated through
    /// every completed split; before that, `totalSupply` may overestimate by
    /// at most (#migrated-actors × #completed-splits) wei of truncation.
    function invariantSumBalancesLeqTotalSupply() external view {
        uint256 sum = 0;
        uint256 actorCount = handler.actorCount();
        for (uint256 i = 0; i < actorCount; i++) {
            sum += vault.balanceOf(handler.actor(i));
        }
        uint256 total = vault.totalSupply();
        assertLe(sum, total, "invariant 5: sum(balanceOf) must not exceed totalSupply");
    }

    /// Invariant 7: with no stock split past its effective time,
    /// `totalSupply()` is `Σmints − Σburns`. Gated on `hasCompletedSplit()`
    /// because `effectiveTotalSupply` applies multipliers as soon as a
    /// split's effective time has passed, before any `fold()` advances
    /// `totalSupplyLatestCursor`.
    function invariantNoSplitSupplyEqualsNetMinted() external view {
        if (vault.hasCompletedSplit()) return;

        uint256 netMinted = handler.totalMinted() - handler.totalBurned();
        assertEq(vault.totalSupply(), netMinted, "invariant 7: totalSupply == Sum(mints) - Sum(burns) with no split");
    }

    /// Invariant 6: `totalSupplyLatestCursor` is either `NODE_NONE` (the
    /// `ensureBootstrap`-set sentinel meaning "no fold has run yet") or
    /// points at a node whose effective time is in the past. It must also
    /// not exceed the nodes array bounds.
    function invariantTotalSupplyLatestSplitValid() external view {
        // Pre-bootstrap: nodes array empty, latestCursor at default 0, but
        // there are no nodes to validate against. Skip.
        if (vault.nodesLength() == 0) return;

        uint256 latest = vault.totalSupplyLatestCursor();
        if (latest == NODE_NONE) return;

        assertLt(latest, vault.nodesLength(), "invariant 6: totalSupplyLatestCursor must be a valid node index");

        CorporateActionNode memory node = vault.getNode(latest);
        assertLe(
            uint256(node.effectiveTime),
            block.timestamp,
            "invariant 6: totalSupplyLatestCursor must point at a past-effectiveTime node"
        );
        assertTrue(
            node.actionType & BALANCE_MIGRATION_TYPES_MASK != 0,
            "invariant 6: totalSupplyLatestCursor must point at a node walked by migration (init or stock split)"
        );
    }

    /// Share-receipt proportionality. The handler exposes deposit,
    /// withdraw, and touch operations and no share-only transfers, so
    /// every actor's share balance equals their receipt balance at the
    /// actor's assigned id.
    function invariantShareReceiptProportionality() external view {
        for (uint256 i = 0; i < 5; i++) {
            address a = handler.actor(i);
            uint256 id = i + 1;
            assertEq(
                receipt.balanceOf(a, id),
                vault.balanceOf(a),
                "invariant: receipt.balanceOf(actor, id) == vault.balanceOf(actor) under deposit/withdraw-only topology"
            );
        }
    }

    /// Per-(holder, id) receipt cursor monotonicity. Enforced inline in
    /// the handler via `_recordReceiptCursor`; re-asserted here for every
    /// tracked (actor, id) pair.
    function invariantReceiptCursorMonotonicity() external view {
        for (uint256 i = 0; i < 5; i++) {
            address a = handler.actor(i);
            uint256 id = i + 1;
            assertTrue(
                handler.cursorReachableForward(handler.lastSeenReceiptCursor(a, id), receipt.holderIdCursor(a, id)),
                "invariant: per-(holder, id) receipt cursor must advance forward in list order"
            );
        }
    }
}

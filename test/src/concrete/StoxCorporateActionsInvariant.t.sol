// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {LibCorporateAction, ACTION_TYPE_STOCK_SPLIT_V1} from "../../../src/lib/LibCorporateAction.sol";
import {LibERC20Storage} from "../../../src/lib/LibERC20Storage.sol";
import {LibTotalSupply} from "../../../src/lib/LibTotalSupply.sol";
import {
    CorporateActionNode,
    CompletionFilter,
    LibCorporateActionNode
} from "../../../src/lib/LibCorporateActionNode.sol";
import {LibTestCorporateAction} from "../../lib/LibTestCorporateAction.sol";
import {LibStockSplit} from "../../../src/lib/LibStockSplit.sol";

/// @dev Auth-bypassed vault subclass used by the invariant harness. Mirrors
/// the production `StoxReceiptVault._update` flow exactly, only skipping the
/// `OffchainAssetReceiptVault` authorizer/freeze middle layer — the migration
/// semantics under test live entirely in `StoxReceiptVault` and the libraries
/// it calls. Also exposes the internal cursor / split state so invariants can
/// read it.
contract InvariantVault is StoxReceiptVault {
    function _update(address from, address to, uint256 amount) internal override {
        LibTotalSupply.fold();
        _migrateAccount(from);
        _migrateAccount(to);

        ERC20Upgradeable._update(from, to, amount);

        if (from == address(0)) {
            LibTotalSupply.onMint(amount);
        } else if (to == address(0)) {
            LibTotalSupply.onBurn(amount);
        }
    }

    function publicUpdate(address from, address to, uint256 amount) external {
        _update(from, to, amount);
    }

    function publicSchedule(uint256 actionType, uint64 effectiveTime, bytes memory parameters)
        external
        returns (uint256)
    {
        return LibCorporateAction.schedule(actionType, effectiveTime, parameters);
    }

    function publicCancel(uint256 actionIndex) external {
        LibCorporateAction.cancel(actionIndex);
    }

    function migrationCursor(address account) external view returns (uint256) {
        return LibCorporateAction.getStorage().accountMigrationCursor[account];
    }

    function totalSupplyLatestSplit() external view returns (uint256) {
        return LibCorporateAction.getStorage().totalSupplyLatestSplit;
    }

    function listHead() external view returns (uint256) {
        return LibTestCorporateAction.head();
    }

    function listTail() external view returns (uint256) {
        return LibTestCorporateAction.tail();
    }

    function getNode(uint256 index) external view returns (CorporateActionNode memory) {
        return LibCorporateAction.getStorage().nodes[index];
    }

    function nodesLength() external view returns (uint256) {
        return LibCorporateAction.getStorage().nodes.length;
    }

    function rawStoredBalance(address account) external view returns (uint256) {
        return LibERC20Storage.underlyingBalance(account);
    }

    /// @dev Whether any stock split in the list has reached its effective
    /// time. `effectiveTotalSupply` applies multipliers once this is true
    /// even if `fold()` has not yet been called to update
    /// `totalSupplyLatestSplit`, so invariants that depend on the
    /// no-multiplier regime must gate on this rather than
    /// `totalSupplyLatestSplit == 0`.
    function hasCompletedSplit() external view returns (bool) {
        return LibCorporateActionNode.nextOfType(0, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED) != 0;
    }
}

/// @dev Handler for the corporate-actions invariant suite. Foundry's invariant
/// fuzzer targets this contract's external functions; each call drives one
/// operation against the vault with bounded, fuzzer-supplied inputs. After
/// every operation that migrates an account, the handler asserts the cursor-
/// equality invariant inline so violations surface at the offending call
/// rather than at the periodic invariant sweep.
///
/// Actors: a fixed set of 5 addresses plus the zero address (for mint/burn).
/// Multipliers: bounded to {1, 2, 3} (and their reciprocals via fractional
/// form) to keep Float precision inside well-tested territory without losing
/// the fractional vs integer distinction.
/// Amounts: bounded per-op against current balances to avoid OZ underflow
/// reverts that would mask real bugs.
contract StoxCorporateActionsHandler is Test {
    InvariantVault public immutable VAULT;

    /// @dev Fixed set of actors the handler cycles through.
    address[5] public actors;

    /// @dev Total number of mints executed (for ghost-variable assertions).
    uint256 public totalMinted;
    /// @dev Total number of burns executed.
    uint256 public totalBurned;
    /// @dev Track the most recent cursor value per actor, to verify
    /// monotonicity (invariant 3).
    mapping(address => uint256) public lastSeenCursor;

    constructor(InvariantVault vault_) {
        VAULT = vault_;
        actors[0] = address(0xA11CE);
        actors[1] = address(0xB0B);
        actors[2] = address(0xCA401);
        actors[3] = address(0xDAFE);
        actors[4] = address(0xEFFE);
        // Start time past 0 so `block.timestamp > 0` and fresh effectiveTime
        // values can land strictly in the future.
        vm.warp(1000);
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _asFloat(int256 coefficient, int256 exponent) internal pure returns (Float) {
        return LibDecimalFloat.packLossless(coefficient, exponent);
    }

    /// @dev Bounded set of stock split multipliers used by schedule. Fractional
    /// reverse splits (1/3, 1/2) are produced by `div(packLossless(1,0),
    /// packLossless(n,0))`.
    function _multiplier(uint256 seed) internal pure returns (bytes memory) {
        uint256 bucket = seed % 6;
        if (bucket == 0) return LibStockSplit.encodeParametersV1(_asFloat(2, 0));
        if (bucket == 1) return LibStockSplit.encodeParametersV1(_asFloat(3, 0));
        if (bucket == 2) return LibStockSplit.encodeParametersV1(_asFloat(1, 0)); // 1x — a no-op split (valid)
        if (bucket == 3) {
            return LibStockSplit.encodeParametersV1(LibDecimalFloat.div(_asFloat(1, 0), _asFloat(2, 0)));
        }
        if (bucket == 4) {
            return LibStockSplit.encodeParametersV1(LibDecimalFloat.div(_asFloat(1, 0), _asFloat(3, 0)));
        }
        // bucket 5: another 2x (slight weighting toward common cases)
        return LibStockSplit.encodeParametersV1(_asFloat(2, 0));
    }

    /// @dev Schedule a stock split at a bounded future time. Time is drawn
    /// from a small window ahead of `block.timestamp` so multiple scheduled
    /// actions end up in mixed order inside the list.
    function schedule(uint256 multiplierSeed, uint8 timeDelta) external {
        // time in [1, 256] seconds in the future.
        uint64 effectiveTime = uint64(block.timestamp + 1 + (uint256(timeDelta) % 256));
        bytes memory parameters = _multiplier(multiplierSeed);
        VAULT.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, effectiveTime, parameters);
    }

    /// @dev Cancel a scheduled action. Bounded to the current nodes array
    /// length so it hits legitimate indices most of the time; indices that
    /// point at already-cancelled or already-completed nodes revert cleanly
    /// (caught by the inline try / ignore pattern).
    function cancel(uint256 indexSeed) external {
        uint256 len = VAULT.nodesLength();
        if (len <= 1) return; // only sentinel; nothing to cancel
        uint256 actionIndex = (indexSeed % (len - 1)) + 1; // in [1, len-1]
        // forge-lint: disable-next-line(unchecked-call)
        try VAULT.publicCancel(actionIndex) {} catch {}
    }

    /// @dev Advance block.timestamp by a bounded delta so scheduled actions
    /// cross into the past and `fold()` picks them up on the next _update.
    function warp(uint8 delta) external {
        vm.warp(block.timestamp + 1 + uint256(delta));
    }

    /// @dev Mint a bounded amount to a fuzzer-selected actor.
    function mint(uint256 actorSeed, uint64 amountSeed) external {
        address to = _actor(actorSeed);
        uint256 amount = uint256(amountSeed) % 1e24 + 1;
        VAULT.publicUpdate(address(0), to, amount);
        totalMinted += amount;
        _assertCursorInvariant(to);
        _recordCursor(to);
    }

    /// @dev Burn a bounded amount from a fuzzer-selected actor, capped at the
    /// actor's current effective balance so OZ doesn't underflow.
    function burn(uint256 actorSeed, uint64 amountSeed) external {
        address from = _actor(actorSeed);
        uint256 effective = VAULT.balanceOf(from);
        if (effective == 0) return;
        uint256 amount = uint256(amountSeed) % (effective + 1);
        if (amount == 0) return;
        VAULT.publicUpdate(from, address(0), amount);
        totalBurned += amount;
        _assertCursorInvariant(from);
        _recordCursor(from);
    }

    /// @dev Transfer a bounded amount between two fuzzer-selected actors,
    /// capped at the sender's effective balance.
    function transfer(uint256 fromSeed, uint256 toSeed, uint64 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        if (from == to) return; // no-op self transfer not interesting
        uint256 effective = VAULT.balanceOf(from);
        if (effective == 0) return;
        uint256 amount = uint256(amountSeed) % (effective + 1);
        VAULT.publicUpdate(from, to, amount);
        _assertCursorInvariant(from);
        _assertCursorInvariant(to);
        _recordCursor(from);
        _recordCursor(to);
    }

    /// @dev Touch an actor (0-amount self-send) to force migration without
    /// any balance change. Exposes cursor-only advancement paths.
    function touch(uint256 actorSeed) external {
        address a = _actor(actorSeed);
        VAULT.publicUpdate(a, a, 0);
        _assertCursorInvariant(a);
        _recordCursor(a);
    }

    // -----------------------------------------------------------------------
    // Ghost assertions / recording

    /// @dev Assert cursor invariant #4: after any migration, the actor's
    /// cursor equals the global `totalSupplyLatestSplit`.
    function _assertCursorInvariant(address a) internal view {
        assertEq(
            VAULT.migrationCursor(a),
            VAULT.totalSupplyLatestSplit(),
            "invariant 4: cursor(actor) == totalSupplyLatestSplit after _migrateAccount"
        );
    }

    /// @dev Record the actor's cursor to check monotonicity (invariant 3).
    /// Cursor IDs are allocation indices, not chronological positions — a
    /// later-scheduled action with an earlier effectiveTime is inserted
    /// before older actions in the list, so a valid migration can move a
    /// cursor to a numerically lower id. Monotonicity is therefore defined
    /// in LIST order (forward along `next` pointers), not numeric order.
    function _recordCursor(address a) internal {
        uint256 current = VAULT.migrationCursor(a);
        uint256 last = lastSeenCursor[a];
        assertTrue(
            cursorReachableForward(last, current), "invariant 3: per-actor cursor must advance forward in list order"
        );
        lastSeenCursor[a] = current;
    }

    /// @dev True iff `current` is `last` itself or reachable by walking
    /// `next` pointers starting from `last`. Walk is bounded by
    /// `nodesLength` so a cycle (violation of invariant 1) does not hang.
    /// External so framework-level invariants can call it too.
    function cursorReachableForward(uint256 last, uint256 current) public view returns (bool) {
        if (last == current) return true;
        if (last == 0) return true;

        uint256 len = VAULT.nodesLength();
        uint256 cursor = last;
        for (uint256 i = 0; i < len && cursor != 0; i++) {
            cursor = VAULT.getNode(cursor).next;
            if (cursor == current) return true;
        }
        return false;
    }

    function actorCount() external pure returns (uint256) {
        return 5;
    }

    function actor(uint256 i) external view returns (address) {
        return actors[i];
    }
}

/// @title StoxCorporateActionsInvariantTest
/// @notice Stateful invariant suite for the corporate-actions system. A
/// `StoxCorporateActionsHandler` drives the vault through random sequences of
/// schedule / cancel / warp / mint / burn / transfer / touch operations. After
/// every handler call, the invariant sweep asserts that the six system
/// properties defined below still hold.
contract StoxCorporateActionsInvariantTest is Test {
    InvariantVault internal vault;
    StoxCorporateActionsHandler internal handler;

    function setUp() public {
        vault = new InvariantVault();
        handler = new StoxCorporateActionsHandler(vault);
        targetContract(address(handler));
    }

    /// Invariant 1: list integrity. Walking from head forward along `next`
    /// pointers and from tail backward along `prev` pointers visits the same
    /// set of reachable nodes. Same count both ways; no cycles in either
    /// direction (enforced by bounding the walk to nodesLength iterations).
    function invariantListIntegrity() external view {
        uint256 len = vault.nodesLength();
        uint256 head = vault.listHead();
        uint256 tail = vault.listTail();

        if (head == 0 && tail == 0) {
            return; // empty list — trivially consistent
        }
        assertTrue(head != 0 && tail != 0, "invariant 1: head and tail must be set together");

        // Forward walk from head: pin each `prev` link points back to the
        // previously visited node, node indices are in-bounds, and the walk
        // terminates exactly at `tail`.
        uint256 forwardCount = 0;
        uint256 current = head;
        uint256 previous = 0;
        while (current != 0 && forwardCount <= len) {
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
        uint256 next = 0;
        while (current != 0 && backwardCount <= len) {
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
        uint256 head = vault.listHead();
        if (head == 0) return;

        uint256 current = head;
        uint64 lastTime = 0;
        uint256 iterations = 0;
        uint256 len = vault.nodesLength();

        while (current != 0 && iterations <= len) {
            iterations++;
            CorporateActionNode memory node = vault.getNode(current);
            assertGe(node.effectiveTime, lastTime, "invariant 2: adjacent nodes must be time-ordered");
            lastTime = node.effectiveTime;
            current = node.next;
        }
    }

    /// Invariant 3: per-actor cursor monotonicity is enforced inline in the
    /// handler via `_recordCursor`. This function exists so the invariant
    /// suite has an assertion at the framework level too. Cursor IDs are
    /// allocation indices so numeric comparison is wrong — assert that the
    /// current cursor is either the same as the last observed one or
    /// reachable forward from it along `next` pointers.
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

    /// Invariant 4 is a POST-CALL property, not a resting invariant:
    /// after `_migrateAccount(account)` returns inside `_update`, that
    /// specific account's cursor equals `totalSupplyLatestSplit`. It does
    /// NOT hold for every actor at every moment — an actor touched before
    /// a later split completes legitimately sits at the older cursor until
    /// they next transact, and that's the whole point of lazy migration.
    ///
    /// The invariant is therefore enforced inline at the handler level: after
    /// every mint / burn / transfer / touch the handler calls
    /// `_assertCursorInvariant` on the specific actor(s) that were just
    /// migrated. A violation there fails the invariant suite immediately at
    /// the offending handler call. There is no framework-level re-check
    /// here because the "at rest" version of the property is simply false.

    /// Invariant 5: the sum of per-actor effective balances must not exceed
    /// `totalSupply()`. Equality holds once every actor has migrated through
    /// every completed split; before that, `totalSupply` may be a slight
    /// overestimate bounded by (#migrated-actors × #completed-splits) wei of
    /// truncation drift. The harness's bounded actor set and bounded
    /// multipliers keep the gap small; this assertion pins the one-sided
    /// bound regardless.
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
    /// `totalSupply()` is exactly `Σmints − Σburns`. This is the default
    /// state of every token until the first stock split reaches its
    /// effective time — the corporate-actions override must be a
    /// straight passthrough of OZ's `_totalSupply` in this regime and
    /// add no drift. Gates on `hasCompletedSplit()` rather than
    /// `totalSupplyLatestSplit == 0`: `effectiveTotalSupply` applies
    /// multipliers as soon as a split's effective time has passed, even
    /// if no subsequent `_update` has triggered `fold()` to advance the
    /// latest-split tracker.
    function invariantNoSplitSupplyEqualsNetMinted() external view {
        if (vault.hasCompletedSplit()) return;

        uint256 netMinted = handler.totalMinted() - handler.totalBurned();
        assertEq(vault.totalSupply(), netMinted, "invariant 7: totalSupply == Sum(mints) - Sum(burns) with no split");
    }

    /// Invariant 6: `totalSupplyLatestSplit` is either 0 (no split has ever
    /// folded) or points at a node whose effective time is in the past. It
    /// must also not exceed the nodes array bounds.
    function invariantTotalSupplyLatestSplitValid() external view {
        uint256 latest = vault.totalSupplyLatestSplit();
        if (latest == 0) return;

        assertLt(latest, vault.nodesLength(), "invariant 6: totalSupplyLatestSplit must be a valid node index");

        CorporateActionNode memory node = vault.getNode(latest);
        assertLe(
            uint256(node.effectiveTime),
            block.timestamp,
            "invariant 6: totalSupplyLatestSplit must point at a past-effectiveTime node"
        );
        assertTrue(
            node.actionType & ACTION_TYPE_STOCK_SPLIT_V1 != 0,
            "invariant 6: totalSupplyLatestSplit must point at a stock split node"
        );
    }
}

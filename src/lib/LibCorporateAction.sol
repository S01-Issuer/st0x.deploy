// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {CorporateActionNode, CompletionFilter, LibCorporateActionNode, NODE_NONE} from "./LibCorporateActionNode.sol";
import {LibStockSplit} from "./LibStockSplit.sol";
import {LibERC20Storage} from "./LibERC20Storage.sol";
import {
    ACTION_TYPE_INIT_V1,
    ACTION_TYPE_STOCK_SPLIT_V1,
    ACTION_TYPE_STABLES_DIVIDEND_V1,
    VALID_ACTION_TYPES_MASK
} from "../interface/ICorporateActionsV1.sol";
import {
    EffectiveTimeInPast,
    ActionAlreadyComplete,
    ActionDoesNotExist,
    UnknownActionType
} from "../error/ErrCorporateAction.sol";

/// @dev ERC-7201 namespaced storage location for corporate actions,
/// derived in-source from the spec formula rather than hardcoded.
/// Evaluated at compile time, zero runtime cost.
bytes32 constant CORPORATE_ACTION_STORAGE_LOCATION =
    keccak256(abi.encode(uint256(keccak256("rain.storage.corporate-action.1")) - 1)) & ~bytes32(uint256(0xff));

/// @dev Permission hash for scheduling a corporate action via the authorizer.
bytes32 constant SCHEDULE_CORPORATE_ACTION = keccak256("SCHEDULE_CORPORATE_ACTION");

/// @dev Permission hash for cancelling a corporate action via the authorizer.
bytes32 constant CANCEL_CORPORATE_ACTION = keccak256("CANCEL_CORPORATE_ACTION");

/// @dev External identifier for V1 stock splits.
bytes32 constant STOCK_SPLIT_V1_TYPE_HASH = keccak256("st0x.corporate-actions.stock-split.1");

/// @title LibCorporateAction
/// @notice Library for corporate action diamond storage. Uses ERC-7201
/// namespaced storage to avoid collisions with existing vault storage slots.
/// Manages a doubly linked list of corporate actions ordered by effectiveTime.
/// There is no stored status or counters — an action is complete when its
/// effectiveTime is less than or equal to the current block timestamp.
///
/// Nodes are stored in a dynamic array. Index 0, when the array is non-empty,
/// is always the `ACTION_TYPE_INIT_V1` bootstrap node lazily created by
/// `_ensureBootstrap` on the first `schedule` call. User-scheduled actions
/// start at index 1. The null encoding for `prev`, `next`, and the "from
/// head/tail inclusive" sentinel for `nextOfType`/`prevOfType` is
/// `NODE_NONE` — value-level disambiguation, not positional, so a
/// real node at index 0 is never confused with "no node".
library LibCorporateAction {
    /// @custom:storage-location erc7201:rain.storage.corporate-action.1
    /// @dev **DO NOT REORDER — APPEND ONLY.** This struct lives at a fixed
    /// ERC-7201 namespaced slot inside an upgradeable beacon-proxy vault.
    /// Field offsets within the struct are positional: reordering any field,
    /// inserting in the middle, or changing a field type silently remaps
    /// live state on upgrade (the old `head` slot becomes the new `tail`
    /// slot, etc.). Consequences are catastrophic and undetectable from
    /// bytecode comparison. New state may only be added at the **end** of
    /// the struct, and the storage-layout pin test in
    /// `test/src/concrete/StoxCorporateActionsFacet.t.sol`
    /// (`testStorageLayoutPin`) must be updated in the same PR to cover
    /// the new field's offset.
    struct CorporateActionStorage {
        /// @param head Head of the list (earliest effectiveTime). After
        /// `_ensureBootstrap` has fired this is always 0 (the bootstrap
        /// node, which has the smallest effectiveTime by construction);
        /// before any schedule call `nodes.length == 0` and head/tail
        /// must not be read.
        uint256 head;
        /// @param tail Tail of the list (latest effectiveTime). Updated
        /// as user actions are scheduled or the trailing user action is
        /// cancelled. Falls back to 0 (bootstrap) when every user action
        /// has been cancelled.
        uint256 tail;
        /// @param nodes Node storage. Index 0 is the init/bootstrap node
        /// once the list has been touched; user-scheduled nodes start at
        /// index 1. `nodes.length == 0` is the only "empty" state.
        CorporateActionNode[] nodes;
        /// @param accountMigrationCursor Per-account migration cursor — the
        /// index of the last node this account was migrated through.
        /// Defaults to 0 (mapping default) which under the new layout means
        /// "at bootstrap"; bootstrap is identity for splits, so a fresh
        /// holder's default cursor of 0 is semantically equivalent to "no
        /// real migration applied yet".
        mapping(address => uint256) accountMigrationCursor;
        /// Per-cursor unmigrated supply. Maps cursor position (node index)
        /// to the sum of stored balances for accounts at that cursor level.
        /// Index 0 is the bootstrap pot — captured by `_ensureBootstrap`
        /// from OZ's `_totalSupply` at the moment the first action is
        /// scheduled. When an account migrates from cursor k to cursor k',
        /// storedBalance is subtracted from unmigrated[k] and the migrated
        /// balance is added to unmigrated[k'].
        mapping(uint256 => uint256) unmigrated;
        /// Index of the latest completed init-or-stock-split node seen by
        /// `fold()`. `_ensureBootstrap` writes `NODE_NONE` here as
        /// the "no fold has run yet" sentinel so the first `fold()` call
        /// walks the head-inclusive range. Mint/burn amounts route to
        /// `unmigrated[totalSupplyLatestCursor]` after the first fold.
        uint256 totalSupplyLatestCursor;
    }

    /// @dev Accessor for corporate action storage at the ERC-7201 slot.
    function getStorage() internal pure returns (CorporateActionStorage storage s) {
        bytes32 position = CORPORATE_ACTION_STORAGE_LOCATION;
        assembly ("memory-safe") {
            s.slot := position
        }
    }

    /// @notice Map an external type identifier to its internal bitmap and
    /// validate parameters. Reverts if the type hash is not recognised.
    /// @param typeHash External identifier, e.g. keccak256("st0x.corporate-actions.stock-split.1").
    /// @param parameters ABI-encoded parameters for the action type.
    /// @return actionType The internal bitmap for this type.
    function resolveActionType(bytes32 typeHash, bytes calldata parameters) internal returns (uint256 actionType) {
        if (typeHash == STOCK_SPLIT_V1_TYPE_HASH) {
            LibStockSplit.validateMultiplierV1(LibStockSplit.decodeParametersV1(parameters));
            return ACTION_TYPE_STOCK_SPLIT_V1;
        }
        revert UnknownActionType(typeHash);
    }

    /// @notice Insert a node into the list maintaining time ordering.
    /// effectiveTime must be strictly in the future.
    /// @return actionIndex The array index of the new node. Index 0 is the
    /// bootstrap node, so user-scheduled actions have index >= 1.
    function schedule(uint256 actionType, uint64 effectiveTime, bytes memory parameters)
        internal
        returns (uint256 actionIndex)
    {
        if (effectiveTime <= block.timestamp) {
            revert EffectiveTimeInPast(effectiveTime, block.timestamp);
        }

        CorporateActionStorage storage s = getStorage();

        _ensureBootstrap(s);

        // Push new node — its array position is the actionIndex.
        s.nodes.push();
        actionIndex = s.nodes.length - 1;

        CorporateActionNode storage node = s.nodes[actionIndex];
        node.actionType = actionType;
        node.effectiveTime = effectiveTime;
        node.parameters = parameters;
        // Pre-fill list pointers with the null sentinel so any code that
        // dereferences a never-spliced node sees "no neighbour" rather than
        // an off-by-one read of node 0.
        node.prev = NODE_NONE;
        node.next = NODE_NONE;

        _insertOrdered(s, actionIndex, effectiveTime);
    }

    /// @dev Lazily create the index-0 init/bootstrap node on first `schedule`
    /// call. Idempotent — every subsequent call is a length check.
    ///
    /// Bootstrap semantics:
    /// - `actionType = ACTION_TYPE_INIT_V1` so balance-migration walks
    ///   (`BALANCE_MIGRATION_TYPES_MASK`) visit it but pure stock-split
    ///   queries (`ACTION_TYPE_STOCK_SPLIT_V1`-only) skip it.
    /// - `effectiveTime = block.timestamp` so the node is "completed" the
    ///   instant it is created — no migration walk ever sees it as pending.
    /// - `parameters` left empty: `LibRebase` / `LibReceiptRebase` /
    ///   `LibTotalSupply.effectiveTotalSupply` branch on `actionType ==
    ///   ACTION_TYPE_INIT_V1` and skip the float multiplier read entirely
    ///   (identity migration).
    /// - `prev = next = NODE_NONE`: the bootstrap is alone in the
    ///   list at creation time, so both neighbours are "no node".
    ///
    /// Pot snapshot:
    /// - `unmigrated[0] = LibERC20Storage.underlyingTotalSupply()` captures
    ///   the pre-action total supply into pot 0. The pot invariant `I(0)`
    ///   holds at this moment because schedule() does not touch balances and
    ///   no `_migrateAccount` has fired yet — so OZ's `_totalSupply == Σ
    ///   _balances` equality is intact, and every account's
    ///   `accountMigrationCursor` is still 0 (= bootstrap).
    ///
    /// Cancel safety: bootstrap's `effectiveTime` is `block.timestamp` at
    /// creation time, so any `cancel(0)` call reverts immediately with
    /// `ActionAlreadyComplete` (the standard guard) — no special-casing
    /// needed in `cancel`.
    function _ensureBootstrap(CorporateActionStorage storage s) private {
        if (s.nodes.length != 0) return;

        // Index 0 — bootstrap node.
        s.nodes.push();
        CorporateActionNode storage bootstrap = s.nodes[0];
        bootstrap.actionType = ACTION_TYPE_INIT_V1;
        bootstrap.effectiveTime = uint64(block.timestamp);
        bootstrap.prev = NODE_NONE;
        bootstrap.next = NODE_NONE;

        // head and tail both point at the bootstrap by virtue of
        // `head == tail == 0` (Solidity zero-init).

        // Snapshot pre-action total supply into pot 0. Every existing holder
        // has accountMigrationCursor == 0, so I(0) holds: pot 0 = Σ
        // underlyingBalance(acc) for accounts at cursor 0.
        s.unmigrated[0] = LibERC20Storage.underlyingTotalSupply();

        // `NODE_NONE` is the "no fold has run yet" sentinel so the
        // first `fold()` call walks the list head-inclusive and lands on
        // the bootstrap (which is already complete).
        s.totalSupplyLatestCursor = NODE_NONE;
    }

    /// @dev Splice a populated node at `newIndex` into the time-ordered
    /// linked list, walking backward from the tail to find the correct
    /// position. Equal-time nodes are inserted **after** existing nodes of
    /// the same effective time (stable ordering — see the tied-effectiveTime
    /// regression tests). The node's `actionType`, `effectiveTime`,
    /// `parameters`, and the `prev = next = NODE_NONE` placeholders
    /// must already be written; this helper only fixes up the list
    /// pointers (`prev`, `next`, `tail`).
    ///
    /// Bootstrap is at index 0 with `effectiveTime = block.timestamp`, and
    /// `schedule` requires `effectiveTime > block.timestamp`, so every user
    /// node lands strictly after the bootstrap. The walk therefore always
    /// finds a `current` whose effectiveTime is `<=` the new node's, and
    /// the "before head" branch is unreachable post-bootstrap.
    ///
    /// @param s Storage pointer (caller already loaded).
    /// @param newIndex The array index of the node being inserted.
    /// @param effectiveTime The node's effective time (cached from storage
    /// so the loop doesn't re-read it on every step).
    function _insertOrdered(CorporateActionStorage storage s, uint256 newIndex, uint64 effectiveTime) private {
        CorporateActionNode storage node = s.nodes[newIndex];

        // Walk backwards from tail to find correct position. `_ensureBootstrap`
        // guarantees the list always contains at least the bootstrap node, so
        // the walk always terminates at the bootstrap (whose effectiveTime is
        // <= every user node's effectiveTime).
        uint256 current = s.tail;
        while (current != NODE_NONE) {
            if (s.nodes[current].effectiveTime <= effectiveTime) {
                uint256 afterCurrent = s.nodes[current].next;
                s.nodes[current].next = newIndex;
                node.prev = current;
                node.next = afterCurrent;
                if (afterCurrent != NODE_NONE) {
                    s.nodes[afterCurrent].prev = newIndex;
                } else {
                    s.tail = newIndex;
                }
                return;
            }
            current = s.nodes[current].prev;
        }
    }

    /// @notice Unlink a scheduled node from the list. Reverts if the action
    /// is already complete or does not exist.
    ///
    /// @dev **Orphaned node data.** This function unlinks the node from the
    /// doubly linked list and zeroes `prev`, `next`, and `effectiveTime`, but
    /// deliberately leaves `actionType` and `parameters` untouched. The node
    /// is no longer reachable via head/tail traversal and every correct
    /// consumer (balanceOf, totalSupply, the `*OfType` getters, `fold`)
    /// walks the list rather than indexing `s.nodes[i]` directly, so ghost
    /// data is invisible. Any future consumer that needs to look up a node
    /// by its array index MUST check `node.effectiveTime != 0` before
    /// trusting any field on the node; an `effectiveTime == 0` node is
    /// either never-used (array slot was never populated) or cancelled
    /// (unlinked here).
    ///
    /// @dev `node.effectiveTime = 0` below is the double-cancel guard. A
    /// second call to `cancel(actionIndex)` on an already-cancelled node
    /// is caught by the `node.effectiveTime == 0` check at the top of
    /// this function. Without the zero-assignment, a double-cancel would:
    /// (1) pass the effectiveTime-in-past check because the original
    /// future time is still set; (2) read `prevId = node.prev = 0` and
    /// `nextId = node.next = 0` (both zeroed by the first cancel); (3)
    /// blow away `s.head` and `s.tail` by writing `nextId = 0` into both.
    /// Catastrophic, silent state corruption.
    /// `testCancelAlreadyCancelledReverts` pins the guard — do not remove
    /// the test or the zero assignment together.
    function cancel(uint256 actionIndex) internal {
        CorporateActionStorage storage s = getStorage();
        if (actionIndex >= s.nodes.length) revert ActionDoesNotExist(actionIndex);

        CorporateActionNode storage node = s.nodes[actionIndex];

        if (node.effectiveTime == 0) revert ActionDoesNotExist(actionIndex);
        // Bootstrap (idx 0) has effectiveTime == block.timestamp at creation,
        // so this guard rejects `cancel(0)` without a special case.
        if (node.effectiveTime <= block.timestamp) revert ActionAlreadyComplete(actionIndex);

        uint256 prevId = node.prev;
        uint256 nextId = node.next;

        if (prevId != NODE_NONE) {
            s.nodes[prevId].next = nextId;
        } else {
            s.head = nextId;
        }

        if (nextId != NODE_NONE) {
            s.nodes[nextId].prev = prevId;
        } else {
            s.tail = prevId;
        }

        // Unlink only — do NOT delete actionType/parameters from storage.
        // The `effectiveTime = 0` assignment below is the double-cancel
        // guard — see the @dev block above before touching it.
        node.prev = NODE_NONE;
        node.next = NODE_NONE;
        node.effectiveTime = 0;
    }

    /// @notice Count completed user-scheduled actions by walking from the
    /// head. The init/bootstrap node is excluded — `completedActionCount`
    /// reports actions a scheduler created via `scheduleCorporateAction`,
    /// not internal infrastructure.
    function countCompleted() internal view returns (uint256 count) {
        if (getStorage().nodes.length == 0) return 0;
        uint256 mask = VALID_ACTION_TYPES_MASK & ~ACTION_TYPE_INIT_V1;
        uint256 current = LibCorporateActionNode.nextOfType(NODE_NONE, mask, CompletionFilter.COMPLETED);
        while (current != NODE_NONE) {
            count++;
            current = LibCorporateActionNode.nextOfType(current, mask, CompletionFilter.COMPLETED);
        }
    }
}

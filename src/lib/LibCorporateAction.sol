// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {CorporateActionNode, CompletionFilter, LibCorporateActionNode} from "./LibCorporateActionNode.sol";
import {LibStockSplit} from "./LibStockSplit.sol";
import {
    EffectiveTimeInPast,
    ActionAlreadyComplete,
    ActionDoesNotExist,
    UnknownActionType,
    NoActionsScheduled
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

/// @dev Bitmap action type for V1 stock splits (forward and reverse).
uint256 constant ACTION_TYPE_STOCK_SPLIT_V1 = 1 << 0;

/// @dev Bitmap action type for V1 stablecoin dividends.
uint256 constant ACTION_TYPE_STABLES_DIVIDEND_V1 = 1 << 1;

/// @dev Union of all defined action types. Extend when a new
/// `ACTION_TYPE_*` constant is added.
uint256 constant VALID_ACTION_TYPES_MASK = ACTION_TYPE_STOCK_SPLIT_V1 | ACTION_TYPE_STABLES_DIVIDEND_V1;

/// @title LibCorporateAction
/// @notice Library for corporate action diamond storage. Uses ERC-7201
/// namespaced storage to avoid collisions with existing vault storage slots.
/// Manages a doubly linked list of corporate actions ordered by effectiveTime.
/// There is no stored status or counters — an action is complete when its
/// effectiveTime is less than or equal to the current block timestamp.
///
/// Nodes are stored in a dynamic array. Index 0 is a sentinel (never used for
/// real data). Real nodes start at index 1. Head/tail/prev/next are 1-based
/// indices where 0 means "none".
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
        /// @param head Head of the list (1-based index, earliest effectiveTime). 0 = empty.
        uint256 head;
        /// @param tail Tail of the list (1-based index, latest effectiveTime). 0 = empty.
        uint256 tail;
        /// @param nodes Node storage. Index 0 is a sentinel. Real nodes start at index 1.
        CorporateActionNode[] nodes;
        /// @param accountMigrationCursor Per-account migration cursor — the 1-based index of the last
        /// node this account was migrated through.
        mapping(address => uint256) accountMigrationCursor;
        /// Per-cursor unmigrated supply. Maps cursor position (node index) to
        /// the sum of stored balances for accounts at that cursor level.
        /// Index 0 is the bootstrap pot (pre-any-split balances).
        /// When an account migrates from cursor k to cursor k', storedBalance
        /// is subtracted from unmigrated[k] and the migrated balance is added
        /// to unmigrated[k'].
        mapping(uint256 => uint256) unmigrated;
        /// 1-based index of the latest completed split node seen by fold().
        /// Mint/burn amounts are added to unmigrated[totalSupplyLatestSplit].
        /// 0 = no completed splits seen yet.
        uint256 totalSupplyLatestSplit;
        /// Whether totalSupply tracking has been bootstrapped from OZ's
        /// _totalSupply. Set once when the first completed split is detected.
        bool totalSupplyBootstrapped;
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
    /// @return actionIndex The 1-based array index of the new node.
    function schedule(uint256 actionType, uint64 effectiveTime, bytes memory parameters)
        internal
        returns (uint256 actionIndex)
    {
        if (effectiveTime <= block.timestamp) {
            revert EffectiveTimeInPast(effectiveTime, block.timestamp);
        }

        CorporateActionStorage storage s = getStorage();

        // Push sentinel at index 0 on first use.
        if (s.nodes.length == 0) {
            s.nodes.push();
        }

        // Push new node — its array position is the actionIndex.
        s.nodes.push();
        actionIndex = s.nodes.length - 1;

        CorporateActionNode storage node = s.nodes[actionIndex];
        node.actionType = actionType;
        node.effectiveTime = effectiveTime;
        node.parameters = parameters;

        _insertOrdered(s, actionIndex, effectiveTime);
    }

    /// @dev Splice a populated node at `newIndex` into the time-ordered
    /// linked list, walking backward from the tail to find the correct
    /// position. Equal-time nodes are inserted **after** existing nodes of
    /// the same effective time (stable ordering — see the tied-effectiveTime
    /// regression tests). The node's `actionType`, `effectiveTime`, and
    /// `parameters` must already be written; this helper only updates the
    /// list pointers (`prev`, `next`, `head`, `tail`).
    ///
    /// Extracted from `schedule` so the insertion walk is isolated from
    /// sentinel allocation and node population. This helper assumes the
    /// storage struct has been
    /// initialised (sentinel already pushed) and the node at `newIndex` is
    /// fully populated.
    ///
    /// @param s Storage pointer (caller already loaded).
    /// @param newIndex The 1-based array index of the node being inserted.
    /// @param effectiveTime The node's effective time (cached from storage
    /// so the loop doesn't re-read it on every step).
    function _insertOrdered(CorporateActionStorage storage s, uint256 newIndex, uint64 effectiveTime) private {
        CorporateActionNode storage node = s.nodes[newIndex];

        if (s.tail == 0) {
            s.head = newIndex;
            s.tail = newIndex;
            return;
        }

        // Walk backwards from tail to find correct position.
        uint256 current = s.tail;
        while (current != 0) {
            if (s.nodes[current].effectiveTime <= effectiveTime) {
                uint256 afterCurrent = s.nodes[current].next;
                s.nodes[current].next = newIndex;
                node.prev = current;
                node.next = afterCurrent;
                if (afterCurrent != 0) {
                    s.nodes[afterCurrent].prev = newIndex;
                } else {
                    s.tail = newIndex;
                }
                return;
            }
            current = s.nodes[current].prev;
        }
        // Goes before the current head.
        node.next = s.head;
        s.nodes[s.head].prev = newIndex;
        s.head = newIndex;
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
        if (actionIndex == 0 || actionIndex >= s.nodes.length) revert ActionDoesNotExist(actionIndex);

        CorporateActionNode storage node = s.nodes[actionIndex];

        if (node.effectiveTime == 0) revert ActionDoesNotExist(actionIndex);
        if (node.effectiveTime <= block.timestamp) revert ActionAlreadyComplete(actionIndex);

        uint256 prevId = node.prev;
        uint256 nextId = node.next;

        if (prevId != 0) {
            s.nodes[prevId].next = nextId;
        } else {
            s.head = nextId;
        }

        if (nextId != 0) {
            s.nodes[nextId].prev = prevId;
        } else {
            s.tail = prevId;
        }

        // Unlink only — do NOT delete actionType/parameters from storage.
        // The `effectiveTime = 0` assignment below is the double-cancel
        // guard — see the @dev block above before touching it.
        node.prev = 0;
        node.next = 0;
        node.effectiveTime = 0;
    }

    /// @notice Count completed actions by walking from the head.
    function countCompleted() internal view returns (uint256 count) {
        if (getStorage().nodes.length == 0) return 0;
        uint256 current = LibCorporateActionNode.nextOfType(0, type(uint256).max, CompletionFilter.COMPLETED);
        while (current != 0) {
            count++;
            current = LibCorporateActionNode.nextOfType(current, type(uint256).max, CompletionFilter.COMPLETED);
        }
    }

    /// @notice Return the head node of the list.
    /// @dev Requires that at least one node has been scheduled (sentinel exists).
    /// @return The head node, or the sentinel (index == 0) if the list is empty.
    function headNode() internal view returns (CorporateActionNode storage) {
        CorporateActionStorage storage s = getStorage();
        if (s.nodes.length == 0) revert NoActionsScheduled();
        if (s.head == 0) return s.nodes[0];
        return s.nodes[s.head];
    }

    /// @notice Return the tail node of the list.
    /// @dev Requires that at least one node has been scheduled (sentinel exists).
    /// @return The tail node, or the sentinel (index == 0) if the list is empty.
    function tailNode() internal view returns (CorporateActionNode storage) {
        CorporateActionStorage storage s = getStorage();
        if (s.nodes.length == 0) revert NoActionsScheduled();
        if (s.tail == 0) return s.nodes[0];
        return s.nodes[s.tail];
    }
}

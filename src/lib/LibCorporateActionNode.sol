// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibCorporateAction} from "./LibCorporateAction.sol";

/// @dev A corporate action node in the doubly linked list ordered by
/// effectiveTime. There is no stored status — an action is "complete" when
/// effectiveTime <= block.timestamp.
///
/// Nodes are stored in a dynamic array. Index 0 is a sentinel (reserved but
/// unused for real data) so that 0 can represent "no node" in pointer fields.
/// Real nodes start at index 1. The node does not store its own index —
/// callers track indices externally.
struct CorporateActionNode {
    /// @param actionType Bitmap action type. Each type is a single bit (1 << n).
    uint256 actionType;
    /// @param effectiveTime When this action takes effect.
    uint64 effectiveTime;
    /// @param prev Previous node in time-ordered list (1-based index, 0 = none).
    uint256 prev;
    /// @param next Next node in time-ordered list (1-based index, 0 = none).
    uint256 next;
    /// @param parameters ABI-encoded parameters specific to the action type.
    bytes parameters;
}

/// @dev Filter for traversal based on completion status. The list is
/// time-ordered ascending: completed nodes (effectiveTime <= now) are
/// contiguous at the front (head side), pending nodes contiguous at the
/// back (tail side).
///
/// - ALL: return any matching node regardless of completion. No early break.
/// - COMPLETED: return only nodes with `effectiveTime <= block.timestamp`.
///   Forward walks stop early at the first pending node (optimization). A
///   backward walk returns the first completed match it finds while walking
///   back from the tail through the pending section; no early break is
///   beneficial on the backward direction.
/// - PENDING: return only nodes with `effectiveTime > block.timestamp`.
///   A forward walk skips completed nodes at the front before returning the
///   first pending match (no early break). A backward walk stops early at
///   the first completed node it encounters (optimization).
enum CompletionFilter {
    ALL,
    COMPLETED,
    PENDING
}

/// @title LibCorporateActionNode
/// @notice Index-based traversal logic for the corporate action linked list.
/// Functions accept and return node indices rather than storage references,
/// so callers always know the position of the node they are working with.
library LibCorporateActionNode {
    /// @notice Walk forward from `fromIndex`, returning the index of the next
    /// node matching the type mask and completion filter.
    ///
    /// @param fromIndex Start after this node (exclusive). Pass 0 to start
    /// from the head of the list.
    /// @param mask Bitmap mask to filter action types. Use type(uint256).max
    /// to match all types.
    /// @param filter Completion filter: ALL, COMPLETED, or PENDING.
    /// @return The index of the next matching node, or 0 if none found.
    function nextOfType(uint256 fromIndex, uint256 mask, CompletionFilter filter) internal view returns (uint256) {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        uint256 current = fromIndex == 0 ? s.head : s.nodes[fromIndex].next;

        while (current != 0) {
            CorporateActionNode storage node = s.nodes[current];
            bool isCompleted = node.effectiveTime <= block.timestamp;

            if (filter == CompletionFilter.COMPLETED && !isCompleted) break;

            if (
                (filter == CompletionFilter.ALL
                        || (filter == CompletionFilter.COMPLETED && isCompleted)
                        || (filter == CompletionFilter.PENDING && !isCompleted)) && (node.actionType & mask != 0)
            ) {
                return current;
            }

            current = node.next;
        }

        return 0;
    }

    /// @notice Walk backward from `fromIndex`, returning the index of the
    /// previous node matching the type mask and completion filter.
    ///
    /// @param fromIndex Start before this node (exclusive). Pass 0 to start
    /// from the tail of the list.
    /// @param mask Bitmap mask to filter action types.
    /// @param filter Completion filter: ALL, COMPLETED, or PENDING.
    /// @return The index of the previous matching node, or 0 if none found.
    function prevOfType(uint256 fromIndex, uint256 mask, CompletionFilter filter) internal view returns (uint256) {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        uint256 current = fromIndex == 0 ? s.tail : s.nodes[fromIndex].prev;

        while (current != 0) {
            CorporateActionNode storage node = s.nodes[current];
            bool isCompleted = node.effectiveTime <= block.timestamp;

            if (filter == CompletionFilter.PENDING && isCompleted) break;

            if (
                (filter == CompletionFilter.ALL
                        || (filter == CompletionFilter.COMPLETED && isCompleted)
                        || (filter == CompletionFilter.PENDING && !isCompleted)) && (node.actionType & mask != 0)
            ) {
                return current;
            }

            current = node.prev;
        }

        return 0;
    }
}

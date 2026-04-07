// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibCorporateAction} from "./LibCorporateAction.sol";

/// @dev A corporate action node in the doubly linked list ordered by
/// effectiveTime. There is no stored status — an action is "complete" when
/// effectiveTime <= block.timestamp.
///
/// Nodes are stored in a dynamic array. Index 0 is a sentinel (never used
/// for real data). Real nodes start at index 1. The node does not store its
/// own index — callers track indices externally.
struct CorporateActionNode {
    /// Bitmap action type. Each type is a single bit (1 << n).
    uint256 actionType;
    /// When this action takes effect.
    uint64 effectiveTime;
    /// Previous node in time-ordered list (1-based index, 0 = none).
    uint256 prev;
    /// Next node in time-ordered list (1-based index, 0 = none).
    uint256 next;
    /// ABI-encoded parameters specific to the action type.
    bytes parameters;
}

/// @title LibCorporateActionNode
/// @notice Index-based traversal logic for the corporate action linked list.
/// Functions accept and return node indices rather than storage references,
/// so callers always know the position of the node they are working with.
library LibCorporateActionNode {
    /// @notice Walk forward from `fromIndex`, returning the index of the next
    /// node that matches the type mask and completion filter.
    ///
    /// The list is ordered by effectiveTime (earliest first). Completed nodes
    /// (effectiveTime <= block.timestamp) are at the front. When `completed`
    /// is true, the walk stops at the first non-completed node (since no
    /// further completed nodes can follow). When `completed` is false,
    /// completed nodes are skipped and only pending nodes are returned.
    ///
    /// @param fromIndex The node to start after (exclusive). Pass 0 (sentinel)
    /// to start from the head of the list.
    /// @param mask Bitmap mask to filter action types. Use type(uint256).max
    /// to match all types.
    /// @param completed If true, return only completed nodes. If false, return
    /// only pending (not yet completed) nodes.
    /// @return The index of the next matching node, or 0 if none found.
    function nextOfType(uint256 fromIndex, uint256 mask, bool completed) internal view returns (uint256) {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        uint256 current = fromIndex == 0 ? s.head : s.nodes[fromIndex].next;

        while (current != 0) {
            CorporateActionNode storage node = s.nodes[current];
            bool isCompleted = node.effectiveTime <= block.timestamp;

            // Completed nodes are contiguous at the front. If we want
            // completed nodes and hit a pending one, no more can follow.
            if (completed && !isCompleted) break;

            if (isCompleted == completed && (node.actionType & mask != 0)) {
                return current;
            }

            current = node.next;
        }

        return 0;
    }
}

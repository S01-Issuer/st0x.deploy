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
///
/// Three traversal functions serve different use cases:
///
/// - `nextCompletedOfType` — forward walk, completed nodes only. Used
///   internally by the rebase and totalSupply systems which only care about
///   actions that have already taken effect.
///
/// - `nextOfType` / `prevOfType` — forward/backward walk, all nodes
///   regardless of completion status. Used by external consumers that need
///   to scan for actions within a time window (e.g. oracle pause checks).
library LibCorporateActionNode {
    /// @notice Walk forward through completed nodes only.
    ///
    /// The list is ordered by effectiveTime (earliest first). Completed nodes
    /// are contiguous at the front, so the walk stops as soon as a pending
    /// node is reached.
    ///
    /// @param fromIndex Start after this node (exclusive). Pass 0 to start
    /// from the head.
    /// @param mask Bitmap mask to filter action types.
    /// @return The index of the next matching completed node, or 0 if none.
    function nextCompletedOfType(uint256 fromIndex, uint256 mask) internal view returns (uint256) {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        uint256 current = fromIndex == 0 ? s.head : s.nodes[fromIndex].next;

        while (current != 0) {
            CorporateActionNode storage node = s.nodes[current];
            if (node.effectiveTime > block.timestamp) break;
            if (node.actionType & mask != 0) return current;
            current = node.next;
        }

        return 0;
    }

    /// @notice Walk forward through all nodes matching a type mask.
    /// @param fromIndex Start after this node (exclusive). Pass 0 to start
    /// from the head.
    /// @param mask Bitmap mask to filter action types.
    /// @return The index of the next matching node, or 0 if none.
    function nextOfType(uint256 fromIndex, uint256 mask) internal view returns (uint256) {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        uint256 current = fromIndex == 0 ? s.head : s.nodes[fromIndex].next;

        while (current != 0) {
            CorporateActionNode storage node = s.nodes[current];
            if (node.actionType & mask != 0) return current;
            current = node.next;
        }

        return 0;
    }

    /// @notice Walk backward through all nodes matching a type mask.
    /// @param fromIndex Start before this node (exclusive). Pass 0 to start
    /// from the tail.
    /// @param mask Bitmap mask to filter action types.
    /// @return The index of the previous matching node, or 0 if none.
    function prevOfType(uint256 fromIndex, uint256 mask) internal view returns (uint256) {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        uint256 current = fromIndex == 0 ? s.tail : s.nodes[fromIndex].prev;

        while (current != 0) {
            CorporateActionNode storage node = s.nodes[current];
            if (node.actionType & mask != 0) return current;
            current = node.prev;
        }

        return 0;
    }
}

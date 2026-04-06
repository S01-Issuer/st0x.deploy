// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibCorporateAction} from "./LibCorporateAction.sol";

/// @dev A corporate action node in the doubly linked list ordered by
/// effectiveTime. There is no stored status — an action is "complete" when
/// effectiveTime <= block.timestamp. Its positional index from the head
/// among completed nodes is its monotonic ID. This is stable because new
/// actions cannot be inserted in the past.
struct CorporateActionNode {
    /// Own position in the nodes array (immutable after creation).
    uint256 index;
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
/// @notice Traversal logic for corporate action nodes.
library LibCorporateActionNode {
    /// @notice Walk forward from `self`, returning the next completed node
    /// whose actionType matches the given mask. Starts from `self.next`.
    /// @param self The node to start walking from (exclusive).
    /// @param mask Bitmap mask to filter action types. Use type(uint256).max
    /// to match all types.
    /// @return The next matching completed node, or the sentinel (index == 0)
    /// if none found.
    function nextCompletedOfType(CorporateActionNode storage self, uint256 mask)
        internal
        view
        returns (CorporateActionNode storage)
    {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        uint256 current = self.index == 0 ? s.head : self.next;

        while (current != 0) {
            CorporateActionNode storage node = s.nodes[current];
            if (node.effectiveTime > block.timestamp) break;
            if (node.actionType & mask != 0) return node;
            current = node.next;
        }

        return s.nodes[0];
    }
}

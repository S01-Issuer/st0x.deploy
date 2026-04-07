// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {CorporateActionNode, LibCorporateActionNode} from "./LibCorporateActionNode.sol";

/// @dev ERC-7201 namespaced storage location for corporate actions.
/// keccak256(abi.encode(uint256(keccak256("rain.storage.corporate-action.1")) - 1)) & ~bytes32(uint256(0xff))
bytes32 constant CORPORATE_ACTION_STORAGE_LOCATION = 0xcce8b403dc927e3ec0218603a262b6c4fcc2985ab628bee1e65a6e26753c8300;

/// @dev Permission hash for scheduling a corporate action via the authorizer.
bytes32 constant SCHEDULE_CORPORATE_ACTION = keccak256("SCHEDULE_CORPORATE_ACTION");

/// @dev Permission hash for cancelling a corporate action via the authorizer.
bytes32 constant CANCEL_CORPORATE_ACTION = keccak256("CANCEL_CORPORATE_ACTION");

/// Thrown when scheduling an action with an effective time in the past.
error EffectiveTimeInPast(uint64 effectiveTime, uint256 currentTime);

/// Thrown when trying to cancel an action whose effectiveTime has passed.
error ActionAlreadyComplete(uint256 actionIndex);

/// Thrown when referencing an action that does not exist.
error ActionDoesNotExist(uint256 actionIndex);

/// Thrown when the external type hash has no known bitmap mapping.
/// @param typeHash The unrecognised external identifier.
error UnknownActionType(bytes32 typeHash);

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
    struct CorporateActionStorage {
        /// Head of the list (1-based index, earliest effectiveTime). 0 = empty.
        uint256 head;
        /// Tail of the list (1-based index, latest effectiveTime). 0 = empty.
        uint256 tail;
        /// Node storage. Index 0 is a sentinel. Real nodes start at index 1.
        CorporateActionNode[] nodes;
        /// Per-account migration cursor — the 1-based index of the last
        /// node this account was migrated through.
        mapping(address => uint256) accountMigrationCursor;
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
    /// Subsequent PRs add concrete type mappings.
    /// @param typeHash External identifier, e.g. keccak256("StockSplit").
    /// @param parameters ABI-encoded parameters for the action type.
    /// @return actionType The internal bitmap for this type.
    function resolveActionType(bytes32 typeHash, bytes memory parameters) internal pure returns (uint256 actionType) {
        // Concrete types are added by subsequent PRs.
        (actionType, parameters);
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

        if (s.tail == 0) {
            s.head = actionIndex;
            s.tail = actionIndex;
        } else {
            // Walk backwards from tail to find correct position.
            uint256 current = s.tail;
            while (current != 0) {
                if (s.nodes[current].effectiveTime <= effectiveTime) {
                    uint256 afterCurrent = s.nodes[current].next;
                    s.nodes[current].next = actionIndex;
                    node.prev = current;
                    node.next = afterCurrent;
                    if (afterCurrent != 0) {
                        s.nodes[afterCurrent].prev = actionIndex;
                    } else {
                        s.tail = actionIndex;
                    }
                    return actionIndex;
                }
                current = s.nodes[current].prev;
            }
            // Goes before the current head.
            node.next = s.head;
            s.nodes[s.head].prev = actionIndex;
            s.head = actionIndex;
        }
    }

    /// @notice Unlink a scheduled node from the list. Reverts if the action
    /// is already complete or does not exist. The node data remains in the
    /// array but is no longer reachable via the linked list.
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

        // Unlink only — do NOT delete node data from storage.
        node.prev = 0;
        node.next = 0;
        node.effectiveTime = 0;
    }

    /// @notice Count completed actions by walking from the head.
    function countCompleted() internal view returns (uint256 count) {
        if (getStorage().nodes.length == 0) return 0;
        uint256 current = LibCorporateActionNode.nextCompletedOfType(0, type(uint256).max);
        while (current != 0) {
            count++;
            current = LibCorporateActionNode.nextCompletedOfType(current, type(uint256).max);
        }
    }

    /// @notice Return the head node of the list.
    /// @dev Requires that at least one node has been scheduled (sentinel exists).
    /// @return The head node, or the sentinel (index == 0) if the list is empty.
    function headNode() internal view returns (CorporateActionNode storage) {
        CorporateActionStorage storage s = getStorage();
        if (s.head == 0) return s.nodes[0];
        return s.nodes[s.head];
    }

    /// @notice Return the tail node of the list.
    /// @dev Requires that at least one node has been scheduled (sentinel exists).
    /// @return The tail node, or the sentinel (index == 0) if the list is empty.
    function tailNode() internal view returns (CorporateActionNode storage) {
        CorporateActionStorage storage s = getStorage();
        if (s.tail == 0) return s.nodes[0];
        return s.nodes[s.tail];
    }

    function head() internal view returns (uint256) {
        return getStorage().head;
    }

    function tail() internal view returns (uint256) {
        return getStorage().tail;
    }
}

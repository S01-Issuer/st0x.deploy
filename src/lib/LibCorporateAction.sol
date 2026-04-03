// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @dev ERC-7201 namespaced storage location for corporate actions.
/// keccak256(abi.encode(uint256(keccak256("rain.storage.corporate-action.1")) - 1)) & ~bytes32(uint256(0xff))
bytes32 constant CORPORATE_ACTION_STORAGE_LOCATION = 0xcce8b403dc927e3ec0218603a262b6c4fcc2985ab628bee1e65a6e26753c8300;

/// @dev Permission hash for scheduling a corporate action via the authorizer.
bytes32 constant SCHEDULE_CORPORATE_ACTION = keccak256("SCHEDULE_CORPORATE_ACTION");

/// @dev Permission hash for cancelling a corporate action via the authorizer.
bytes32 constant CANCEL_CORPORATE_ACTION = keccak256("CANCEL_CORPORATE_ACTION");

/// @dev Action is scheduled and waiting for its effective time to pass.
uint8 constant STATUS_SCHEDULED = 1;

/// @dev Action has completed — effective time passed and monotonic ID assigned.
uint8 constant STATUS_COMPLETE = 2;

/// Thrown when scheduling an action with effectiveTime <= block.timestamp.
/// @param effectiveTime The effective time that was not in the future.
/// @param currentTime The current block timestamp.
error EffectiveTimeInPast(uint256 effectiveTime, uint256 currentTime);

/// Thrown when trying to cancel an action that is not SCHEDULED.
/// @param nodeId The node that could not be cancelled.
/// @param status The current status of the node.
error NotScheduled(uint256 nodeId, uint8 status);

/// Thrown when querying a node ID that does not exist.
/// @param nodeId The invalid node ID.
error NodeDoesNotExist(uint256 nodeId);

/// @dev A node in the doubly linked list of corporate actions.
struct CorporateActionNode {
    /// Bitmap of action types (e.g. 1 << 0 for stock split).
    uint256 actionType;
    /// When this action takes effect.
    uint64 effectiveTime;
    /// Current lifecycle status (SCHEDULED or COMPLETE).
    uint8 status;
    /// Monotonic ID assigned when the action completes. Zero while scheduled.
    uint256 monotonicId;
    /// Previous node in time-ordered list. Zero means this is the head.
    uint256 prev;
    /// Next node in time-ordered list. Zero means this is the tail.
    uint256 next;
    /// ABI-encoded parameters specific to the action type.
    bytes parameters;
}

/// @title LibCorporateAction
/// @notice Library for corporate action diamond storage. Uses ERC-7201
/// namespaced storage to avoid collisions with existing vault storage slots.
///
/// Manages a doubly linked list of corporate actions ordered by effectiveTime.
/// Actions auto-complete when their effectiveTime passes and any interaction
/// triggers a check. Completed actions receive monotonic IDs.
library LibCorporateAction {
    /// @custom:storage-location erc7201:rain.storage.corporate-action.1
    struct CorporateActionStorage {
        /// The global corporate action ID (CAID). Incremented each time a
        /// corporate action completes, regardless of type.
        uint256 globalCAID;
        /// Counter for generating node IDs. Starts at 1.
        uint256 nextNodeId;
        /// Head of the doubly linked list (earliest effectiveTime).
        uint256 head;
        /// Tail of the doubly linked list (latest effectiveTime).
        uint256 tail;
        /// Node storage by ID.
        mapping(uint256 => CorporateActionNode) nodes;
    }

    /// @dev Accessor for corporate action storage at the ERC-7201 slot.
    function getStorage() internal pure returns (CorporateActionStorage storage s) {
        bytes32 position = CORPORATE_ACTION_STORAGE_LOCATION;
        assembly ("memory-safe") {
            s.slot := position
        }
    }

    /// @notice Process any scheduled actions whose effectiveTime has passed,
    /// transitioning them to COMPLETE and assigning monotonic IDs.
    /// Walks from the head forward since completed actions cluster at the front.
    function processCompletions() internal {
        CorporateActionStorage storage s = getStorage();
        uint256 current = s.head;
        while (current != 0) {
            CorporateActionNode storage node = s.nodes[current];
            if (node.status != STATUS_SCHEDULED) {
                current = node.next;
                continue;
            }
            // Once we hit a scheduled node in the future, all subsequent
            // nodes are also in the future (list is time-ordered).
            if (node.effectiveTime > block.timestamp) {
                break;
            }
            s.globalCAID++;
            node.monotonicId = s.globalCAID;
            node.status = STATUS_COMPLETE;
            current = node.next;
        }
    }

    /// @notice Schedule a new corporate action. Inserts a node into the doubly
    /// linked list maintaining time ordering. Processes any pending completions
    /// first.
    /// @param actionType Bitmap of action types.
    /// @param effectiveTime When the action takes effect. Must be > block.timestamp.
    /// @param parameters ABI-encoded parameters for the action type.
    /// @return nodeId The list node ID assigned to this action.
    function schedule(uint256 actionType, uint64 effectiveTime, bytes memory parameters)
        internal
        returns (uint256 nodeId)
    {
        if (effectiveTime <= block.timestamp) {
            revert EffectiveTimeInPast(effectiveTime, block.timestamp);
        }

        processCompletions();

        CorporateActionStorage storage s = getStorage();
        s.nextNodeId++;
        nodeId = s.nextNodeId;

        CorporateActionNode storage newNode = s.nodes[nodeId];
        newNode.actionType = actionType;
        newNode.effectiveTime = effectiveTime;
        newNode.status = STATUS_SCHEDULED;
        newNode.parameters = parameters;

        // Empty list.
        if (s.head == 0) {
            s.head = nodeId;
            s.tail = nodeId;
            return nodeId;
        }

        // Insert at tail (most common case — scheduling in chronological order).
        CorporateActionNode storage tailNode = s.nodes[s.tail];
        if (effectiveTime >= tailNode.effectiveTime) {
            newNode.prev = s.tail;
            tailNode.next = nodeId;
            s.tail = nodeId;
            return nodeId;
        }

        // Insert at head.
        CorporateActionNode storage headNode = s.nodes[s.head];
        if (effectiveTime < headNode.effectiveTime) {
            newNode.next = s.head;
            headNode.prev = nodeId;
            s.head = nodeId;
            return nodeId;
        }

        // Insert in the middle — walk from tail backwards to find position.
        uint256 cursor = s.tail;
        while (cursor != 0) {
            CorporateActionNode storage cursorNode = s.nodes[cursor];
            if (effectiveTime >= cursorNode.effectiveTime) {
                // Insert after cursor.
                uint256 afterCursor = cursorNode.next;
                newNode.prev = cursor;
                newNode.next = afterCursor;
                cursorNode.next = nodeId;
                if (afterCursor != 0) {
                    s.nodes[afterCursor].prev = nodeId;
                }
                break;
            }
            cursor = cursorNode.prev;
        }
    }

    /// @notice Cancel a scheduled action by removing its node from the list.
    /// Only SCHEDULED nodes can be cancelled. Processes completions first so
    /// that any actions that have already passed their effectiveTime cannot be
    /// cancelled.
    /// @param nodeId The node to cancel.
    function cancel(uint256 nodeId) internal {
        processCompletions();

        CorporateActionStorage storage s = getStorage();
        CorporateActionNode storage node = s.nodes[nodeId];

        if (node.status != STATUS_SCHEDULED) {
            revert NotScheduled(nodeId, node.status);
        }

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

        // Clear the node to free storage. Keep actionType and effectiveTime
        // so the CorporateActionCancelled event can reference them if needed
        // by off-chain indexers, but zero out the list pointers and status.
        node.prev = 0;
        node.next = 0;
        node.status = 0;
    }

    /// @notice Read a node by ID. Reverts if the node was never created.
    /// @param nodeId The node to read.
    /// @return node The node storage reference.
    function getNode(uint256 nodeId) internal view returns (CorporateActionNode storage node) {
        CorporateActionStorage storage s = getStorage();
        if (nodeId == 0 || nodeId > s.nextNodeId) {
            revert NodeDoesNotExist(nodeId);
        }
        node = s.nodes[nodeId];
    }
}

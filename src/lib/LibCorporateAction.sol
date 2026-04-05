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

/// Thrown when scheduling an action with an effective time in the past.
error EffectiveTimeInPast(uint64 effectiveTime, uint256 currentTime);

/// Thrown when trying to cancel an action whose effectiveTime has passed.
error ActionAlreadyComplete(uint256 actionId);

/// Thrown when referencing an action that does not exist.
error ActionDoesNotExist(uint256 actionId);

/// Thrown when the external type hash has no known bitmap mapping.
/// @param typeHash The unrecognised external identifier.
error UnknownActionType(bytes32 typeHash);

/// @dev A corporate action node in the doubly linked list ordered by
/// effectiveTime. There is no stored status — an action is "complete" when
/// effectiveTime <= block.timestamp. Its positional index from the head
/// among completed nodes is its monotonic ID. This is stable because new
/// actions cannot be inserted in the past.
struct CorporateActionNode {
    /// Bitmap action type. Each type is a single bit (1 << n).
    uint256 actionType;
    /// When this action takes effect.
    uint64 effectiveTime;
    /// Previous node in time-ordered list. Zero = head.
    uint256 prev;
    /// Next node in time-ordered list. Zero = tail.
    uint256 next;
    /// ABI-encoded parameters specific to the action type.
    bytes parameters;
}

/// @title LibCorporateAction
/// @notice Library for corporate action diamond storage. Uses ERC-7201
/// namespaced storage to avoid collisions with existing vault storage slots.
/// Manages a doubly linked list of corporate actions ordered by effectiveTime.
/// There is no stored status or counters — an action is complete when its
/// effectiveTime is less than or equal to the current block timestamp.
library LibCorporateAction {
    /// @custom:storage-location erc7201:rain.storage.corporate-action.1
    struct CorporateActionStorage {
        /// Counter for internal node IDs (linked list keys). Starts at 1.
        uint256 nextActionId;
        /// Head of the list (earliest effectiveTime).
        uint256 head;
        /// Tail of the list (latest effectiveTime).
        uint256 tail;
        /// Node storage by internal node ID.
        mapping(uint256 => CorporateActionNode) nodes;
        /// Per-account migration cursor — the internal node ID of the last
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
    function resolveActionType(bytes32 typeHash, bytes memory parameters)
        internal
        pure
        returns (uint256 actionType)
    {
        // Concrete types are added by subsequent PRs.
        (actionType, parameters);
        revert UnknownActionType(typeHash);
    }

    /// @notice Insert a node into the list maintaining time ordering.
    /// effectiveTime must be strictly in the future.
    function schedule(uint256 actionType, uint64 effectiveTime, bytes memory parameters)
        internal
        returns (uint256 actionId)
    {
        if (effectiveTime <= block.timestamp) {
            revert EffectiveTimeInPast(effectiveTime, block.timestamp);
        }

        CorporateActionStorage storage s = getStorage();
        s.nextActionId++;
        actionId = s.nextActionId;

        CorporateActionNode storage node = s.nodes[actionId];
        node.actionType = actionType;
        node.effectiveTime = effectiveTime;
        node.parameters = parameters;

        if (s.tail == 0) {
            s.head = actionId;
            s.tail = actionId;
        } else {
            // Walk backwards from tail to find correct position.
            uint256 current = s.tail;
            while (current != 0) {
                if (s.nodes[current].effectiveTime <= effectiveTime) {
                    uint256 afterCurrent = s.nodes[current].next;
                    s.nodes[current].next = actionId;
                    node.prev = current;
                    node.next = afterCurrent;
                    if (afterCurrent != 0) {
                        s.nodes[afterCurrent].prev = actionId;
                    } else {
                        s.tail = actionId;
                    }
                    return actionId;
                }
                current = s.nodes[current].prev;
            }
            // Goes before the current head.
            node.next = s.head;
            s.nodes[s.head].prev = actionId;
            s.head = actionId;
        }
    }

    /// @notice Remove a scheduled node from the list. Reverts if the action
    /// is already complete or does not exist.
    function cancel(uint256 actionId) internal {
        CorporateActionStorage storage s = getStorage();
        CorporateActionNode storage node = s.nodes[actionId];

        if (node.effectiveTime == 0) revert ActionDoesNotExist(actionId);
        if (node.effectiveTime <= block.timestamp) revert ActionAlreadyComplete(actionId);

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

        delete s.nodes[actionId];
    }

    /// @notice Count completed actions by walking from head.
    function countCompleted() internal view returns (uint256 count) {
        CorporateActionStorage storage s = getStorage();
        uint256 current = s.head;
        while (current != 0) {
            if (s.nodes[current].effectiveTime > block.timestamp) break;
            count++;
            current = s.nodes[current].next;
        }
    }

    function head() internal view returns (uint256) {
        return getStorage().head;
    }

    function tail() internal view returns (uint256) {
        return getStorage().tail;
    }

    /// @notice Walk completed actions from a cursor, filtering by action type
    /// bitmap. Returns matching action IDs.
    /// @param startActionId Action ID to start from (exclusive). Use 0 to
    /// start from the head.
    /// @param mask Bitmap mask to filter action types. Use type(uint256).max
    /// to match all types.
    /// @param maxResults Maximum results to return.
    /// @return actionIds The matching completed action IDs.
    function walkCompleted(uint256 startActionId, uint256 mask, uint256 maxResults)
        internal
        view
        returns (uint256[] memory actionIds)
    {
        CorporateActionStorage storage s = getStorage();
        uint256 current = startActionId == 0 ? s.head : s.nodes[startActionId].next;

        // First pass: count matches.
        uint256 count = 0;
        uint256 temp = current;
        while (temp != 0 && count < maxResults) {
            CorporateActionNode storage node = s.nodes[temp];
            if (node.effectiveTime > block.timestamp) break;
            if (node.actionType & mask != 0) count++;
            temp = node.next;
        }

        // Second pass: collect.
        actionIds = new uint256[](count);
        uint256 idx = 0;
        while (current != 0 && idx < count) {
            CorporateActionNode storage node = s.nodes[current];
            if (node.effectiveTime > block.timestamp) break;
            if (node.actionType & mask != 0) {
                actionIds[idx++] = current;
            }
            current = node.next;
        }
    }

    /// @notice Walk pending (future) actions from the tail backwards,
    /// filtering by action type bitmap.
    /// @param mask Bitmap mask to filter action types.
    /// @param maxResults Maximum results to return.
    /// @return actionIds Matching pending action IDs (most recent first).
    function walkPending(uint256 mask, uint256 maxResults) internal view returns (uint256[] memory actionIds) {
        CorporateActionStorage storage s = getStorage();

        // First pass: count.
        uint256 count = 0;
        uint256 current = s.tail;
        while (current != 0 && count < maxResults) {
            CorporateActionNode storage node = s.nodes[current];
            if (node.effectiveTime <= block.timestamp) break;
            if (node.actionType & mask != 0) count++;
            current = node.prev;
        }

        // Second pass: collect.
        actionIds = new uint256[](count);
        uint256 idx = 0;
        current = s.tail;
        while (current != 0 && idx < count) {
            CorporateActionNode storage node = s.nodes[current];
            if (node.effectiveTime <= block.timestamp) break;
            if (node.actionType & mask != 0) {
                actionIds[idx++] = current;
            }
            current = node.prev;
        }
    }
}

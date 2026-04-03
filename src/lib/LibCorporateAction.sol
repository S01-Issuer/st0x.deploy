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

/// @dev A corporate action node in the doubly linked list. Nodes are ordered
/// by effectiveTime. An action is "complete" if effectiveTime <= block.timestamp.
/// There is no stored status — completeness is determined by comparing the
/// effectiveTime to the current block timestamp.
struct CorporateActionNode {
    /// Bitmap action type. Each type is a single bit (1 << n). Enables
    /// efficient filtering via bitwise AND with a mask.
    uint256 actionType;
    /// When this action takes effect. Once in the past, the action is
    /// permanently part of the historical record.
    uint64 effectiveTime;
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
/// Corporate actions live in a doubly linked list ordered by effectiveTime.
/// There is no stored status, no stored monotonic ID, no stored counters.
/// An action is "complete" when its effectiveTime passes. Its monotonic ID
/// is its positional index from the head among completed actions. This works
/// because new actions cannot be inserted in the past, so the ordering of
/// completed actions is permanent and their positional IDs are stable.
library LibCorporateAction {
    /// @custom:storage-location erc7201:rain.storage.corporate-action.1
    struct CorporateActionStorage {
        /// Counter for generating internal node IDs (linked list keys).
        /// Starts at 1. These are NOT monotonic action IDs — those are
        /// computed by walking the list.
        uint256 nextNodeId;
        /// Head of the doubly linked list (earliest effectiveTime).
        uint256 head;
        /// Tail of the doubly linked list (latest effectiveTime).
        uint256 tail;
        /// Node storage by internal node ID.
        mapping(uint256 => CorporateActionNode) nodes;
        /// Per-account migration cursor. Stores the internal node ID of the
        /// last node that this account has been migrated through. Migration
        /// walks forward from this node applying balance-affecting multipliers
        /// for all completed nodes encountered.
        mapping(address => uint256) accountMigrationCursor;
    }

    /// @dev Accessor for corporate action storage at the ERC-7201 slot.
    function getStorage() internal pure returns (CorporateActionStorage storage s) {
        bytes32 position = CORPORATE_ACTION_STORAGE_LOCATION;
        assembly ("memory-safe") {
            s.slot := position
        }
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
import {LibERC20Storage} from "./LibERC20Storage.sol";

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

/// @dev Bitmap constant for stock split action type.
uint256 constant ACTION_TYPE_STOCK_SPLIT = 1 << 0;

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

/// Thrown when querying a rebase ID that does not exist.
/// @param rebaseId The invalid rebase ID.
error RebaseDoesNotExist(uint256 rebaseId);

/// Thrown when querying a monotonic action ID that does not exist.
/// @param monotonicId The invalid monotonic ID.
error MonotonicIdDoesNotExist(uint256 monotonicId);

/// Thrown when scheduling an unknown action type bitmap.
/// @param actionType The unrecognised bitmap.
error UnknownActionType(uint256 actionType);

/// Thrown when a stock split multiplier is zero.
error ZeroMultiplier();

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
    using LibDecimalFloat for Float;

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
        /// Counter for balance-affecting corporate actions (rebases). Only
        /// incremented when a stock split (or similar) completes. Accounts
        /// track their version against this.
        uint256 rebaseCount;
        /// Multiplier history indexed by rebase ID (1-based). Each entry is
        /// a Rain float multiplier applied sequentially during migration.
        mapping(uint256 => Float) multipliers;
        /// Mapping from monotonic ID to the rebase ID it produced (0 if the
        /// action was not balance-affecting).
        mapping(uint256 => uint256) monotonicToRebaseId;
        /// Mapping from monotonic ID to node ID for lookups by completed action.
        mapping(uint256 => uint256) monotonicToNodeId;
        /// Per-account rebase version. Tracks which rebase multipliers have
        /// been applied to an account's stored balance. Migration applies
        /// multipliers from (accountRebaseId + 1) through rebaseCount.
        mapping(address => uint256) accountRebaseId;
    }

    /// @dev Accessor for corporate action storage at the ERC-7201 slot.
    function getStorage() internal pure returns (CorporateActionStorage storage s) {
        bytes32 position = CORPORATE_ACTION_STORAGE_LOCATION;
        assembly ("memory-safe") {
            s.slot := position
        }
    }

    /// @notice Process any scheduled actions whose effectiveTime has passed,
    /// transitioning them to COMPLETE and assigning monotonic IDs. For stock
    /// splits, records the multiplier and increments rebaseCount.
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
            s.monotonicToNodeId[s.globalCAID] = current;

            // Balance-affecting actions record multipliers and eagerly
            // update totalSupply so it is immediately correct.
            if (node.actionType & ACTION_TYPE_STOCK_SPLIT != 0) {
                Float multiplier = abi.decode(node.parameters, (Float));
                s.rebaseCount++;
                s.multipliers[s.rebaseCount] = multiplier;
                s.monotonicToRebaseId[s.globalCAID] = s.rebaseCount;

                // Eagerly rebase totalSupply via direct storage write.
                uint256 currentSupply = LibERC20Storage.getTotalSupply();
                // forge-lint: disable-next-line(unsafe-typecast)
                (uint256 newSupply,) = LibDecimalFloat.toFixedDecimalLossy(
                    LibDecimalFloat.mul(LibDecimalFloat.packLossless(int256(currentSupply), 0), multiplier), 0
                );
                LibERC20Storage.setTotalSupply(newSupply);
            }

            current = node.next;
        }
    }

    /// @notice Schedule a new corporate action. Validates the action type and
    /// parameters, then inserts a node into the doubly linked list maintaining
    /// time ordering. Processes any pending completions first.
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

        // Validate action type and parameters.
        if (actionType == ACTION_TYPE_STOCK_SPLIT) {
            Float multiplier = abi.decode(parameters, (Float));
            (int256 coefficient,) = multiplier.unpack();
            if (coefficient == 0) {
                revert ZeroMultiplier();
            }
        } else {
            revert UnknownActionType(actionType);
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

    /// @notice Get a completed action by its monotonic ID.
    /// @param monotonicId The monotonic ID to look up.
    /// @return node The node storage reference.
    function getActionByMonotonicId(uint256 monotonicId) internal view returns (CorporateActionNode storage node) {
        CorporateActionStorage storage s = getStorage();
        if (monotonicId == 0 || monotonicId > s.globalCAID) {
            revert MonotonicIdDoesNotExist(monotonicId);
        }
        uint256 nodeId = s.monotonicToNodeId[monotonicId];
        node = s.nodes[nodeId];
    }

    /// @notice Get the multiplier at a given rebase ID.
    /// @param rebaseId The rebase ID (1-based).
    /// @return multiplier The Rain float multiplier.
    function getMultiplier(uint256 rebaseId) internal view returns (Float multiplier) {
        CorporateActionStorage storage s = getStorage();
        if (rebaseId == 0 || rebaseId > s.rebaseCount) {
            revert RebaseDoesNotExist(rebaseId);
        }
        return s.multipliers[rebaseId];
    }

    /// @notice Get pending (scheduled) actions matching a bitmap mask, walking
    /// backward from the tail. Pending actions cluster at the tail of the list.
    /// @param mask Bitmap mask — returns actions where `actionType & mask != 0`.
    /// @param maxResults Maximum number of results to return.
    /// @return nodeIds Array of matching node IDs (most recent first).
    function getPendingActions(uint256 mask, uint256 maxResults) internal view returns (uint256[] memory nodeIds) {
        CorporateActionStorage storage s = getStorage();
        // First pass: count matches.
        uint256 count = 0;
        uint256 current = s.tail;
        while (current != 0 && count < maxResults) {
            CorporateActionNode storage node = s.nodes[current];
            if (node.status != STATUS_SCHEDULED) {
                // Once we hit a non-scheduled node walking backwards from tail,
                // all remaining nodes are also non-scheduled (completed).
                break;
            }
            if (node.actionType & mask != 0) {
                count++;
            }
            current = node.prev;
        }

        // Second pass: collect IDs.
        nodeIds = new uint256[](count);
        uint256 idx = 0;
        current = s.tail;
        while (current != 0 && idx < count) {
            CorporateActionNode storage node = s.nodes[current];
            if (node.status != STATUS_SCHEDULED) {
                break;
            }
            if (node.actionType & mask != 0) {
                nodeIds[idx] = current;
                idx++;
            }
            current = node.prev;
        }
    }

    /// @notice Get the most recent completed action matching a bitmap mask.
    /// Walks backward from tail past any pending actions, then finds the first
    /// completed match.
    /// @param mask Bitmap mask — matches where `actionType & mask != 0`.
    /// @return nodeId The matching node ID, or 0 if none found.
    function getRecentAction(uint256 mask) internal view returns (uint256 nodeId) {
        CorporateActionStorage storage s = getStorage();
        uint256 current = s.tail;
        while (current != 0) {
            CorporateActionNode storage node = s.nodes[current];
            if (node.status == STATUS_COMPLETE && node.actionType & mask != 0) {
                return current;
            }
            current = node.prev;
        }
        return 0;
    }
}

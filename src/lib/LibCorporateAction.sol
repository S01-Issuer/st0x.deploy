// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float} from "rain.math.float/lib/LibDecimalFloat.sol";

/// @dev String ID for the corporate action storage location.
string constant CORPORATE_ACTION_STORAGE_ID = "rain.storage.corporate-action.1";

/// @dev "rain.storage.corporate-action.1" with the erc7201 formula.
/// keccak256(abi.encode(uint256(keccak256("rain.storage.corporate-action.1")) - 1)) & ~bytes32(uint256(0xff))
bytes32 constant CORPORATE_ACTION_STORAGE_LOCATION = 0xcce8b403dc927e3ec0218603a262b6c4fcc2985ab628bee1e65a6e26753c8300;

/// @dev Duration of the execution window after the effective time. If the
/// action is not executed within this window it becomes expired and can never
/// be executed. 4 hours gives operators a reasonable buffer while keeping the
/// uncertainty window bounded for external systems.
uint256 constant EXECUTION_WINDOW = 4 hours;

/// @dev Status values for the corporate action state machine.
/// SCHEDULED: action has been created and is waiting for its effective time.
/// IN_PROGRESS: action is currently being executed (reentrancy guard).
/// COMPLETE: action has been executed successfully.
/// EXPIRED: action was not executed within the execution window.
uint8 constant STATUS_SCHEDULED = 1;
uint8 constant STATUS_IN_PROGRESS = 2;
uint8 constant STATUS_COMPLETE = 3;
uint8 constant STATUS_EXPIRED = 4;

/// Thrown when scheduling an action with an effective time in the past.
/// @param effectiveTime The effective time that was in the past.
/// @param currentTime The current block timestamp.
error EffectiveTimeInPast(uint256 effectiveTime, uint256 currentTime);

/// Thrown when attempting to execute an action that is not in SCHEDULED status.
/// @param actionId The action that was not schedulable.
/// @param currentStatus The current status of the action.
error ActionNotScheduled(uint256 actionId, uint8 currentStatus);

/// Thrown when attempting to execute an action before its effective time.
/// @param actionId The action that was too early.
/// @param effectiveTime The effective time of the action.
/// @param currentTime The current block timestamp.
error ActionNotEffective(uint256 actionId, uint256 effectiveTime, uint256 currentTime);

/// Thrown when the execution window has passed for a scheduled action.
/// @param actionId The expired action.
/// @param deadline The deadline that was missed.
/// @param currentTime The current block timestamp.
error ActionExpired(uint256 actionId, uint256 deadline, uint256 currentTime);

/// Thrown when querying an action ID that does not exist.
/// @param actionId The invalid action ID.
error ActionDoesNotExist(uint256 actionId);

/// @dev A corporate action record. Stored sequentially in the action history.
/// @param actionType Application-defined type identifier (e.g. stock split).
/// @param status The current lifecycle status.
/// @param effectiveTime When the action takes effect.
/// @param executedTime When the action was actually executed (0 if not yet).
/// @param parameters ABI-encoded parameters specific to the action type.
struct CorporateAction {
    bytes32 actionType;
    uint8 status;
    uint64 effectiveTime;
    uint64 executedTime;
    bytes parameters;
}

/// @title LibCorporateAction
/// @notice Library for corporate action diamond storage. Uses ERC-7201
/// namespaced storage to avoid collisions with existing vault storage slots.
/// Manages the lifecycle state machine, sequential action history, and
/// execution window enforcement.
library LibCorporateAction {
    /// @custom:storage-location erc7201:rain.storage.corporate-action.1
    struct CorporateActionStorage {
        /// The global corporate action ID (CAID). Incremented each time any
        /// corporate action is executed, regardless of type. Serves as the
        /// canonical sequence number that all accounts and external systems
        /// reference.
        uint256 globalCAID;
        /// Sequential counter for action IDs. The next action gets this ID and
        /// it increments. Zero means no actions have been scheduled.
        uint256 nextActionId;
        /// Action records indexed by sequential ID starting from 1.
        mapping(uint256 => CorporateAction) actions;
        /// Multiplier history indexed by CAID (1-based). When a corporate
        /// action that affects balances executes, its multiplier is recorded
        /// here. The migration system applies these sequentially to accounts
        /// that need catching up.
        mapping(uint256 => Float) multipliers;
    }

    /// @dev Accessor for corporate action storage at the ERC-7201 slot.
    function getStorage() internal pure returns (CorporateActionStorage storage s) {
        bytes32 position = CORPORATE_ACTION_STORAGE_LOCATION;
        assembly ("memory-safe") {
            s.slot := position
        }
    }

    /// @notice Schedule a new corporate action. Creates the action record in
    /// SCHEDULED status. The effective time must be in the future.
    /// @param actionType The type identifier for this action.
    /// @param effectiveTime When the action should take effect.
    /// @param parameters ABI-encoded parameters for the action type.
    /// @return actionId The sequential ID assigned to this action.
    function schedule(bytes32 actionType, uint64 effectiveTime, bytes memory parameters)
        internal
        returns (uint256 actionId)
    {
        if (effectiveTime <= block.timestamp) {
            revert EffectiveTimeInPast(effectiveTime, block.timestamp);
        }

        CorporateActionStorage storage s = getStorage();
        // Action IDs start at 1. Zero is reserved as "no action".
        s.nextActionId++;
        actionId = s.nextActionId;

        CorporateAction storage action = s.actions[actionId];
        action.actionType = actionType;
        action.status = STATUS_SCHEDULED;
        action.effectiveTime = effectiveTime;
        action.parameters = parameters;
    }

    /// @notice Transition a scheduled action to IN_PROGRESS. Enforces that the
    /// action is SCHEDULED, that the effective time has arrived, and that the
    /// execution window has not passed.
    /// @param actionId The action to begin executing.
    /// @return action The action record storage pointer for the caller to read.
    function beginExecution(uint256 actionId) internal returns (CorporateAction storage action) {
        CorporateActionStorage storage s = getStorage();
        action = s.actions[actionId];

        if (action.status != STATUS_SCHEDULED) {
            revert ActionNotScheduled(actionId, action.status);
        }

        uint256 effectiveTime = action.effectiveTime;
        if (block.timestamp < effectiveTime) {
            revert ActionNotEffective(actionId, effectiveTime, block.timestamp);
        }

        uint256 deadline = effectiveTime + EXECUTION_WINDOW;
        if (block.timestamp > deadline) {
            revert ActionExpired(actionId, deadline, block.timestamp);
        }

        action.status = STATUS_IN_PROGRESS;
        action.executedTime = uint64(block.timestamp);
    }

    /// @notice Transition an IN_PROGRESS action to COMPLETE. Called after the
    /// action's effects have been applied. Increments the global CAID.
    /// @param actionId The action to complete.
    function completeExecution(uint256 actionId) internal {
        CorporateActionStorage storage s = getStorage();
        CorporateAction storage action = s.actions[actionId];
        action.status = STATUS_COMPLETE;
        s.globalCAID++;
    }

    /// @notice Transition an IN_PROGRESS action to COMPLETE and record a
    /// multiplier. Used by corporate actions that affect balances (splits,
    /// reverse splits). The multiplier is stored at the new CAID so the
    /// migration system can apply it sequentially.
    /// @param actionId The action to complete.
    /// @param multiplier The balance multiplier to record.
    function completeExecutionWithMultiplier(uint256 actionId, Float multiplier) internal {
        CorporateActionStorage storage s = getStorage();
        CorporateAction storage action = s.actions[actionId];
        action.status = STATUS_COMPLETE;
        s.globalCAID++;
        s.multipliers[s.globalCAID] = multiplier;
    }

    /// @notice Read the multiplier recorded at a given CAID.
    /// @param caid The corporate action ID to query.
    /// @return multiplier The multiplier (zero float if no multiplier was
    /// recorded at this CAID).
    function getMultiplier(uint256 caid) internal view returns (Float multiplier) {
        return getStorage().multipliers[caid];
    }

    /// @notice Explicitly expire a scheduled action whose window has passed.
    /// Anyone can call this — it's a public good to clean up state.
    /// @param actionId The action to expire.
    function expire(uint256 actionId) internal {
        CorporateActionStorage storage s = getStorage();
        CorporateAction storage action = s.actions[actionId];

        if (action.status != STATUS_SCHEDULED) {
            revert ActionNotScheduled(actionId, action.status);
        }

        uint256 deadline = action.effectiveTime + EXECUTION_WINDOW;
        if (block.timestamp <= deadline) {
            revert ActionNotEffective(actionId, action.effectiveTime, block.timestamp);
        }

        action.status = STATUS_EXPIRED;
    }

    /// @notice Read an action record. Reverts if the action does not exist.
    /// @param actionId The action to read.
    /// @return action The action record.
    function getAction(uint256 actionId) internal view returns (CorporateAction storage action) {
        CorporateActionStorage storage s = getStorage();
        if (actionId == 0 || actionId > s.nextActionId) {
            revert ActionDoesNotExist(actionId);
        }
        action = s.actions[actionId];
    }
}

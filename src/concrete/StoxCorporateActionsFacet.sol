// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    LibCorporateAction,
    CorporateAction,
    STATUS_SCHEDULED,
    STATUS_IN_PROGRESS,
    STATUS_COMPLETE,
    STATUS_EXPIRED
} from "../lib/LibCorporateAction.sol";
import {ACTION_TYPE_STOCK_SPLIT} from "../lib/LibStockSplit.sol";
import {Float} from "rain.math.float/lib/LibDecimalFloat.sol";
import {IAuthorizeV1} from "ethgild/interface/IAuthorizeV1.sol";
import {OffchainAssetReceiptVault} from "ethgild/concrete/vault/OffchainAssetReceiptVault.sol";

/// @dev Permission for scheduling corporate actions. Separate from execution
/// so that scheduling can be restricted to governance while execution can be
/// delegated to operator hot wallets.
bytes32 constant CORPORATE_ACTION_SCHEDULE = keccak256("CORPORATE_ACTION_SCHEDULE");

/// @dev Permission for executing scheduled corporate actions.
bytes32 constant CORPORATE_ACTION_EXECUTE = keccak256("CORPORATE_ACTION_EXECUTE");

/// Thrown when executing an action with an unknown action type.
/// @param actionType The unrecognised type.
error UnknownActionType(bytes32 actionType);

/// @title StoxCorporateActionsFacet
/// @notice Diamond facet for corporate actions on the vault. This facet shares
/// the vault's storage space via ERC-7201 namespaced storage, so it can be
/// delegatecalled from the vault's fallback without storage collisions.
///
/// Implements the corporate action lifecycle: schedule → execute → complete,
/// with expiry for missed execution windows. Authorization is checked against
/// the vault's existing authorizer contract.
contract StoxCorporateActionsFacet {
    /// Emitted when a corporate action is scheduled.
    /// @param sender The address that scheduled the action.
    /// @param actionId The sequential ID of the new action.
    /// @param actionType The type identifier for this action.
    /// @param effectiveTime When the action takes effect.
    event CorporateActionScheduled(
        address indexed sender, uint256 indexed actionId, bytes32 indexed actionType, uint64 effectiveTime
    );

    /// Emitted when a corporate action completes execution.
    /// @param sender The address that completed execution.
    /// @param actionId The completed action.
    /// @param newGlobalCAID The global CAID after completion.
    event CorporateActionCompleted(address indexed sender, uint256 indexed actionId, uint256 newGlobalCAID);

    /// Emitted when a corporate action expires.
    /// @param sender The address that triggered expiry.
    /// @param actionId The expired action.
    event CorporateActionExpired(address indexed sender, uint256 indexed actionId);

    /// @notice Schedule a stock split. Requires CORPORATE_ACTION_SCHEDULE
    /// permission. The effective time must be in the future.
    /// @param effectiveTime When the split takes effect.
    /// @param multiplier The balance multiplier as a Rain float (e.g. 2 for a
    /// 2-for-1 split, 0.5 for a 1-for-2 reverse split).
    /// @return actionId The sequential ID assigned to this action.
    //slither-disable-next-line reentrancy-events
    function scheduleStockSplit(uint64 effectiveTime, Float multiplier) external returns (uint256 actionId) {
        _authorize(msg.sender, CORPORATE_ACTION_SCHEDULE);
        bytes memory parameters = abi.encode(multiplier);
        actionId = LibCorporateAction.schedule(ACTION_TYPE_STOCK_SPLIT, effectiveTime, parameters);
        emit CorporateActionScheduled(msg.sender, actionId, ACTION_TYPE_STOCK_SPLIT, effectiveTime);
    }

    /// @notice Execute a scheduled corporate action. Requires
    /// CORPORATE_ACTION_EXECUTE permission. The action must be within its
    /// execution window (effective time to effective time + 4 hours).
    /// @param actionId The action to execute.
    //slither-disable-next-line reentrancy-events
    function executeCorporateAction(uint256 actionId) external {
        _authorize(msg.sender, CORPORATE_ACTION_EXECUTE);
        CorporateAction storage action = LibCorporateAction.beginExecution(actionId);

        bytes32 actionType = action.actionType;

        if (actionType == ACTION_TYPE_STOCK_SPLIT) {
            Float multiplier = abi.decode(action.parameters, (Float));
            LibCorporateAction.completeExecutionWithMultiplier(actionId, multiplier);
        } else {
            revert UnknownActionType(actionType);
        }

        uint256 newCAID = LibCorporateAction.getStorage().globalCAID;
        emit CorporateActionCompleted(msg.sender, actionId, newCAID);
    }

    /// @notice Expire a scheduled action whose execution window has passed.
    /// Anyone can call this — no permission required. It is a public good to
    /// clean up state so external systems see accurate status.
    /// @param actionId The action to expire.
    function expireCorporateAction(uint256 actionId) external {
        LibCorporateAction.expire(actionId);
        emit CorporateActionExpired(msg.sender, actionId);
    }

    /// @notice Returns the current global corporate action ID (CAID).
    /// Incremented each time any corporate action executes. External contracts
    /// can use this to detect whether new corporate actions have occurred since
    /// they last checked.
    function globalCAID() external view returns (uint256) {
        return LibCorporateAction.getStorage().globalCAID;
    }

    /// @notice Returns the current rebase count. Only incremented when a
    /// balance-affecting corporate action (e.g. stock split) executes and
    /// records a multiplier. Accounts track their version against this to
    /// determine whether migration is needed.
    function rebaseCount() external view returns (uint256) {
        return LibCorporateAction.getStorage().rebaseCount;
    }

    /// @notice Returns the total number of corporate actions that have been
    /// scheduled (regardless of status).
    function corporateActionCount() external view returns (uint256) {
        return LibCorporateAction.getStorage().nextActionId;
    }

    /// @notice Returns a corporate action record by ID.
    /// @param actionId The action to query (1-indexed).
    /// @return actionType The type identifier.
    /// @return status The current lifecycle status.
    /// @return effectiveTime When the action takes effect.
    /// @return executedTime When the action was executed (0 if not yet).
    /// @return parameters The ABI-encoded action parameters.
    function getCorporateAction(uint256 actionId)
        external
        view
        returns (bytes32 actionType, uint8 status, uint64 effectiveTime, uint64 executedTime, bytes memory parameters)
    {
        CorporateAction storage action = LibCorporateAction.getAction(actionId);
        return (action.actionType, action.status, action.effectiveTime, action.executedTime, action.parameters);
    }

    /// @notice Returns the multiplier recorded at a given rebase ID. Reverts
    /// if the rebase ID does not exist.
    /// @param rebaseId The rebase ID to query (1-based).
    /// @return multiplier The Rain float multiplier.
    function getMultiplier(uint256 rebaseId) external view returns (Float multiplier) {
        return LibCorporateAction.getMultiplier(rebaseId);
    }

    /// @dev Authorize via the vault's authorizer. Since this facet is
    /// delegatecalled by the vault, we can access the vault's storage to
    /// find the authorizer. We read it from the OffchainAssetReceiptVault
    /// storage layout.
    function _authorize(address user, bytes32 permission) internal {
        // The vault exposes authorizer() as a public view function. Since we
        // are running in the vault's context via delegatecall, we can call it
        // on ourselves.
        IAuthorizeV1 auth = OffchainAssetReceiptVault(payable(address(this))).authorizer();
        auth.authorize(user, permission, "");
    }
}

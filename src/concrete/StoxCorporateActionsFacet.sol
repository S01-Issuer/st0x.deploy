// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICorporateActionsV1} from "../interface/ICorporateActionsV1.sol";
import {
    LibCorporateAction,
    CorporateActionNode,
    SCHEDULE_CORPORATE_ACTION,
    CANCEL_CORPORATE_ACTION
} from "../lib/LibCorporateAction.sol";
import {Float} from "rain.math.float/lib/LibDecimalFloat.sol";
import {IAuthorizeV1} from "ethgild/interface/IAuthorizeV1.sol";
import {OffchainAssetReceiptVault} from "ethgild/concrete/vault/OffchainAssetReceiptVault.sol";

/// @title StoxCorporateActionsFacet
/// @notice Diamond facet for corporate actions on the vault. This facet shares
/// the vault's storage space via ERC-7201 namespaced storage, so it can be
/// delegatecalled from the vault's fallback without storage collisions.
///
/// Authorization is checked against the vault's existing authorizer contract
/// using SCHEDULE_CORPORATE_ACTION and CANCEL_CORPORATE_ACTION permissions.
contract StoxCorporateActionsFacet is ICorporateActionsV1 {
    /// Emitted when a corporate action is scheduled into the linked list.
    /// @param sender The address that scheduled the action.
    /// @param nodeId The linked list node ID.
    /// @param actionType The bitmap action type.
    /// @param effectiveTime When the action takes effect.
    event CorporateActionScheduled(
        address indexed sender, uint256 indexed nodeId, uint256 indexed actionType, uint64 effectiveTime
    );

    /// Emitted when a scheduled action completes automatically.
    /// @param nodeId The node that completed.
    /// @param monotonicId The monotonic ID assigned on completion.
    event CorporateActionCompleted(uint256 indexed nodeId, uint256 indexed monotonicId);

    /// Emitted when a scheduled action is cancelled and removed from the list.
    /// @param sender The address that cancelled the action.
    /// @param nodeId The cancelled node ID.
    event CorporateActionCancelled(address indexed sender, uint256 indexed nodeId);

    /// @notice Schedule a new corporate action. Requires SCHEDULE_CORPORATE_ACTION
    /// permission. The effective time must be in the future.
    /// @param actionType Bitmap of action types.
    /// @param effectiveTime When the action takes effect.
    /// @param parameters ABI-encoded parameters for the action type.
    /// @return nodeId The linked list node ID assigned.
    //slither-disable-next-line reentrancy-events
    function scheduleCorporateAction(uint256 actionType, uint64 effectiveTime, bytes calldata parameters)
        external
        returns (uint256 nodeId)
    {
        _authorize(msg.sender, SCHEDULE_CORPORATE_ACTION);
        nodeId = LibCorporateAction.schedule(actionType, effectiveTime, parameters);
        emit CorporateActionScheduled(msg.sender, nodeId, actionType, effectiveTime);
    }

    /// @notice Cancel a scheduled corporate action. Requires
    /// CANCEL_CORPORATE_ACTION permission.
    /// @param nodeId The node to cancel.
    //slither-disable-next-line reentrancy-events
    function cancelCorporateAction(uint256 nodeId) external {
        _authorize(msg.sender, CANCEL_CORPORATE_ACTION);
        LibCorporateAction.cancel(nodeId);
        emit CorporateActionCancelled(msg.sender, nodeId);
    }

    /// @inheritdoc ICorporateActionsV1
    function globalCAID() external view returns (uint256) {
        return LibCorporateAction.getStorage().globalCAID;
    }

    /// @inheritdoc ICorporateActionsV1
    function rebaseCount() external view returns (uint256) {
        return LibCorporateAction.getStorage().rebaseCount;
    }

    /// @inheritdoc ICorporateActionsV1
    function getMultiplier(uint256 rebaseId) external view returns (Float multiplier) {
        return LibCorporateAction.getMultiplier(rebaseId);
    }

    /// @inheritdoc ICorporateActionsV1
    function getAction(uint256 monotonicId)
        external
        view
        returns (uint256 actionType, uint64 effectiveTime, bytes memory parameters)
    {
        CorporateActionNode storage node = LibCorporateAction.getActionByMonotonicId(monotonicId);
        return (node.actionType, node.effectiveTime, node.parameters);
    }

    /// @inheritdoc ICorporateActionsV1
    function getPendingActions(uint256 mask, uint256 maxResults) external view returns (uint256[] memory nodeIds) {
        return LibCorporateAction.getPendingActions(mask, maxResults);
    }

    /// @inheritdoc ICorporateActionsV1
    function getRecentAction(uint256 mask) external view returns (uint256 nodeId) {
        return LibCorporateAction.getRecentAction(mask);
    }

    /// @dev Authorize via the vault's authorizer. Since this facet is
    /// delegatecalled by the vault, `address(this)` is the vault and we can
    /// access its storage to find the authorizer.
    function _authorize(address user, bytes32 permission) internal {
        IAuthorizeV1 auth = OffchainAssetReceiptVault(payable(address(this))).authorizer();
        auth.authorize(user, permission, "");
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICorporateActionsV1} from "../interface/ICorporateActionsV1.sol";
import {LibCorporateAction, SCHEDULE_CORPORATE_ACTION, CANCEL_CORPORATE_ACTION} from "../lib/LibCorporateAction.sol";
import {IAuthorizeV1} from "ethgild/interface/IAuthorizeV1.sol";
import {OffchainAssetReceiptVault} from "ethgild/concrete/vault/OffchainAssetReceiptVault.sol";

/// @title StoxCorporateActionsFacet
/// @notice Diamond facet implementing the corporate action linked list.
contract StoxCorporateActionsFacet is ICorporateActionsV1 {
    event CorporateActionScheduled(
        address indexed sender, uint256 indexed actionId, uint256 actionType, uint64 effectiveTime
    );
    event CorporateActionCancelled(address indexed sender, uint256 indexed actionId);

    /// @inheritdoc ICorporateActionsV1
    function completedActionCount() external view override returns (uint256) {
        return LibCorporateAction.countCompleted();
    }

    /// @inheritdoc ICorporateActionsV1
    function scheduleCorporateAction(uint256 actionType, uint64 effectiveTime, bytes calldata parameters)
        external
        override
        returns (uint256 actionId)
    {
        _authorize(msg.sender, SCHEDULE_CORPORATE_ACTION);
        actionId = LibCorporateAction.schedule(actionType, effectiveTime, parameters);
        emit CorporateActionScheduled(msg.sender, actionId, actionType, effectiveTime);
    }

    /// @inheritdoc ICorporateActionsV1
    function cancelCorporateAction(uint256 actionId) external override {
        _authorize(msg.sender, CANCEL_CORPORATE_ACTION);
        LibCorporateAction.cancel(actionId);
        emit CorporateActionCancelled(msg.sender, actionId);
    }

    /// @dev Authorize via the vault's authorizer. Since this facet is
    /// delegatecalled by the vault, `address(this)` is the vault and we can
    /// access its storage to find the authorizer.
    function _authorize(address user, bytes32 permission) internal {
        IAuthorizeV1 auth = OffchainAssetReceiptVault(payable(address(this))).authorizer();
        auth.authorize(user, permission, "");
    }
}

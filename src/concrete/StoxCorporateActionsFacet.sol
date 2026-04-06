// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICorporateActionsV1} from "../interface/ICorporateActionsV1.sol";
import {LibCorporateAction, SCHEDULE_CORPORATE_ACTION, CANCEL_CORPORATE_ACTION} from "../lib/LibCorporateAction.sol";
import {IAuthorizeV1} from "ethgild/interface/IAuthorizeV1.sol";
import {OffchainAssetReceiptVault} from "ethgild/concrete/vault/OffchainAssetReceiptVault.sol";

/// @title StoxCorporateActionsFacet
/// @notice Diamond facet for corporate actions on the vault. This facet shares
/// the vault's storage space via ERC-7201 namespaced storage, so it can be
/// delegatecalled from the vault's fallback without storage collisions.
///
/// PR1 establishes the facet architecture and authorization wiring.
/// Subsequent PRs add the linked list, scheduling, and query functions.
contract StoxCorporateActionsFacet is ICorporateActionsV1 {
    event CorporateActionScheduled(
        address indexed sender, uint256 indexed actionIndex, uint256 actionType, uint64 effectiveTime
    );
    event CorporateActionCancelled(address indexed sender, uint256 indexed actionIndex);

    /// @inheritdoc ICorporateActionsV1
    function completedActionCount() external pure override returns (uint256) {
        return LibCorporateAction.countCompleted();
    }

    /// @inheritdoc ICorporateActionsV1
    function scheduleCorporateAction(bytes32 typeHash, uint64 effectiveTime, bytes calldata parameters)
        external
        override
        returns (uint256 actionIndex)
    {
        _authorize(msg.sender, SCHEDULE_CORPORATE_ACTION);
        uint256 actionType = LibCorporateAction.resolveActionType(typeHash, parameters);
        actionIndex = LibCorporateAction.schedule(actionType, effectiveTime, parameters);
        emit CorporateActionScheduled(msg.sender, actionIndex, actionType, effectiveTime);
    }

    /// @inheritdoc ICorporateActionsV1
    function cancelCorporateAction(uint256 actionIndex) external override {
        _authorize(msg.sender, CANCEL_CORPORATE_ACTION);
        LibCorporateAction.cancel(actionIndex);
        emit CorporateActionCancelled(msg.sender, actionIndex);
    }

    /// @dev Authorize via the vault's authorizer. Since this facet is
    /// delegatecalled by the vault, `address(this)` is the vault and we can
    /// access its storage to find the authorizer.
    function _authorize(address user, bytes32 permission) internal {
        IAuthorizeV1 auth = OffchainAssetReceiptVault(payable(address(this))).authorizer();
        auth.authorize(user, permission, "");
    }
}

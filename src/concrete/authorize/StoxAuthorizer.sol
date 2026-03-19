// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVaultAuthorizerV1,
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "ethgild/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {Unauthorized} from "ethgild/interface/IAuthorizeV1.sol";
import {UPDATE_NAME_SYMBOL, UPDATE_NAME_SYMBOL_ADMIN} from "../CorporateActionRegistry.sol";

/// @title StoxAuthorizer
/// @notice Extends the base OffchainAssetReceiptVaultAuthorizerV1 with
/// additional permissions required by st0x corporate actions.
///
/// The base authorizer handles all the standard vault permissions (CERTIFY,
/// DEPOSIT, WITHDRAW, CONFISCATE_*, TRANSFER_*). This extension adds:
///
/// - UPDATE_NAME_SYMBOL: Permission to update a vault's name and symbol via
///   a corporate action. The CorporateActionRegistry contract should be granted
///   this role so it can dispatch name/symbol updates to vaults.
///
/// Future corporate action permissions (REBASE, etc.) will be added here as
/// the registry gains new action types. The authorizer is the single source of
/// truth for all permission checks — no new permission models are introduced.
///
/// Same RBAC pattern as the base: each permission has a corresponding ADMIN
/// role. The initial admin receives all admin roles and can delegate as needed.
contract StoxAuthorizer is OffchainAssetReceiptVaultAuthorizerV1 {
    /// @inheritdoc OffchainAssetReceiptVaultAuthorizerV1
    function initialize(bytes memory data) external override initializer returns (bytes32) {
        return _initializeStox(data);
    }

    /// Internal initialization that sets up both base and st0x-specific roles.
    /// Separated from the initializer modifier so inheriting contracts can
    /// access it.
    function _initializeStox(bytes memory data) internal returns (bytes32) {
        bytes32 result = _initialize(data);

        OffchainAssetReceiptVaultAuthorizerV1Config memory config =
            abi.decode(data, (OffchainAssetReceiptVaultAuthorizerV1Config));

        // Corporate action permissions follow the same pattern as the base
        // permissions: each permission has a self-administering admin role,
        // and the initial admin gets the admin role.
        _setRoleAdmin(UPDATE_NAME_SYMBOL, UPDATE_NAME_SYMBOL_ADMIN);
        _setRoleAdmin(UPDATE_NAME_SYMBOL_ADMIN, UPDATE_NAME_SYMBOL_ADMIN);
        _grantRole(UPDATE_NAME_SYMBOL_ADMIN, config.initialAdmin);

        return result;
    }

    /// @inheritdoc OffchainAssetReceiptVaultAuthorizerV1
    function authorize(address user, bytes32 permission, bytes memory data) public virtual override {
        // Corporate action permissions are pure RBAC — if the user has the
        // role, they're authorized. No special transfer/certification logic.
        if (permission == UPDATE_NAME_SYMBOL) {
            if (hasRole(permission, user)) {
                return;
            }
            revert Unauthorized(user, permission, data);
        }

        // Everything else delegates to the base authorizer which handles
        // TRANSFER_SHARES, TRANSFER_RECEIPT (with certification logic),
        // and all other standard RBAC permissions.
        super.authorize(user, permission, data);
    }
}

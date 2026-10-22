// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.2.7-pr349/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    ConfigRegistryOffchainAssetReceiptVaultAuthorizerV1
} from "rain-vats-0.2.7-pr349/src/concrete/authorize/ConfigRegistryOffchainAssetReceiptVaultAuthorizerV1.sol";
import {ICLONEABLE_V2_SUCCESS} from "rain-factory-0.2.4/src/interface/ICloneableV2.sol";
import {SCHEDULE_CORPORATE_ACTION, CANCEL_CORPORATE_ACTION} from "../../lib/LibCorporateAction.sol";

/// @dev Role admin for SCHEDULE_CORPORATE_ACTION.
bytes32 constant SCHEDULE_CORPORATE_ACTION_ADMIN = keccak256("SCHEDULE_CORPORATE_ACTION_ADMIN");

/// @dev Role admin for CANCEL_CORPORATE_ACTION.
bytes32 constant CANCEL_CORPORATE_ACTION_ADMIN = keccak256("CANCEL_CORPORATE_ACTION_ADMIN");

/// @title StoxOffchainAssetReceiptVaultAuthorizerV1
/// @notice Extends the base authorizer with corporate action role admin
/// configuration. The base authorizer handles corporate action permissions
/// via its generic RBAC path, but cannot grant them because no role admin is
/// configured. This contract adds SCHEDULE_CORPORATE_ACTION_ADMIN and
/// CANCEL_CORPORATE_ACTION_ADMIN roles following the same pattern as the
/// existing role admin hierarchy, granted to the same initial admin the
/// `ConfigRegistry` resolves for the other five.
contract StoxOffchainAssetReceiptVaultAuthorizerV1 is ConfigRegistryOffchainAssetReceiptVaultAuthorizerV1 {
    /// @dev The base admins, then the corporate-action admins on the same
    /// initial admin, unless the base did not succeed.
    function _initialize(OffchainAssetReceiptVaultAuthorizerV1Config memory config)
        internal
        virtual
        override
        returns (bytes32)
    {
        bytes32 result = super._initialize(config);
        if (result != ICLONEABLE_V2_SUCCESS) {
            return result;
        }

        _setRoleAdmin(SCHEDULE_CORPORATE_ACTION, SCHEDULE_CORPORATE_ACTION_ADMIN);
        _setRoleAdmin(SCHEDULE_CORPORATE_ACTION_ADMIN, SCHEDULE_CORPORATE_ACTION_ADMIN);

        _setRoleAdmin(CANCEL_CORPORATE_ACTION, CANCEL_CORPORATE_ACTION_ADMIN);
        _setRoleAdmin(CANCEL_CORPORATE_ACTION_ADMIN, CANCEL_CORPORATE_ACTION_ADMIN);

        _grantRole(SCHEDULE_CORPORATE_ACTION_ADMIN, config.initialAdmin);
        _grantRole(CANCEL_CORPORATE_ACTION_ADMIN, config.initialAdmin);

        return ICLONEABLE_V2_SUCCESS;
    }
}

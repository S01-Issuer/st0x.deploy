// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVaultAuthorizerV1,
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "ethgild/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {ICLONEABLE_V2_SUCCESS} from "rain.factory/interface/ICloneableV2.sol";
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
/// existing role admin hierarchy.
contract StoxOffchainAssetReceiptVaultAuthorizerV1 is OffchainAssetReceiptVaultAuthorizerV1 {
    /// @inheritdoc OffchainAssetReceiptVaultAuthorizerV1
    function initialize(bytes memory data) public override initializer returns (bytes32) {
        OffchainAssetReceiptVaultAuthorizerV1Config memory config =
            abi.decode(data, (OffchainAssetReceiptVaultAuthorizerV1Config));

        bytes32 result = _initialize(config);
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

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IAuthorizeV1, Unauthorized} from "rain-vats-0.1.6/src/interface/IAuthorizeV1.sol";

/// @dev Permissive authorizer used by the fallback routing tests. Records the
/// most recent call and allows every permission by default so we can exercise
/// the forward-to-facet path without reproducing the full ethgild auth setup.
contract PermissiveAuthorizer is IAuthorizeV1 {
    address public lastUser;
    bytes32 public lastPermission;
    bytes public lastData;
    uint256 public callCount;
    bool public denyMode;

    function setDenyMode(bool deny) external {
        denyMode = deny;
    }

    function authorize(address user, bytes32 permission, bytes memory data) external override {
        callCount++;
        lastUser = user;
        lastPermission = permission;
        lastData = data;
        if (denyMode) {
            revert Unauthorized(user, permission, data);
        }
    }
}

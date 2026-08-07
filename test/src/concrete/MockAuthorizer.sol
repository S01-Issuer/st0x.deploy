// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IAuthorizeV1, Unauthorized} from "rain-vats-0.1.7/src/interface/IAuthorizeV1.sol";

/// @dev Mock authorizer used by the facet tests. Records the most recent
/// `authorize` call so tests can assert the per-action context that the facet
/// passes through. When `denyMode` is true, every `authorize` call reverts
/// with `Unauthorized`, exercising the auth-denial code path.
contract MockAuthorizer is IAuthorizeV1 {
    bool public denyMode;
    address public lastUser;
    bytes32 public lastPermission;
    bytes public lastData;
    uint256 public callCount;

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

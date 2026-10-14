// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @notice A `(role, grantee)` pair on an `AccessControl` contract.
struct RoleGrant {
    bytes32 role;
    address grantee;
}

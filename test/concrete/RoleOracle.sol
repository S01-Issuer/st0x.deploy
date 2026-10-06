// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

contract RoleOracle {
    mapping(bytes32 => mapping(address => bool)) public hasRole;

    function set(bytes32 role, address account, bool held) external {
        hasRole[role][account] = held;
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {BuildIdealRoles} from "../../script/BuildIdealRoles.sol";

contract BuildIdealRolesHarness is BuildIdealRoles {
    function callNetwork(uint256 chainId) external pure returns (string memory) {
        return network(chainId);
    }

    function callSuffix(uint256 chainId) external pure returns (string memory) {
        return suffix(chainId);
    }

    function callRoleName(bytes32 role) external pure returns (string memory) {
        return roleName(role);
    }

    function callGranteeName(uint256 chainId, address grantee) external pure returns (string memory) {
        return granteeName(chainId, grantee);
    }
}

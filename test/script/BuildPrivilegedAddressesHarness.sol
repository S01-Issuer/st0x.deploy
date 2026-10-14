// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {BuildPrivilegedAddresses} from "../../script/BuildPrivilegedAddresses.sol";

contract BuildPrivilegedAddressesHarness is BuildPrivilegedAddresses {
    function callNetwork(uint256 chainId) external pure returns (string memory) {
        return network(chainId);
    }

    function callSuffix(uint256 chainId) external pure returns (string memory) {
        return suffix(chainId);
    }

    function callOwnerName(address owner) external pure returns (string memory) {
        return ownerName(owner);
    }

    function callRoleName(bytes32 role) external pure returns (string memory) {
        return roleName(role);
    }

    function callGranteeName(uint256 chainId, address grantee) external pure returns (string memory) {
        return granteeName(chainId, grantee);
    }
}

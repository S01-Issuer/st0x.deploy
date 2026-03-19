// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @dev Vault implementation whose initialize(bytes) returns bytes32(0)
/// instead of ICLONEABLE_V2_SUCCESS.
contract BadInitializeVault {
    function initialize(bytes calldata) external pure returns (bytes32) {
        return bytes32(0);
    }
}

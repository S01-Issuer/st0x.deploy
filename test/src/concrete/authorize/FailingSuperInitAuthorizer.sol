// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.1.7/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";

/// @dev Overrides _initialize to return a non-success value, simulating
/// a parent initialization failure.
contract FailingSuperInitAuthorizer is StoxOffchainAssetReceiptVaultAuthorizerV1 {
    bytes32 public constant FAILURE_SENTINEL = bytes32(uint256(1));

    function _initialize(OffchainAssetReceiptVaultAuthorizerV1Config memory) internal pure override returns (bytes32) {
        return FAILURE_SENTINEL;
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVaultAuthorizerV1,
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.2.7-pr349/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";

bytes32 constant FAILURE_SENTINEL = bytes32(uint256(1));

/// @dev A base `_initialize` that does not succeed.
abstract contract FailingBaseInitAuthorizer is OffchainAssetReceiptVaultAuthorizerV1 {
    function _initialize(OffchainAssetReceiptVaultAuthorizerV1Config memory)
        internal
        virtual
        override
        returns (bytes32)
    {
        return FAILURE_SENTINEL;
    }
}

/// @dev Linearised so `StoxOffchainAssetReceiptVaultAuthorizerV1`'s `super`
/// is `FailingBaseInitAuthorizer`.
contract FailingSuperInitAuthorizer is FailingBaseInitAuthorizer, StoxOffchainAssetReceiptVaultAuthorizerV1 {
    function _initialize(OffchainAssetReceiptVaultAuthorizerV1Config memory config)
        internal
        override(FailingBaseInitAuthorizer, StoxOffchainAssetReceiptVaultAuthorizerV1)
        returns (bytes32)
    {
        return super._initialize(config);
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVaultAuthorizerV1,
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.2.20/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";

/// @dev A base authorizer whose _initialize returns a non-success value.
contract FailingBaseInitAuthorizer is OffchainAssetReceiptVaultAuthorizerV1 {
    bytes32 public constant FAILURE_SENTINEL = bytes32(uint256(1));

    function _initialize(OffchainAssetReceiptVaultAuthorizerV1Config memory)
        internal
        virtual
        override
        returns (bytes32)
    {
        return FAILURE_SENTINEL;
    }
}

/// @dev The Stox authorizer over FailingBaseInitAuthorizer: its super._initialize fails.
contract FailingSuperInitAuthorizer is FailingBaseInitAuthorizer, StoxOffchainAssetReceiptVaultAuthorizerV1 {
    function _initialize(OffchainAssetReceiptVaultAuthorizerV1Config memory config)
        internal
        override(FailingBaseInitAuthorizer, StoxOffchainAssetReceiptVaultAuthorizerV1)
        returns (bytes32)
    {
        return super._initialize(config);
    }
}

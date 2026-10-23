// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVaultAuthorizerV1,
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.2.7-pr349/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    ConfigRegistryOffchainAssetReceiptVaultAuthorizerV1
} from "rain-vats-0.2.7-pr349/src/concrete/authorize/ConfigRegistryOffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {FailingBaseInitAuthorizer} from "./FailingBaseInitAuthorizer.sol";

/// @dev Linearised so `StoxOffchainAssetReceiptVaultAuthorizerV1`'s `super`
/// is `FailingBaseInitAuthorizer`. Takes the plain config.
contract FailingSuperInitAuthorizer is FailingBaseInitAuthorizer, StoxOffchainAssetReceiptVaultAuthorizerV1 {
    function initialize(bytes memory data)
        external
        override(OffchainAssetReceiptVaultAuthorizerV1, ConfigRegistryOffchainAssetReceiptVaultAuthorizerV1)
        initializer
        returns (bytes32)
    {
        return _initialize(abi.decode(data, (OffchainAssetReceiptVaultAuthorizerV1Config)));
    }

    function _initialize(OffchainAssetReceiptVaultAuthorizerV1Config memory config)
        internal
        override(FailingBaseInitAuthorizer, StoxOffchainAssetReceiptVaultAuthorizerV1)
        returns (bytes32)
    {
        return super._initialize(config);
    }
}

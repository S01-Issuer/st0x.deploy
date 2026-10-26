// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Region} from "./LibProdTokenConfig.sol";

/// @title LibStoxConfig
/// @notice st0x's bindings in rain-deploy's `ConfigRegistry` V3, all under the
/// root authority: the same account on every chain, so a consumer's creation
/// code is chain-invariant while each chain binds its own value.
library LibStoxConfig {
    /// @notice The authority every st0x binding is read under.
    address internal constant ROOT_AUTHORITY = address(0x0b300013CD54a8F1aC40981f80FaaA18b8Cc1E4c);

    /// @notice `abi.encode(address)`: the beacon production tokens proxy.
    bytes32 internal constant VAULT_BEACON_NAME = keccak256("st0x.vault-beacon.v1");

    /// @notice `abi.encode(address)`: the beacon production receipts proxy.
    bytes32 internal constant RECEIPT_BEACON_NAME = keccak256("st0x.receipt-beacon.v1");

    /// @notice `abi.encode(address)`: the beacon production wrappers proxy.
    bytes32 internal constant WRAPPER_BEACON_NAME = keccak256("st0x.wrapper-beacon.v1");

    /// @notice `abi.encode(OffchainAssetReceiptVaultRbacV1)`: the owner and
    /// authorizer of US tokens.
    bytes32 internal constant US_RBAC_NAME = keccak256("st0x.rbac.us.v1");

    /// @notice `abi.encode(OffchainAssetReceiptVaultRbacV1)`: the owner and
    /// authorizer of EU tokens.
    bytes32 internal constant EU_RBAC_NAME = keccak256("st0x.rbac.eu.v1");

    /// @notice The RBAC binding a region's tokens initialize from.
    /// @param region The region.
    /// @return The binding's name.
    function rbacName(Region region) internal pure returns (bytes32) {
        return region == Region.EU ? EU_RBAC_NAME : US_RBAC_NAME;
    }
}

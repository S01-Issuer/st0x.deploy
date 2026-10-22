// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {LibConfigRegistry} from "rain-deploy-0.1.21/src/lib/LibConfigRegistry.sol";

/// @title LibStoxConfig
/// @notice st0x's bindings in rain-deploy's `ConfigRegistry` V3, all under the
/// root authority: the same account on every chain, so a consumer's creation
/// code is chain-invariant while each chain binds its own value.
library LibStoxConfig {
    /// @notice The authority every st0x binding is read under.
    address internal constant ROOT_AUTHORITY = address(0x0b300013CD54a8F1aC40981f80FaaA18b8Cc1E4c);

    /// @notice `abi.encode(address)`: the initial owner of every beacon a
    /// current st0x deploy constructs.
    bytes32 internal constant BEACON_OWNER = keccak256("st0x.beacon-owner.v1");

    /// @notice `abi.encode(address)`: the initial admin of every V4 authoriser
    /// clone, the holder of its seven `_ADMIN` roles.
    bytes32 internal constant AUTHORISER_ADMIN = keccak256("st0x.authoriser-admin.v1");

    /// @notice The bound beacon owner. Reverts `NameNotRegistered` where it is
    /// unbound.
    /// @return The owner.
    function beaconOwner() internal view returns (address) {
        (bytes memory value,) = LibConfigRegistry.resolve(ROOT_AUTHORITY, BEACON_OWNER);
        return abi.decode(value, (address));
    }

    /// @notice The bound authoriser admin. Reverts `NameNotRegistered` where
    /// it is unbound.
    /// @return The admin.
    function authoriserAdmin() internal view returns (address) {
        (bytes memory value,) = LibConfigRegistry.resolve(ROOT_AUTHORITY, AUTHORISER_ADMIN);
        return abi.decode(value, (address));
    }
}

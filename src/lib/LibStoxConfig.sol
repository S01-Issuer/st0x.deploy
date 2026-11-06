// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {LibConfigRegistry} from "rain-deploy-0.1.30/src/lib/LibConfigRegistry.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";

/// @title LibStoxConfig
/// @notice st0x's bindings in rain-deploy's `ConfigRegistry` V5, all under the
/// root authority: the same account on every chain, so a consumer's creation
/// code is chain-invariant while each chain binds its own value.
library LibStoxConfig {
    /// @notice `abi.encode(address)`: the beacon production tokens proxy.
    bytes32 internal constant VAULT_BEACON_NAME = keccak256("st0x.vault-beacon.v1");

    /// @notice `abi.encode(address)`: the beacon production receipts proxy.
    bytes32 internal constant RECEIPT_BEACON_NAME = keccak256("st0x.receipt-beacon.v1");

    /// @notice `abi.encode(address)`: the beacon production wrappers proxy.
    bytes32 internal constant WRAPPER_BEACON_NAME = keccak256("st0x.wrapper-beacon.v1");

    /// @notice `abi.encode(address)`: the initial owner every st0x beacon is
    /// constructed with, read once in its constructor; ownership moves on-chain
    /// after.
    bytes32 internal constant BEACON_INITIAL_OWNER_NAME = keccak256("st0x.beacon-initial-owner.v1");

    /// @notice The bound beacon initial owner. Reverts `NameNotRegistered` where
    /// it is unbound.
    /// @return The beacon initial owner.
    function beaconInitialOwner() internal view returns (address) {
        // slither-disable-next-line unused-return
        (bytes memory value,) = LibConfigRegistry.resolve(
            LibRegistryAuthority.ROOT_AUTHORITY, BEACON_INITIAL_OWNER_NAME, keccak256("address")
        );
        return abi.decode(value, (address));
    }

    /// @notice `abi.encode(address)`: the timelock's initial proposer and
    /// canceller, read once at its construction.
    bytes32 internal constant TIMELOCK_INITIAL_PROPOSER_NAME = keccak256("st0x.timelock-initial-proposer.v1");

    /// @return The timelock's initial proposer; reverts while unbound.
    function timelockInitialProposer() internal view returns (address) {
        // slither-disable-next-line unused-return
        (bytes memory value,) = LibConfigRegistry.resolve(
            LibRegistryAuthority.ROOT_AUTHORITY, TIMELOCK_INITIAL_PROPOSER_NAME, keccak256("address")
        );
        return abi.decode(value, (address));
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    BYTECODE_HASH as STOX_RECEIPT_HASH,
    DEPLOYED_ADDRESS as STOX_RECEIPT_ADDR
} from "../generated/StoxReceipt.pointers.sol";
import {
    BYTECODE_HASH as STOX_RECEIPT_VAULT_HASH,
    DEPLOYED_ADDRESS as STOX_RECEIPT_VAULT_ADDR
} from "../generated/StoxReceiptVault.pointers.sol";
import {
    BYTECODE_HASH as STOX_WRAPPED_TOKEN_VAULT_HASH,
    DEPLOYED_ADDRESS as STOX_WRAPPED_TOKEN_VAULT_ADDR
} from "../generated/StoxWrappedTokenVault.pointers.sol";
import {
    BYTECODE_HASH as STOX_UNIFIED_DEPLOYER_HASH,
    DEPLOYED_ADDRESS as STOX_UNIFIED_DEPLOYER_ADDR
} from "../generated/StoxUnifiedDeployer.pointers.sol";
import {
    BYTECODE_HASH as STOX_WRAPPED_TOKEN_VAULT_BEACON_HASH,
    DEPLOYED_ADDRESS as STOX_WRAPPED_TOKEN_VAULT_BEACON_ADDR
} from "../generated/StoxWrappedTokenVaultBeacon.pointers.sol";
import {
    BYTECODE_HASH as STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_HASH,
    DEPLOYED_ADDRESS as STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_ADDR
} from "../generated/StoxWrappedTokenVaultBeaconSetDeployer.pointers.sol";
import {
    BYTECODE_HASH as STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_HASH,
    DEPLOYED_ADDRESS as STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_ADDR
} from "../generated/StoxOffchainAssetReceiptVaultBeaconSetDeployer.pointers.sol";

/// @title LibProdDeployV2
/// @notice V2 production deployment addresses and codehashes for the Stox
/// deployment via the Zoltu deterministic deployer. Addresses are
/// deterministic and identical across all EVM networks.
library LibProdDeployV2 {
    /// @dev The initial owner for all V2 beacons, including
    /// StoxWrappedTokenVaultBeacon and the beacons created by
    /// StoxOffchainAssetReceiptVaultBeaconSetDeployer. Resolves to
    /// rainlang.eth.
    /// https://basescan.org/address/0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b
    address constant BEACON_INITIAL_OWNER = address(0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b);

    /// @dev Deterministic Zoltu address for StoxReceipt.
    address constant STOX_RECEIPT = STOX_RECEIPT_ADDR;
    /// @dev Codehash of StoxReceipt when deployed via Zoltu.
    bytes32 constant STOX_RECEIPT_CODEHASH = STOX_RECEIPT_HASH;

    /// @dev Deterministic Zoltu address for StoxReceiptVault.
    address constant STOX_RECEIPT_VAULT = STOX_RECEIPT_VAULT_ADDR;
    /// @dev Codehash of StoxReceiptVault when deployed via Zoltu.
    bytes32 constant STOX_RECEIPT_VAULT_CODEHASH = STOX_RECEIPT_VAULT_HASH;

    /// @dev Deterministic Zoltu address for StoxWrappedTokenVault.
    address constant STOX_WRAPPED_TOKEN_VAULT = STOX_WRAPPED_TOKEN_VAULT_ADDR;
    /// @dev Codehash of StoxWrappedTokenVault when deployed via Zoltu.
    bytes32 constant STOX_WRAPPED_TOKEN_VAULT_CODEHASH = STOX_WRAPPED_TOKEN_VAULT_HASH;

    /// @dev Deterministic Zoltu address for StoxUnifiedDeployer.
    address constant STOX_UNIFIED_DEPLOYER = STOX_UNIFIED_DEPLOYER_ADDR;
    /// @dev Codehash of StoxUnifiedDeployer when deployed via Zoltu.
    bytes32 constant STOX_UNIFIED_DEPLOYER_CODEHASH = STOX_UNIFIED_DEPLOYER_HASH;

    /// @dev Deterministic Zoltu address for StoxWrappedTokenVaultBeacon.
    address constant STOX_WRAPPED_TOKEN_VAULT_BEACON = STOX_WRAPPED_TOKEN_VAULT_BEACON_ADDR;
    /// @dev Codehash of StoxWrappedTokenVaultBeacon when deployed via Zoltu.
    bytes32 constant STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH = STOX_WRAPPED_TOKEN_VAULT_BEACON_HASH;

    /// @dev Deterministic Zoltu address for StoxOffchainAssetReceiptVaultBeaconSetDeployer.
    address constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER =
        STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_ADDR;
    /// @dev Codehash of StoxOffchainAssetReceiptVaultBeaconSetDeployer when deployed via Zoltu.
    bytes32 constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH =
        STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_HASH;

    /// @dev Deterministic Zoltu address for StoxWrappedTokenVaultBeaconSetDeployer.
    address constant STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER = STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_ADDR;
    /// @dev Codehash of StoxWrappedTokenVaultBeaconSetDeployer when deployed via Zoltu.
    bytes32 constant STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH =
        STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_HASH;
}

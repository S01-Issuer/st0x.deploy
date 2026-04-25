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
import {
    BYTECODE_HASH as STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_HASH,
    DEPLOYED_ADDRESS as STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_ADDR
} from "../generated/StoxOffchainAssetReceiptVaultAuthorizerV1.pointers.sol";
import {
    BYTECODE_HASH as STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_HASH,
    DEPLOYED_ADDRESS as STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_ADDR
} from "../generated/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.pointers.sol";
import {
    BYTECODE_HASH as STOX_CORPORATE_ACTIONS_FACET_HASH,
    DEPLOYED_ADDRESS as STOX_CORPORATE_ACTIONS_FACET_ADDR
} from "../generated/StoxCorporateActionsFacet.pointers.sol";

/// @title LibProdDeployV3
/// @notice V3 production deployment addresses and codehashes for the Stox
/// deployment via the Zoltu deterministic deployer. V3 adds ERC-165 to
/// deployers, deployer interface inheritance, corporate action role admins
/// to the authorizer, and updates the upstream rain.vats dependency.
/// Addresses are deterministic and identical across all EVM networks.
library LibProdDeployV3 {
    /// @dev The initial owner for all beacons. Resolves to rainlang.eth.
    address constant BEACON_INITIAL_OWNER = address(0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b);

    /// @dev Deterministic Zoltu address for StoxReceipt (unchanged from V2).
    address constant STOX_RECEIPT = STOX_RECEIPT_ADDR;
    bytes32 constant STOX_RECEIPT_CODEHASH = STOX_RECEIPT_HASH;

    /// @dev Deterministic Zoltu address for StoxReceiptVault (unchanged from V2).
    address constant STOX_RECEIPT_VAULT = STOX_RECEIPT_VAULT_ADDR;
    bytes32 constant STOX_RECEIPT_VAULT_CODEHASH = STOX_RECEIPT_VAULT_HASH;

    /// @dev Deterministic Zoltu address for StoxWrappedTokenVault (unchanged from V2).
    address constant STOX_WRAPPED_TOKEN_VAULT = STOX_WRAPPED_TOKEN_VAULT_ADDR;
    bytes32 constant STOX_WRAPPED_TOKEN_VAULT_CODEHASH = STOX_WRAPPED_TOKEN_VAULT_HASH;

    /// @dev Deterministic Zoltu address for StoxUnifiedDeployer.
    address constant STOX_UNIFIED_DEPLOYER = STOX_UNIFIED_DEPLOYER_ADDR;
    bytes32 constant STOX_UNIFIED_DEPLOYER_CODEHASH = STOX_UNIFIED_DEPLOYER_HASH;

    /// @dev Deterministic Zoltu address for StoxWrappedTokenVaultBeacon (unchanged from V2).
    address constant STOX_WRAPPED_TOKEN_VAULT_BEACON = STOX_WRAPPED_TOKEN_VAULT_BEACON_ADDR;
    bytes32 constant STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH = STOX_WRAPPED_TOKEN_VAULT_BEACON_HASH;

    /// @dev Deterministic Zoltu address for StoxOffchainAssetReceiptVaultBeaconSetDeployer.
    address constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER =
        STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_ADDR;
    bytes32 constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH =
        STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_HASH;

    /// @dev Deterministic Zoltu address for StoxWrappedTokenVaultBeaconSetDeployer.
    address constant STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER = STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_ADDR;
    bytes32 constant STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH =
        STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_HASH;

    /// @dev Deterministic Zoltu address for StoxOffchainAssetReceiptVaultAuthorizerV1.
    address constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1 =
        STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_ADDR;
    bytes32 constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH =
        STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_HASH;

    /// @dev Deterministic Zoltu address for StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.
    address constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1 =
        STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_ADDR;
    bytes32 constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CODEHASH =
        STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_HASH;

    /// @dev Deterministic Zoltu address for StoxCorporateActionsFacet. The
    /// vault's `fallback()` hardcodes this address and delegatecalls every
    /// non-matching selector here; changing the facet bytecode requires
    /// redeploying the vault implementation too.
    address constant STOX_CORPORATE_ACTIONS_FACET = STOX_CORPORATE_ACTIONS_FACET_ADDR;
    /// @dev Codehash of StoxCorporateActionsFacet when deployed via Zoltu.
    bytes32 constant STOX_CORPORATE_ACTIONS_FACET_CODEHASH = STOX_CORPORATE_ACTIONS_FACET_HASH;
}

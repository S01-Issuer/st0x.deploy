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

/// @title LibProdDeployV2
/// @notice V2 production deployment addresses and codehashes for the Stox
/// deployment via the Zoltu deterministic deployer. Addresses are
/// deterministic and identical across all EVM networks.
library LibProdDeployV2 {
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
}

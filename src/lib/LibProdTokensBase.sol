// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title LibProdTokensBase
/// @notice Production token instance addresses on Base. These are beacon proxy
/// instances created via the V1 deployer, not implementation contracts.
/// Each token set consists of a receipt (ERC-1155), receipt vault (ERC-20),
/// and wrapped token vault (ERC-4626).
library LibProdTokensBase {
    // =========================================================================
    // tMSTR / wtMSTR — MicroStrategy Incorporated ST0x
    // Deployed via V1 OffchainAssetReceiptVaultBeaconSetDeployer + V1 StoxWrappedTokenVaultBeaconSetDeployer
    // =========================================================================

    /// @dev Receipt (ERC-1155) for tMSTR.
    /// https://basescan.org/address/0x1c1fEF6f7b8e576219554b1d11c8aF29D00C0cEC
    address constant MSTR_RECEIPT = address(0x1c1fEF6f7b8e576219554b1d11c8aF29D00C0cEC);

    /// @dev Receipt vault (ERC-20, "tMSTR") — the OffchainAssetReceiptVault instance.
    /// https://basescan.org/address/0x013b782F402d61aa1004CCA95b9f5Bb402c9d5FE
    address constant MSTR_RECEIPT_VAULT = address(0x013b782F402d61aa1004CCA95b9f5Bb402c9d5FE);

    /// @dev Wrapped token vault (ERC-4626, "wtMSTR") — the StoxWrappedTokenVault instance.
    /// https://basescan.org/address/0xFF05E1bD696900dc6A52CA35Ca61Bb1024eDa8e2
    address constant MSTR_WRAPPED_TOKEN_VAULT = address(0xFF05E1bD696900dc6A52CA35Ca61Bb1024eDa8e2);
}

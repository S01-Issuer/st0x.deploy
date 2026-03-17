// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title LibProdDeploy
/// @notice Hardcoded production deployment addresses and codehashes for the
/// Stox deployment on Base. Used by deployer contracts and verified by fork
/// tests.
library LibProdDeploy {
    /// @dev The initial owner for beacon set deployers. Resolves to
    /// rainlang.eth.
    /// https://basescan.org/address/0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b
    address constant BEACON_INITIAL_OWNER = address(0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b);

    /// @dev The OffchainAssetReceiptVault beacon set deployer on Base.
    /// https://basescan.org/address/0x2191981ca2477b745870cc307cbeb4cb2967ace3
    address constant OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER =
        address(0x2191981Ca2477B745870cC307cbEB4cB2967ACe3);

    /// @dev The StoxWrappedTokenVault beacon set deployer on Base.
    /// https://basescan.org/address/0xef6f9d21ed2e2742bfd3dfcf67829e4855884fab
    address constant STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER = address(0xeF6f9D21ED2E2742bfd3dFcf67829e4855884faB);

    /// @dev A deployed StoxWrappedTokenVault instance on Base.
    /// https://basescan.org/address/0x80A79767F2d7c24A0577f791eC2Af74a7c9A1eD1
    address constant STOX_WRAPPED_TOKEN_VAULT = address(0x80A79767F2d7c24A0577f791eC2Af74a7c9A1eD1);

    /// @dev The StoxUnifiedDeployer on Base.
    /// https://basescan.org/address/0x821a71a313bdDDc94192CF0b5F6f5bC31Ac75853
    address constant STOX_UNIFIED_DEPLOYER = address(0x821a71a313bdDDc94192CF0b5F6f5bC31Ac75853);

    /// @dev Expected codehash of the OffchainAssetReceiptVault beacon set
    /// deployer on Base. Includes immutable beacon addresses so is
    /// deployment-specific.
    bytes32 constant PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1 =
        0xa64b7746d1822476d36059e4334b86f98768a39b5af8c1def28021bb3c31087f;

    /// @dev Expected codehash of the StoxWrappedTokenVault beacon set deployer
    /// on Base. Includes immutable beacon address so is deployment-specific.
    bytes32 constant PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1 =
        0x9e6bb58fd7e4e4b5b057665a58564363469a7b0690bcf60931e9bc1ce7bc814c;

    /// @dev Expected codehash of the StoxWrappedTokenVault proxy on Base.
    bytes32 constant PROD_STOX_WRAPPED_TOKEN_VAULT_BASE_CODEHASH_V1 =
        0xb9eb10ad0bd97d88446bc7db5f16f9ffdca89add7fd7f5d6582490d308e5b614;

    /// @dev Expected codehash of the StoxUnifiedDeployer on Base. Used by fork
    /// tests to verify deployment integrity.
    bytes32 constant PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1 =
        0xb5167a6cfec58378938913cf93dd0c7cf0aab1501beb653b0b6e0be6f5b8e072;
}

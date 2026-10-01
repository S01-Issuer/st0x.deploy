// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title LibProdDeployV2BaseOverrides
/// @notice The on-chain state of the beacons inside the V2
/// OffchainAssetReceiptVaultBeaconSetDeployer on Base, where it diverges from
/// `LibProdDeployV2`:
///
/// Receipt beacon (0x7EFeCb081f3A14Bc86cFA45373a23121a5D90Ec1):
///   - Implementation is the V1 StoxReceipt.
///   - Owner is the V2 StoxReceipt contract, which cannot call `upgradeTo`
///     or `transferOwnership` — the beacon is permanently locked.
///
/// Vault beacon (0x7328C39029f6Ee7Ff8d48932FFB4eCD44b6Fbb8C):
///   - Implementation is the V1 StoxReceiptVault
///     (`LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION`).
///   - Owner is the V2 StoxReceiptVault contract, which cannot call
///     `upgradeTo` or `transferOwnership` — the beacon is permanently locked.
///
/// Production tokens on Base use the V1 deployer's beacons. Fork tests assert
/// these values.
library LibProdDeployV2BaseOverrides {
    /// @dev The receipt beacon's implementation: the V1 StoxReceipt.
    /// https://basescan.org/address/0xE7573879D73455Dc92cB4087Fa8177594387CbCD
    address constant RECEIPT_BEACON_IMPLEMENTATION = address(0xE7573879D73455Dc92cB4087Fa8177594387CbCD);

    /// @dev The receipt beacon's owner: the V2 StoxReceipt contract, which
    /// cannot call `upgradeTo` or `transferOwnership`, so the beacon is
    /// permanently locked.
    /// https://basescan.org/address/0xbAB0E6b7B5dDA86FB8ba81c00aEA0Ceb8b73686b
    address constant RECEIPT_BEACON_OWNER = address(0xbAB0E6b7B5dDA86FB8ba81c00aEA0Ceb8b73686b);

    /// @dev The vault beacon's implementation: the V1 StoxReceiptVault.
    /// https://basescan.org/address/0x8EFfCe5Ebb047F215dF1d8522c32c7C9DE239f39
    address constant VAULT_BEACON_IMPLEMENTATION = address(0x8EFfCe5Ebb047F215dF1d8522c32c7C9DE239f39);

    /// @dev The vault beacon's owner: the V2 StoxReceiptVault contract, which
    /// cannot call `upgradeTo` or `transferOwnership`, so the beacon is
    /// permanently locked.
    /// https://basescan.org/address/0xc95dB340A7a100881626475d41BFf70857Aa920D
    address constant VAULT_BEACON_OWNER = address(0xc95dB340A7a100881626475d41BFf70857Aa920D);
}

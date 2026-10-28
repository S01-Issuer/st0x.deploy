// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title LibProdDeployV2BaseOverrides
/// @notice Documents the actual on-chain state of V2 OARV deployer beacons on
/// Base where they diverge from the expected values in LibProdDeployV2.
///
/// Post-deployment, the beacons inside the V2
/// OffchainAssetReceiptVaultBeaconSetDeployer on Base were corrupted:
///
/// Receipt beacon (0x7EFeCb081f3A14Bc86cFA45373a23121a5D90Ec1):
///   - Implementation downgraded from V2 StoxReceipt to V1 StoxReceipt.
///   - Ownership transferred from rainlang.eth to the V2 StoxReceipt contract,
///     which cannot call upgradeTo — the beacon is effectively bricked.
///
/// Vault beacon (0x7328C39029f6Ee7Ff8d48932FFB4eCD44b6Fbb8C):
///   - Implementation is correct (V2 StoxReceiptVault).
///   - Ownership transferred from rainlang.eth to the V2 StoxReceiptVault
///     contract, which cannot call upgradeTo — the beacon is effectively
///     bricked.
///
/// Production tokens on Base use the V1 deployer's beacons (which are healthy).
/// These overrides exist solely to keep fork tests reflecting on-chain reality.
library LibProdDeployV2BaseOverrides {
    /// @dev V1 StoxReceipt implementation — the receipt beacon was downgraded
    /// to this address post-deployment.
    /// https://basescan.org/address/0xE7573879D73455Dc92cB4087Fa8177594387CbCD
    address constant RECEIPT_BEACON_IMPLEMENTATION = address(0xE7573879D73455Dc92cB4087Fa8177594387CbCD);

    /// @dev Receipt beacon owner — transferred to the V2 StoxReceipt contract.
    /// This contract cannot call upgradeTo or transferOwnership, so the beacon
    /// is permanently locked.
    /// https://basescan.org/address/0xbAB0E6b7B5dDA86FB8ba81c00aEA0Ceb8b73686b
    address constant RECEIPT_BEACON_OWNER = address(0xbAB0E6b7B5dDA86FB8ba81c00aEA0Ceb8b73686b);

    /// @dev Vault beacon implementation — changed from the V2
    /// StoxReceiptVault to a different address post-deployment.
    /// https://basescan.org/address/0x8EFfCe5Ebb047F215dF1d8522c32c7C9DE239f39
    address constant VAULT_BEACON_IMPLEMENTATION = address(0x8EFfCe5Ebb047F215dF1d8522c32c7C9DE239f39);

    /// @dev Vault beacon owner — transferred to the V2 StoxReceiptVault
    /// contract. Same situation as the receipt beacon: permanently locked.
    /// https://basescan.org/address/0xc95dB340A7a100881626475d41BFf70857Aa920D
    address constant VAULT_BEACON_OWNER = address(0xc95dB340A7a100881626475d41BFf70857Aa920D);
}

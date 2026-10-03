// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IST0xVaultBeaconSet} from "../interface/IST0xVaultBeaconSet.sol";
import {LibProdDeployV4} from "../generated/LibProdDeployV4.sol";

/// @title LibProdBeacons0_1_1
/// @notice The four ST0x production beacons of the deterministic **0.1.1**
/// deployment and the implementations they were bootstrapped with — every
/// address resolved from the generated `0_1_1` pins. The whole set is
/// Zoltu-deterministic, so these are the same addresses on every chain that
/// bootstraps at 0.1.1 (Ethereum mainnet and HyperEVM among them).
/// @dev Implementations are deployed deterministically (Zoltu), so a
/// version's impl has the same address on every chain; `implementations()`
/// references the generated `0_1_1` impl pins directly.
///
/// Beacons are per-chain. A proxy points at the beacon and the beacon at the
/// versioned impl, so cross-chain parity compares the beacon's
/// implementation, not its address. The wrapped-token-vault beacon has its
/// own generated pin (`STOX_WRAPPED_TOKEN_VAULT_BEACON_0_1_1`). The receipt
/// and receipt-vault beacons have no individual generated pointers — they are
/// created by, and read live from, the generated `0_1_1` beacon-set-deployer
/// (`STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1`) via its
/// `iReceiptBeacon()` / `iOffchainAssetReceiptVaultBeacon()` getters. The
/// orchestrator beacon is its own generated pin (`ST0X_ORCHESTRATOR_BEACON`).
///
/// A fresh 0.1.1 bootstrap leaves all four beacons owned by
/// `LibProdDeployV1.BEACON_INITIAL_OWNER` (rainlang.eth, the deploy EOA);
/// `LibBeaconInvariants` asserts the live owner.
// The version-suffixed name mirrors the generated `0_1_1` pin naming;
// CapWords would obscure the version.
// slither-disable-next-line naming-convention
library LibProdBeacons0_1_1 {
    /// @notice The four production beacons, in a fixed order (receipt,
    /// receipt vault, wrapped token vault, orchestrator) — index-aligned with
    /// `implementations()` and with `LibBeaconInvariants`' `*_BEACON_INDEX`
    /// constants. The receipt / receipt-vault beacons are read from the
    /// `0_1_1` beacon-set-deployer's getters; the wrapped and orchestrator
    /// beacons are their generated pins. `view` because the first two are
    /// live reads from the deployer (which is why callers run against a
    /// bootstrapped chain's fork).
    /// @return The four beacon addresses.
    function beacons() internal view returns (address[4] memory) {
        IST0xVaultBeaconSet deployer =
            IST0xVaultBeaconSet(LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1);
        return [
            address(deployer.iReceiptBeacon()),
            address(deployer.iOffchainAssetReceiptVaultBeacon()),
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_0_1_1,
            LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON
        ];
    }

    /// @notice The implementation each beacon is bootstrapped with, index-
    /// aligned with `beacons()`. Referenced from the generated `0_1_1` impl
    /// pins — the same deterministic addresses on every chain.
    /// @dev These are the bootstrap-time implementations, not the live ones.
    /// A fresh chain comes up serving them; on a live fork the receipt and
    /// receipt-vault beacons serve the `0_1_30` impls, so only the
    /// wrapped-token-vault entry matches what its beacon serves. A caller
    /// wanting the live implementation names the `0_1_30` pin explicitly.
    /// @return The four bootstrap-time implementation addresses.
    function implementations() internal pure returns (address[4] memory) {
        return [
            LibProdDeployV4.STOX_RECEIPT_0_1_1,
            LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1,
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_0_1_1,
            LibProdDeployV4.ST0X_ORCHESTRATOR_0_1_30
        ];
    }
}

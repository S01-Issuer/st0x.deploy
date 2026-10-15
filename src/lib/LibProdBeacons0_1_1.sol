// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IST0xVaultBeaconSet} from "../interface/IST0xVaultBeaconSet.sol";
import {LibProdDeployV4} from "../generated/LibProdDeployV4.sol";

/// @title LibProdBeacons0_1_1
/// @notice The four ST0x production beacons of the deterministic **0.1.1**
/// deployment and the implementations they were BOOTSTRAPPED with — every
/// address traced to the generated `0_1_1` pins rather than re-pasted as
/// fresh literals.
/// The whole set is Zoltu-deterministic, so these are the SAME addresses on
/// every chain that bootstraps at 0.1.1 (Ethereum mainnet; HyperEVM per
/// RAI-1511).
/// @dev A 0.1.1-bootstrap chain's beacons and impls are the `0_1_1`
/// deployment. Two principles keep this lib free of
/// pasted addresses:
///
/// 1. **Implementations are chain-agnostic.** They are deployed
///    deterministically (Zoltu), so a version's impl has the SAME address on
///    every chain — matching impls across chains is the goal. `implementations()`
///    references the generated `0_1_1` impl pins directly; there is no second
///    copy to drift.
///
/// 2. **Beacons are per-chain, sourced from the generated `0_1_1` pins.** A
///    proxy points at the beacon; the beacon points at the (versioned) impl —
///    the beacon is the non-versioned anchor, so cross-chain parity compares
///    the beacon's IMPLEMENTATION, not its address. The wrapped-token-vault
///    beacon has its own generated pin (`STOX_WRAPPED_TOKEN_VAULT_BEACON_0_1_1`)
///    so it is referenced directly. The receipt and receipt-vault beacons are
///    NOT emitted as individual generated pointers — they are created by, and
///    read live from, the generated `0_1_1` beacon-set-deployer
///    (`STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1`) via its
///    `iReceiptBeacon()` / `iOffchainAssetReceiptVaultBeacon()` getters. The
///    orchestrator beacon is its own generated pin
///    (`ST0X_ORCHESTRATOR_BEACON`). So all four beacon addresses resolve from
///    generated pins, none are hand-pasted.
///
/// As deployed, all four beacons are owned by
/// `LibProdDeployV1.BEACON_INITIAL_OWNER` (rainlang.eth, the deploy EOA). The
/// Ethereum migration (`20260716-migrate-beacon-owners-ethereum`) transfers
/// them to `LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM`, mirroring what
/// `MigrateBeaconOwners` already did for Base's beacons.
// The version-suffixed name mirrors the generated `0_1_1` pin naming that
// this lib exists to trace; CapWords would obscure the version.
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

    /// @notice The implementation each beacon is BOOTSTRAPPED with, index-
    /// aligned with `beacons()`. Referenced from the generated `0_1_1` impl
    /// pins — the same deterministic addresses on every chain, so no separate
    /// per-chain copy.
    /// @dev **These are the bootstrap-time implementations, not the live
    /// ones.** A fresh chain comes up serving them, and
    /// `script/20260909-upgrade-and-migrate-token-beacons.s.sol` pre-flights
    /// against exactly this state before moving the receipt and receipt-vault
    /// beacons onto 0.1.30. Every chain has since run that upgrade, so on a
    /// live fork only the wrapped-token-vault entry still matches what its
    /// beacon serves. Do NOT "correct" the receipt / receipt-vault entries to
    /// the live 0.1.30 impls: that would break the upgrade script's
    /// pre-flight on the next chain to bootstrap. A caller wanting the LIVE
    /// implementation names the `0_1_30` pin explicitly instead.
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

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IST0xVaultBeaconSet} from "../interface/IST0xVaultBeaconSet.sol";
import {LibProdDeployV4} from "../generated/LibProdDeployV4.sol";

/// @title LibProdBeaconsEthereum
/// @notice The three ST0x production beacons on **Ethereum mainnet** and the
/// implementations they point at — every address traced to the generated
/// `0_1_1` pins rather than re-pasted as fresh literals.
/// @dev Ethereum bootstrapped fresh at the **0.1.1** release, so its beacons
/// and impls are the `0_1_1` deployment. Two principles keep this lib free of
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
///    `iReceiptBeacon()` / `iOffchainAssetReceiptVaultBeacon()` getters. So all
///    three beacon addresses resolve from `0_1_1` pins, none are hand-pasted.
///
/// As deployed, all three beacons are owned by
/// `LibProdDeployV1.BEACON_INITIAL_OWNER` (rainlang.eth, the deploy EOA). The
/// Ethereum migration (`20260716-migrate-beacon-owners-ethereum`) transfers
/// them to `LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM`, mirroring what
/// `MigrateBeaconOwners` already did for Base's beacons.
library LibProdBeaconsEthereum {
    /// @notice The three production beacons, in a fixed order (receipt,
    /// receipt vault, wrapped token vault) — index-aligned with
    /// `implementations()`. The receipt / receipt-vault beacons are read from
    /// the `0_1_1` beacon-set-deployer's getters; the wrapped beacon is its
    /// generated `0_1_1` pin. `view` because the first two are live reads from
    /// the deployer (which is why callers run against an Ethereum fork).
    /// @return The three Ethereum beacon addresses.
    function beacons() internal view returns (address[3] memory) {
        IST0xVaultBeaconSet deployer =
            IST0xVaultBeaconSet(LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1);
        return [
            address(deployer.iReceiptBeacon()),
            address(deployer.iOffchainAssetReceiptVaultBeacon()),
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_0_1_1
        ];
    }

    /// @notice The implementation each beacon points at, index-aligned with
    /// `beacons()`. Referenced from the generated `0_1_1` impl pins — the same
    /// deterministic addresses on every chain, so no separate Ethereum copy.
    /// Asserted unchanged across the ownership transfer.
    /// @return The three implementation addresses.
    function implementations() internal pure returns (address[3] memory) {
        return [
            LibProdDeployV4.STOX_RECEIPT_0_1_1,
            LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1,
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_0_1_1
        ];
    }
}

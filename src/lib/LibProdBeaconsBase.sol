// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibProdDeployV1} from "./LibProdDeployV1.sol";
import {LibProdDeployV4} from "../generated/LibProdDeployV4.sol";

/// @title LibProdBeaconsBase
/// @notice The three ST0x production beacons on **Base** and the
/// implementations they point at — the Base counterpart of
/// `LibProdBeacons0_1_1`, same shape and index order so per-chain
/// consumers dispatch to one lib per chain instead of hand-assembling
/// either side.
/// @dev Base's production tokens run on the **V1-generation** beacon
/// addresses: deployed at V1, retained through every implementation upgrade
/// since (a beacon address is a per-chain deploy artifact that never
/// changes; only the implementation it serves is upgraded). Later-generation
/// beacon deploys on Base — the deterministic 0.1.1 Zoltu set among them —
/// exist on-chain but were never adopted by production and are deliberately
/// not represented here.
///
/// No pasted addresses: the beacons reference the hand-pinned V1 constants
/// in `LibProdDeployV1`, and the implementations reference the generated
/// `0_1_1` impl pins (deterministic Zoltu deploys, the SAME addresses on
/// every chain) — the V4 upgrade pointed Base's V1-address beacons at those
/// 0.1.1 implementations.
library LibProdBeaconsBase {
    /// @notice The three production beacons, in a fixed order (receipt,
    /// receipt vault, wrapped token vault) — index-aligned with
    /// `implementations()` and with `LibProdBeacons0_1_1.beacons()`.
    /// @return The three Base beacon addresses.
    function beacons() internal pure returns (address[3] memory) {
        return [
            LibProdDeployV1.STOX_RECEIPT_BEACON_V1,
            LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1,
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1
        ];
    }

    /// @notice The implementation each beacon points at, index-aligned with
    /// `beacons()`. Referenced from the generated `0_1_1` impl pins — the
    /// same deterministic addresses `LibProdBeacons0_1_1.implementations()`
    /// resolves, because implementation parity across chains is the goal.
    /// @return The three implementation addresses.
    function implementations() internal pure returns (address[3] memory) {
        return [
            LibProdDeployV4.STOX_RECEIPT_0_1_1,
            LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1,
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_0_1_1
        ];
    }
}

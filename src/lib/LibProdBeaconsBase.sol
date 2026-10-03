// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibProdDeployV1} from "./LibProdDeployV1.sol";
import {LibProdDeployV4} from "../generated/LibProdDeployV4.sol";

/// @title LibProdBeaconsBase
/// @notice The four ST0x production beacons on **Base** and the
/// implementations they were bootstrapped with — the Base counterpart of
/// `LibProdBeacons0_1_1`, same shape and index order.
/// @dev Base's production tokens point at the V1 beacon addresses
/// (`LibProdDeployV1`); a beacon address never changes, only the
/// implementation it serves. The deterministic 0.1.1 beacon set also exists
/// on Base, but no production token points at it, so it is not represented
/// here.
///
/// The beacons reference the V1 constants in `LibProdDeployV1`; the
/// implementations reference the generated `0_1_1` impl pins (deterministic
/// Zoltu deploys, the same addresses on every chain).
library LibProdBeaconsBase {
    /// @notice The four production beacons, in a fixed order (receipt,
    /// receipt vault, wrapped token vault, orchestrator) — index-aligned with
    /// `implementations()`, with `LibProdBeacons0_1_1.beacons()` and with
    /// `LibBeaconInvariants`' `*_BEACON_INDEX` constants.
    /// @return The four Base beacon addresses.
    function beacons() internal pure returns (address[4] memory) {
        return [
            LibProdDeployV1.STOX_RECEIPT_BEACON_V1,
            LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1,
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1,
            LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON
        ];
    }

    /// @notice The implementation each beacon was bootstrapped with, index-
    /// aligned with `beacons()`. Referenced from the generated `0_1_1` impl
    /// pins — the same deterministic addresses
    /// `LibProdBeacons0_1_1.implementations()` resolves.
    /// @dev Bootstrap-time, not live: Base's receipt and receipt-vault
    /// beacons serve the `0_1_30` impls, so only the wrapped-token-vault
    /// entry matches what its beacon serves. See
    /// `LibProdBeacons0_1_1.implementations()`.
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

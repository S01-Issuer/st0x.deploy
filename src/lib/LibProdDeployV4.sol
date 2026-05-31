// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title LibProdDeployV4
/// @notice V4 production deployment pins for the ST0x contract set on Base.
/// V4 is rebuilt against the patched `rain.vats` tag carrying the high-severity
/// vulnerability fix (rainlanguage/rain.vats#313). Every deterministic Zoltu
/// address derives from the compiled bytecode, so the patched rain.vats tag
/// produces a new address for every Zoltu-deployed implementation in this set.
///
/// **All address and codehash constants in this lib are PLACEHOLDERS** until
/// (a) DM cuts the patched rain.vats tag, (b) we bump the `rain-vats` Soldeer
/// pin in this repo, and (c) `script/BuildPointers.s.sol` regenerates the
/// `src/generated/*.pointers.sol` files. Once those land, swap each placeholder
/// for the imported `BYTECODE_HASH` / `DEPLOYED_ADDRESS` from the regenerated
/// pointers (mirroring `LibProdDeployV3`'s structure), and rename every
/// `_RAIN_VATS_TBD` suffix to the actual tag (e.g. `_RAIN_VATS_0_1_6`).
///
/// While the placeholders are in place, any script or test that asserts
/// against these constants (notably the V3 upgrade script and its fork tests)
/// will deliberately fail — the red CI is the forcing function that the
/// rebuild on the patched tag must complete before the V3 upgrade can ship.
///
/// Naming convention (per Josh + DM, 2026-05-31): the rain.vats tag is encoded
/// in each deployed-contract constant name so a future tag bump produces a new
/// constant rather than silently overwriting an existing one. The lib name
/// itself is generic (`LibProdDeployV4`) — Soldeer's import path already
/// encodes the version at the dependency boundary, so the lib name doesn't
/// need to.
///
/// `LibProdDeployV3` is retained for archaeological reference (it pins the
/// pre-patch rain.vats 0.1.5 addresses that are not safe to ship) but should
/// no longer be referenced by any active script.
library LibProdDeployV4 {
    /// @notice Placeholder rain.vats tag suffix. Search-and-replace this token
    /// across the whole lib with the real tag (e.g. `RAIN_VATS_0_1_6`) once DM
    /// cuts and propagates the patched rain.vats tag.
    /// @dev String constant, present only as a written reminder — Solidity has
    /// no preprocessor so the rename must be done by hand in the source.
    string constant RAIN_VATS_TAG_PLACEHOLDER = "RAIN_VATS_TBD";

    /// @notice The beacon initial owner. Resolves to rainlang.eth. Unchanged
    /// across V1 / V2 / V3 / V4; this is the EOA that receives ownership at
    /// deploy time and is migrated to the ST0x token-owner Safe by
    /// `LibProdMigrateBeaconOwnership`.
    address constant BEACON_INITIAL_OWNER = address(0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b);

    // =========================================================================
    // Deployed-contract pointers — all PLACEHOLDER until patched rain.vats tag
    // lands and `BuildPointers` regenerates `src/generated/*.pointers.sol`.
    // Rename every `_RAIN_VATS_TBD` suffix to the actual tag at that point.
    // =========================================================================

    address constant STOX_RECEIPT_RAIN_VATS_TBD = address(0);
    bytes32 constant STOX_RECEIPT_CODEHASH_RAIN_VATS_TBD = bytes32(0);

    address constant STOX_RECEIPT_VAULT_RAIN_VATS_TBD = address(0);
    bytes32 constant STOX_RECEIPT_VAULT_CODEHASH_RAIN_VATS_TBD = bytes32(0);

    address constant STOX_WRAPPED_TOKEN_VAULT_RAIN_VATS_TBD = address(0);
    bytes32 constant STOX_WRAPPED_TOKEN_VAULT_CODEHASH_RAIN_VATS_TBD = bytes32(0);

    address constant STOX_UNIFIED_DEPLOYER_RAIN_VATS_TBD = address(0);
    bytes32 constant STOX_UNIFIED_DEPLOYER_CODEHASH_RAIN_VATS_TBD = bytes32(0);

    address constant STOX_WRAPPED_TOKEN_VAULT_BEACON_RAIN_VATS_TBD = address(0);
    bytes32 constant STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH_RAIN_VATS_TBD = bytes32(0);

    address constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RAIN_VATS_TBD = address(0);
    bytes32 constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH_RAIN_VATS_TBD = bytes32(0);

    address constant STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_RAIN_VATS_TBD = address(0);
    bytes32 constant STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH_RAIN_VATS_TBD = bytes32(0);

    /// @dev The corporate-action-aware authoriser impl. The clone deployed for
    /// the issuer (see `LibProdAuthoriser.STOX_PROD_AUTHORISER_V4_CLONE` once
    /// added) points at this impl via EIP-1167.
    address constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RAIN_VATS_TBD = address(0);
    bytes32 constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH_RAIN_VATS_TBD = bytes32(0);

    address constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_RAIN_VATS_TBD = address(0);
    bytes32 constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CODEHASH_RAIN_VATS_TBD = bytes32(0);

    /// @dev The corporate-actions facet. The receipt vault's `fallback()`
    /// hardcodes this address and delegatecalls every non-matching selector
    /// here, so a facet bytecode change forces a vault impl redeploy too. With
    /// the new rain.vats tag the receipt vault impl is rebuilt, so this facet
    /// is rebuilt in lock-step.
    address constant STOX_CORPORATE_ACTIONS_FACET_RAIN_VATS_TBD = address(0);
    bytes32 constant STOX_CORPORATE_ACTIONS_FACET_CODEHASH_RAIN_VATS_TBD = bytes32(0);
}

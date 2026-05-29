// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibProdTokensBase} from "./LibProdTokensBase.sol";

/// @notice Minimal `Ownable`-like surface used by ST0x receipt vaults.
/// Every production receipt vault exposes `owner()`; this library only
/// needs the getter, not the transfer/renounce mutators. Declared inline
/// here so the token-invariant bundle owns its only external surface
/// rather than depending on a richer token-side interface that could drift.
interface IOwnable {
    /// @notice The current owner of the contract.
    /// @return The owner address.
    function owner() external view returns (address);
}

/// @notice Minimal authoriser-getter surface exposed by ST0x receipt
/// vaults. Declared inline (returning `address`) rather than importing
/// the upstream `IAuthorizableV1` so this library owns its only external
/// surface and doesn't carry the upstream's richer return type.
interface IAuthorisable {
    /// @notice The authoriser contract gating restricted vault operations.
    /// @return The authoriser address.
    function authorizer() external view returns (address);
}

/// @notice A production receipt vault's `owner()` does not match the owner
/// the uniform-ownership invariant expected every vault to share. Surfaces
/// the exact vault address that breaks the invariant rather than a generic
/// mismatch.
/// @param vault The receipt vault whose owner was read.
/// @param expected The address every vault is expected to report as
/// `owner()`.
/// @param actual The owner address returned by `vault.owner()`.
error ReceiptVaultOwnerMismatch(address vault, address expected, address actual);

/// @notice A production receipt vault's `authorizer()` does not match the
/// authoriser every vault is expected to share. Surfaces the exact vault
/// that breaks the uniform-authoriser invariant.
/// @param vault The receipt vault whose authoriser was read.
/// @param expected The authoriser address every vault is expected to share.
/// @param actual The authoriser address returned by `vault.authorizer()`.
error ReceiptVaultAuthoriserMismatch(address vault, address expected, address actual);

/// @title LibTokenInvariants
/// @notice Reusable token-side uniformity invariants for the ST0x
/// production receipt vaults on Base. Each assertion iterates the vault
/// list emitted by `LibProdTokensBase.productionReceiptVaults` and either
/// returns silently when the invariant holds against the live chain state
/// or reverts with a typed error that pinpoints the offending vault.
/// @dev These are token-side prod invariants: a receipt vault's owner and
/// authoriser uniformity is a property of the token deployment, not of the
/// Safe multisig. They are composed into `LibSafeInvariants.assertAll`
/// alongside the Safe-side invariants so the full production state bundle
/// carries both, but they live here because owner/authoriser uniformity is
/// a token-side concern that does not belong in a Safe-named library. Both
/// asserts are also callable standalone for focused drift detection.
library LibTokenInvariants {
    /// @notice Assert that every production receipt vault reports the same
    /// `owner()`. Iterates `LibProdTokensBase.productionReceiptVaults` and
    /// reverts with `ReceiptVaultOwnerMismatch` on the first vault whose
    /// `owner()` diverges from `expectedOwner`, surfacing the offending
    /// vault.
    /// @dev A divergent owner means a token is controlled by a different
    /// account than the rest of the system — the class of inconsistency
    /// this invariant exists to prevent. Composed into
    /// `LibSafeInvariants.assertAll` (with the Safe as the expected owner)
    /// as a first-class token-side invariant; also callable standalone.
    /// @param expectedOwner The address every production receipt vault is
    /// expected to report as `owner()`.
    function assertUniformOwnership(address expectedOwner) internal view {
        address[] memory vaults = LibProdTokensBase.productionReceiptVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            address actualOwner = IOwnable(vaults[i]).owner();
            if (actualOwner != expectedOwner) {
                revert ReceiptVaultOwnerMismatch(vaults[i], expectedOwner, actualOwner);
            }
        }
    }

    /// @notice Assert that every production receipt vault reports the same
    /// authoriser. Iterates `LibProdTokensBase.productionReceiptVaults` and
    /// reverts with `ReceiptVaultAuthoriserMismatch` on the first vault whose
    /// `authorizer()` diverges from `expected`, surfacing the offending vault.
    /// @dev A divergent authoriser means a token is gated by a different RBAC
    /// contract than the rest of the system — the class of inconsistency this
    /// invariant exists to prevent. Composed into
    /// `LibSafeInvariants.assertAll` as a first-class token-side invariant;
    /// also callable standalone.
    /// @param expected The authoriser address every production receipt vault
    /// is expected to share.
    function assertUniformAuthoriser(address expected) internal view {
        address[] memory vaults = LibProdTokensBase.productionReceiptVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            address actual = IAuthorisable(vaults[i]).authorizer();
            if (actual != expected) {
                revert ReceiptVaultAuthoriserMismatch(vaults[i], expected, actual);
            }
        }
    }
}

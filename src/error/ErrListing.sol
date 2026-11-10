// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

/// Thrown when `nameListing` is called on a token initialized without an asset id.
error ListingTokenHasNoAssetId();

/// Thrown when the listed asset id is not the token's own.
/// @param stored The token's asset id.
/// @param listed The asset id passed to `nameListing`.
error ListingAssetIdMismatch(string stored, string listed);

/// Thrown when `nameListing` is called on a token that already has an underlying ticker or name.
error ListingAlreadyNamed();

/// Thrown when the leaf for this token and the listed fields is not in the root.
/// @param leaf The leaf `nameListing` computed.
/// @param root The root passed to `nameListing`.
error ListingProofInvalid(bytes32 leaf, bytes32 root);

/// Thrown when the listing signer binding is not one canonically encoded address.
/// @param value The bound value.
error ListingSignerBindingMalformed(bytes value);

/// Thrown when the signature over the root does not recover to the bound listing signer.
/// @param recovered The address the signature recovers to.
/// @param signer The bound listing signer.
error ListingSignerMismatch(address recovered, address signer);

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

/// Thrown when a vault's init metadata does not start with `STOX_ASSET_ID_METADATA_V1_TAG`.
/// @param tag The tag the metadata starts with, or zero when it is shorter than one word.
error UnknownAssetIdMetadata(bytes32 tag);

/// Thrown when a vault's init metadata is not the canonical `abi.encode(STOX_ASSET_ID_METADATA_V1_TAG, assetId)`.
error NonCanonicalAssetIdMetadata();

/// Thrown when a vault's init metadata carries an empty asset id.
error EmptyAssetId();

/// Thrown when the asset id is set a second time. It is write-once.
error AssetIdAlreadySet();

/// Thrown when `initializeAssetId` runs outside the vault's `initialize`.
error AssetIdNotInitializing();

/// Thrown when a vault is initialized with a non-empty name; the owner sets it with `setUnderlying`.
error NonEmptyInitialName();

/// Thrown when a vault is initialized with a non-empty symbol; the owner sets it with `setUnderlying`.
error NonEmptyInitialSymbol();

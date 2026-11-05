// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {UnknownAssetIdMetadata, NonCanonicalAssetIdMetadata, EmptyAssetId} from "../error/ErrAssetId.sol";

/// @dev ERC-7201 namespaced storage location for the asset id, derived
/// in-source from the spec formula rather than hardcoded.
bytes32 constant ASSET_ID_STORAGE_LOCATION =
    keccak256(abi.encode(uint256(keccak256("rain.storage.asset-id.1")) - 1)) & ~bytes32(uint256(0xff));

/// @dev Tags the vault init metadata that carries an asset id:
/// `abi.encode(STOX_ASSET_ID_METADATA_V1_TAG, string assetId)`.
bytes32 constant STOX_ASSET_ID_METADATA_V1_TAG = keccak256("st0x.metadata.asset-id.1");

/// @dev What `StoxCorporateActionsFacet.initializeAssetId` returns once it
/// has stored the asset id.
bytes32 constant ASSET_ID_INITIALIZED = keccak256("st0x.asset-id.initialized.1");

/// @title LibAssetId
/// @notice Storage and init metadata encoding for the asset id of a
/// `StoxReceiptVault` (see `IStoxAssetIdV1`).
library LibAssetId {
    /// @custom:storage-location erc7201:rain.storage.asset-id.1
    /// @dev **DO NOT REORDER — APPEND ONLY.** Field offsets at this ERC-7201 slot are positional.
    /// @param assetId The asset id, written once at `initialize`; empty on a vault initialized without one.
    struct AssetIdStorage {
        string assetId;
    }

    /// @notice Accessor for the asset id storage.
    /// @return Storage reference to the `AssetIdStorage` struct.
    function getStorage() internal pure returns (AssetIdStorage storage) {
        bytes32 position = ASSET_ID_STORAGE_LOCATION;
        AssetIdStorage storage s;
        assembly ("memory-safe") {
            s.slot := position
        }
        return s;
    }

    /// @notice The vault init metadata that carries `assetId`.
    /// @param assetId The asset id.
    /// @return The metadata.
    function encodeMetadata(string memory assetId) internal pure returns (bytes memory) {
        return abi.encode(STOX_ASSET_ID_METADATA_V1_TAG, assetId);
    }

    /// @notice The asset id in `encodeMetadata` form metadata; reverts on any other form or an empty id.
    /// @param metadata The metadata.
    /// @return The asset id.
    function decodeMetadata(bytes memory metadata) internal pure returns (string memory) {
        if (metadata.length < 0x20) revert UnknownAssetIdMetadata(bytes32(0));
        bytes32 tag = abi.decode(metadata, (bytes32));
        if (tag != STOX_ASSET_ID_METADATA_V1_TAG) revert UnknownAssetIdMetadata(tag);
        (, string memory assetId) = abi.decode(metadata, (bytes32, string));
        // `abi.decode` ignores trailing bytes and non-canonical offsets; the metadata is part of the address.
        if (keccak256(abi.encode(tag, assetId)) != keccak256(metadata)) revert NonCanonicalAssetIdMetadata();
        if (bytes(assetId).length == 0) revert EmptyAssetId();
        return assetId;
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

bytes32 constant STOX_TOKEN_CONFIG_V1_TAG = keccak256("StoxTokenConfigV1");

/// @dev Append only: init data and storage hold the ordinal.
enum AssetIdKind {
    ISIN
}

/// @dev Append only: init data and storage hold the ordinal.
enum Region {
    US,
    EU
}

struct AssetId {
    AssetIdKind kind;
    string id;
}

/// @param assetId The token's starting asset id.
/// @param listingTicker The ticker at listing, e.g. "MSTR".
/// @param listingName The issuer name at listing, without any ST0x suffix.
/// @param metadata Opaque: committed to by the address and emitted, never
/// stored or decoded.
struct StoxTokenConfigV1 {
    AssetId assetId;
    string listingTicker;
    string listingName;
    Region region;
    address authority;
    bytes32 rbacName;
    bytes32 receiptBeaconName;
    bytes metadata;
}

interface IStoxTokenConfigV1 {
    event StoxTokenInitialized(address indexed sender, StoxTokenConfigV1 config);

    /// @notice Reachable on every vault through its `fallback`; refuses once
    /// the vault is initialized.
    /// @return The rain-vats V3 init data derived from `data`.
    function initializeStoxToken(bytes calldata data) external returns (bytes memory);
}

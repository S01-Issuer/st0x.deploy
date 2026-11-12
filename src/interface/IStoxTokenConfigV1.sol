// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Region} from "../lib/LibProdTokenConfig.sol";

bytes32 constant STOX_TOKEN_CONFIG_V1_TAG = keccak256("StoxTokenConfigV1");

/// @param assetId The listing-time ISIN of the exact share line, or a
/// documented ST0X id where none exists. Never follows later changes.
/// @param listingTicker The ticker at listing, e.g. "MSTR".
/// @param listingName The issuer name at listing, without any ST0x suffix.
/// @param metadata Empty, or `abi.encode(bytes32 tag, payload)`.
struct StoxTokenConfigV1 {
    string assetId;
    string listingTicker;
    string listingName;
    Region region;
    address authority;
    bytes32 rbacName;
    bytes32 receiptBeaconName;
    bytes metadata;
}

interface IStoxTokenConfigV1 {
    event StoxTokenInitialized(address sender, StoxTokenConfigV1 config);

    function initializeStoxToken(bytes calldata data) external returns (bytes memory);
}

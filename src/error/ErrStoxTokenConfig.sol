// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

error InvalidStoxTokenConfigTag(bytes32 tag);

error NonCanonicalStoxTokenConfig();

error MalformedAssetId(string assetId);

error MalformedListingTicker(string listingTicker);

error MalformedListingName(string listingName);

error StoxTokenAlreadyInitialized();

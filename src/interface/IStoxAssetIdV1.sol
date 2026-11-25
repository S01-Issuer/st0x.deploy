// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

/// @dev Not proof that a token is genuine; only the pinned address is.
interface IStoxAssetIdV1 {
    /// @return The listing-time asset id from StoxTokenConfigV1, or "" for a vault initialized before it.
    function assetId() external view returns (string memory);
}

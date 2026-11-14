// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

/// @title IStoxAssetIdV1
/// @notice The listing-time identifier (e.g. ISIN) of the off-chain asset a ST0x token represents, set once at initialize.
/// @dev Not proof that a token is genuine: any vault can be deployed with a genuine token's init data. Only the pinned address is.
interface IStoxAssetIdV1 {
    /// @notice Emitted once, by the receipt vault, when it is initialized with its asset id.
    /// @param sender The caller of the vault's `initialize`.
    /// @param assetId The asset id.
    event AssetIdSet(address indexed sender, string assetId);

    /// @notice The asset id the token was initialized with.
    /// @return The asset id, or the empty string for a token initialized without one.
    function assetId() external view returns (string memory);
}

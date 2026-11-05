// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

/// @title IStoxAssetIdV1
/// @notice The fixed identifier of the off-chain asset a ST0x token
/// represents, for example the ISIN of the exact share line the token tracks.
///
/// The asset id is fixed at listing time. It is set once, when the vault is
/// initialized, and it never changes after that. It does not follow later ISIN
/// changes: a reverse split or a reorganization can reissue the ISIN, and the
/// token keeps its listing-time id. A V6 token's address commits to its asset
/// id, so the same asset id and region always give the same address.
///
/// `assetId()` and `AssetIdSet` are NOT proof that a token is genuine. Anyone
/// can deploy a vault through the open factory with a genuine token's init
/// data and another salt, and that vault reports the same asset id. Only the
/// pinned token address identifies the genuine token.
interface IStoxAssetIdV1 {
    /// @notice Emitted once, by the receipt vault, when it is initialized with
    /// its asset id. A wrapper never emits it: its `assetId()` passes its
    /// asset's through.
    /// @param sender The caller of the vault's `initialize`.
    /// @param assetId The asset id.
    event AssetIdSet(address indexed sender, string assetId);

    /// @notice The asset id the token was initialized with.
    /// @return The asset id, or the empty string for a token initialized
    /// before asset ids existed.
    function assetId() external view returns (string memory);
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

/// @title IStoxListingV1
/// @notice Anyone first-names an unnamed ST0x token from a listing: a Merkle root of (token, asset id, ticker, name)
/// leaves signed by the listing signer bound in the `ConfigRegistry`.
interface IStoxListingV1 {
    /// @notice Emitted when a token is first named from a listing.
    /// @param sender The caller.
    /// @param root The listing root that named it.
    event ListingNamed(address indexed sender, bytes32 indexed root);

    /// @notice Sets the underlying ticker and name of this unnamed token from a signed listing leaf, as `setUnderlying` does.
    /// @param listedAssetId The token's asset id, as in the leaf.
    /// @param newSymbol The underlying ticker, as in the leaf.
    /// @param newName The underlying name, as in the leaf.
    /// @param proof The leaf's Merkle proof.
    /// @param root The listing root.
    /// @param signature The listing signer's signature over the root's `LibListing.digest`.
    function nameListing(
        string calldata listedAssetId,
        string calldata newSymbol,
        string calldata newName,
        bytes32[] calldata proof,
        bytes32 root,
        bytes calldata signature
    ) external;
}

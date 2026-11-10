// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Hashes} from "@openzeppelin-contracts-5.7.0/utils/cryptography/Hashes.sol";
import {LibRainDeployRegistryBeaconProxy} from "rain-factory-0.2.11/src/lib/LibRainDeployRegistryBeaconProxy.sol";

import {TokenConfig} from "./LibProdTokenConfig.sol";
import {LibProdTokenParams} from "./LibProdTokenParams.sol";
import {LibListing} from "./LibListing.sol";
import {LibUnderlyingNamingRollout} from "./LibUnderlyingNamingRollout.sol";

/// One leaf of a listing: the token and the fields `nameListing` checks and writes.
struct ListingRow {
    address token;
    string assetId;
    string ticker;
    string name;
}

/// Thrown when a listing is built from no rows.
error ListingWithoutRows();

/// Thrown when a listing row has no asset id.
/// @param index The row's index.
error ListingRowWithoutAssetId(uint256 index);

/// Thrown when two listing rows name the same token.
/// @param token The token.
error ListingDuplicateToken(address token);

/// @title LibListingTree
/// @notice Builds a listing's Merkle tree off-chain exactly as OpenZeppelin `StandardMerkleTree.of(rows,
/// ["address","string","string","string"])` does: leaves sorted by hash, the same array layout, and the same proofs.
library LibListingTree {
    /// @notice One row per config: its V6 token address, asset id, ticker and underlying name.
    /// @param configs The rows of the token table.
    /// @return The listing rows, in the same order.
    function rows(TokenConfig[] memory configs) internal pure returns (ListingRow[] memory) {
        LibUnderlyingNamingRollout.assertRowsWellFormed(configs);
        ListingRow[] memory listed = new ListingRow[](configs.length);
        for (uint256 i = 0; i < configs.length; i++) {
            if (bytes(configs[i].assetId).length == 0) revert ListingRowWithoutAssetId(i);
            listed[i] = ListingRow({
                token: LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(
                    LibProdTokenParams.tokenParam(configs[i])
                ),
                assetId: configs[i].assetId,
                ticker: configs[i].underlying,
                name: configs[i].underlyingName
            });
        }
        return listed;
    }

    /// @notice The leaf of every row, in row order; reverts on no rows or a duplicate token.
    /// @param listed The rows.
    /// @return The leaves.
    function leaves(ListingRow[] memory listed) internal pure returns (bytes32[] memory) {
        if (listed.length == 0) revert ListingWithoutRows();
        bytes32[] memory hashes = new bytes32[](listed.length);
        for (uint256 i = 0; i < listed.length; i++) {
            for (uint256 j = 0; j < i; j++) {
                if (listed[j].token == listed[i].token) revert ListingDuplicateToken(listed[i].token);
            }
            hashes[i] = LibListing.leaf(listed[i].token, listed[i].assetId, listed[i].ticker, listed[i].name);
        }
        return hashes;
    }

    /// @notice The tree array of OpenZeppelin's `makeMerkleTree` over the sorted leaves: the root at index 0 and leaf
    /// `k` of the sorted order at `length - 1 - k`.
    /// @param listed The rows.
    /// @return The tree.
    function tree(ListingRow[] memory listed) internal pure returns (bytes32[] memory) {
        bytes32[] memory sorted = sortedLeaves(listed);
        bytes32[] memory nodes = new bytes32[](2 * sorted.length - 1);
        for (uint256 k = 0; k < sorted.length; k++) {
            nodes[nodes.length - 1 - k] = sorted[k];
        }
        for (uint256 i = nodes.length - sorted.length; i > 0; i--) {
            nodes[i - 1] = Hashes.commutativeKeccak256(nodes[2 * i - 1], nodes[2 * i]);
        }
        return nodes;
    }

    /// @notice The listing root.
    /// @param listed The rows.
    /// @return The root.
    function root(ListingRow[] memory listed) internal pure returns (bytes32) {
        return tree(listed)[0];
    }

    /// @notice The proof of row `index`, as OpenZeppelin's `getProof` returns it.
    /// @param listed The rows.
    /// @param index The row.
    /// @return The proof.
    function proof(ListingRow[] memory listed, uint256 index) internal pure returns (bytes32[] memory) {
        bytes32[] memory nodes = tree(listed);
        bytes32 target =
            LibListing.leaf(listed[index].token, listed[index].assetId, listed[index].ticker, listed[index].name);
        uint256 position = nodes.length;
        for (uint256 i = nodes.length - listed.length; i < nodes.length; i++) {
            if (nodes[i] == target) position = i;
        }
        uint256 depth = 0;
        for (uint256 i = position; i > 0; i = (i - 1) / 2) {
            depth++;
        }
        bytes32[] memory siblings = new bytes32[](depth);
        uint256 at = 0;
        for (uint256 i = position; i > 0; i = (i - 1) / 2) {
            siblings[at++] = nodes[i % 2 == 1 ? i + 1 : i - 1];
        }
        return siblings;
    }

    /// @notice The leaves sorted ascending, as `StandardMerkleTree.of` sorts them.
    /// @param listed The rows.
    /// @return The sorted leaves.
    function sortedLeaves(ListingRow[] memory listed) internal pure returns (bytes32[] memory) {
        bytes32[] memory sorted = leaves(listed);
        for (uint256 i = 1; i < sorted.length; i++) {
            bytes32 key = sorted[i];
            uint256 j = i;
            while (j > 0 && sorted[j - 1] > key) {
                sorted[j] = sorted[j - 1];
                j--;
            }
            sorted[j] = key;
        }
        return sorted;
    }
}

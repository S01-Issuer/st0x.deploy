// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {LibProdTokenConfig, TokenConfig} from "./LibProdTokenConfig.sol";
import {LibListingTree, ListingRow} from "./LibListingTree.sol";

/// @notice The rows of the V6 listing do not derive `ROOT`.
/// @param expected The frozen root.
/// @param actual The root the rows derive.
error V6ListingMoved(bytes32 expected, bytes32 actual);

/// @notice The table has fewer V6 rows than the listing names.
/// @param expected `ROW_COUNT`.
/// @param actual The number of V6 rows.
error V6ListingTableShort(uint256 expected, uint256 actual);

/// @title LibV6Listing
/// @notice The listing that first-names the leading `ROW_COUNT` production V6 tokens and the two test tokens on every
/// chain: the root the listing signer signs.
library LibV6Listing {
    /// @notice The listing root; frozen, since the listing signer signs it.
    bytes32 internal constant ROOT = 0x620bdcbe8ef7d32c36ec74daac5663c5cb5b4915f1882adb1a7f9bc85d2e0a6f;

    /// @notice How many leading production V6 rows the listing names; a row appended after them does not move it.
    uint256 internal constant ROW_COUNT = 59;

    /// @notice The leading `ROW_COUNT` production V6 rows, then the test tokens.
    /// @return The rows; reverts `V6ListingTableShort` when the table has fewer V6 rows.
    function configs() internal pure returns (TokenConfig[] memory) {
        return listedFrom(LibProdTokenConfig.v6TokenConfigs());
    }

    /// @notice The leading `ROW_COUNT` of `production`, then the test tokens.
    /// @param production The production V6 rows, in table order.
    /// @return The rows; reverts `V6ListingTableShort` when `production` has fewer than `ROW_COUNT`.
    function listedFrom(TokenConfig[] memory production) internal pure returns (TokenConfig[] memory) {
        if (production.length < ROW_COUNT) revert V6ListingTableShort(ROW_COUNT, production.length);
        TokenConfig[] memory test = LibProdTokenConfig.testTokenConfigs();
        TokenConfig[] memory listed = new TokenConfig[](ROW_COUNT + test.length);
        for (uint256 i = 0; i < ROW_COUNT; i++) {
            listed[i] = production[i];
        }
        for (uint256 i = 0; i < test.length; i++) {
            listed[ROW_COUNT + i] = test[i];
        }
        return listed;
    }

    /// @notice The listing rows of `listed`; reverts `V6ListingMoved` unless they derive `ROOT`.
    /// @param listed The rows, as `configs` returns them.
    /// @return The listing rows.
    function frozen(TokenConfig[] memory listed) internal pure returns (ListingRow[] memory) {
        ListingRow[] memory listedRows = LibListingTree.rows(listed);
        bytes32 root = LibListingTree.root(listedRows);
        if (root != ROOT) revert V6ListingMoved(ROOT, root);
        return listedRows;
    }

    /// @notice The listing rows of the table; reverts `V6ListingMoved` unless they derive `ROOT`.
    /// @return The listing rows.
    function rows() internal pure returns (ListingRow[] memory) {
        return frozen(configs());
    }
}

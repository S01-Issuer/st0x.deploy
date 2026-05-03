// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Float} from "rain.math.float/lib/LibDecimalFloat.sol";
import {
    ICorporateActionsV1,
    ACTION_TYPE_INIT_V1,
    ACTION_TYPE_STOCK_SPLIT_V1,
    BALANCE_MIGRATION_TYPES_MASK
} from "../interface/ICorporateActionsV1.sol";
import {CompletionFilter, NODE_NONE} from "./LibCorporateActionNode.sol";
import {LibStockSplit} from "./LibStockSplit.sol";
import {LibRebaseMath} from "./LibRebaseMath.sol";

/// @title LibReceiptRebase
/// @notice Walks the vault's stock split list from a per-`(holder, id)`
/// cursor forward, applying each completed split's multiplier sequentially
/// via the shared `LibRebaseMath.applyMultiplier` primitive, and returns
/// the rasterized receipt balance.
///
/// The key structural difference from `LibRebase` is the data source:
///
/// - `LibRebase` (share side) reads stock split nodes directly from the
///   vault's `LibCorporateAction.CorporateActionStorage.nodes` array,
///   because it runs under the vault's own delegatecall context.
/// - `LibReceiptRebase` (receipt side) runs on the receipt contract, which
///   is a **separate** contract at its own address. It reads nodes through
///   cross-contract view calls against `ICorporateActionsV1.nextOfType`
///   and `ICorporateActionsV1.getActionParameters` on the vault.
///
/// Walk semantics:
///   - Zero-balance accounts still advance the cursor through completed
///     splits. Required for fresh recipients: without it, a subsequent
///     write at a stale cursor would cause the next `balanceOf` read to
///     re-apply every completed multiplier to an already-rasterized
///     balance, inflating it.
///   - Non-zero balances apply each multiplier sequentially via
///     `LibRebaseMath.applyMultiplier`, matching the share-side
///     rasterization step exactly.
///   - If the walk visits no further completed splits the function is a
///     no-op and returns `(storedBalance, cursor)` unchanged.
///
/// **Cost note.** Each completed split visited costs two cross-contract
/// view calls (`nextOfType` + `getActionParameters`). Stock splits are
/// expected to be rare (O(10) over a contract's lifetime) so the
/// per-receipt-holder migration cost is bounded and acceptable.
library LibReceiptRebase {
    /// @notice Walk the vault's completed stock split list from `cursor`
    /// forward, returning the rebased balance and the advanced cursor.
    ///
    /// @param storedBalance The raw stored receipt balance for
    /// `(holder, id)`, read directly from OZ's ERC1155 storage.
    /// @param cursor The index of the last vault corporate-action node this
    /// `(holder, id)` pair was migrated through. The default 0 is the
    /// vault's bootstrap node — fresh `(holder, id)` pairs start there
    /// and the walk advances them through every subsequent completed
    /// stock split.
    /// @param vault The vault contract implementing `ICorporateActionsV1`.
    /// @return migratedBalance The balance after sequential multiplier
    /// application. Always 0 when `storedBalance == 0`.
    /// @return newCursor The index of the last completed stock split
    /// visited. Equals the input cursor if no further completed splits
    /// were found.
    function migratedBalance(uint256 storedBalance, uint256 cursor, ICorporateActionsV1 vault)
        internal
        view
        returns (uint256, uint256 newCursor)
    {
        newCursor = cursor;

        // Discard effectiveTime — only nextCursor and actionType are used
        // for the walk. The mask covers init and stock-split nodes;
        // effectiveTime is irrelevant here (the COMPLETED filter already
        // handled it on the vault side). actionType lets us skip the
        // float multiplier read for the identity init node.
        // slither-disable-next-line unused-return
        (uint256 nodeIndex, uint256 actionType,) =
            vault.nextOfType(cursor, BALANCE_MIGRATION_TYPES_MASK, CompletionFilter.COMPLETED);

        // Fast path: zero balance still advances the cursor through every
        // completed migration node without any multiplier math. Required for
        // fresh recipients of transfers: without it, a subsequent write
        // would land at a stale cursor and the next balanceOf read would
        // re-apply every completed multiplier to a post-rebase balance,
        // inflating it. See LibRebase.migratedBalance for the same
        // mechanism on the share side.
        if (storedBalance == 0) {
            while (nodeIndex != NODE_NONE) {
                newCursor = nodeIndex;
                // slither-disable-next-line unused-return
                (nodeIndex, actionType,) =
                    vault.nextOfType(nodeIndex, BALANCE_MIGRATION_TYPES_MASK, CompletionFilter.COMPLETED);
            }
            return (0, newCursor);
        }

        uint256 balance = storedBalance;

        while (nodeIndex != NODE_NONE) {
            newCursor = nodeIndex;
            // Init is identity — no multiplier, no balance change. Skip the
            // cross-contract `getActionParameters` call entirely; the
            // bootstrap node has empty parameters that would not decode as
            // a Float.
            if (actionType == ACTION_TYPE_STOCK_SPLIT_V1) {
                Float multiplier = LibStockSplit.decodeParametersV1(vault.getActionParameters(nodeIndex));
                balance = LibRebaseMath.applyMultiplier(balance, multiplier);
            }

            // slither-disable-next-line unused-return
            (nodeIndex, actionType,) =
                vault.nextOfType(nodeIndex, BALANCE_MIGRATION_TYPES_MASK, CompletionFilter.COMPLETED);
        }

        return (balance, newCursor);
    }
}

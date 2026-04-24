// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Float} from "rain.math.float/lib/LibDecimalFloat.sol";
import {ICorporateActionsV1} from "../interface/ICorporateActionsV1.sol";
import {CompletionFilter} from "./LibCorporateActionNode.sol";
import {ACTION_TYPE_STOCK_SPLIT_V1} from "./LibCorporateAction.sol";
import {LibStockSplit} from "./LibStockSplit.sol";
import {LibRebaseMath} from "./LibRebaseMath.sol";

/// @title LibReceiptRebase
/// @notice Receipt-side mirror of `LibRebase.migratedBalance`. Walks the
/// vault's stock split list from a per-`(holder, id)` cursor forward,
/// applying each completed split's multiplier sequentially via the shared
/// `LibRebaseMath.applyMultiplier` primitive.
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
/// The walk semantics are identical to `LibRebase.migratedBalance`:
///   - Zero-balance accounts still advance the cursor through completed
///     splits (load-bearing for fresh recipients — same reasoning as the
///     2026-04-07-01 cursor inflation regression on the share side).
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
    /// @param cursor The 1-based index of the last vault corporate-action
    /// node this `(holder, id)` pair was migrated through. 0 = start from
    /// the head of the list.
    /// @param vault The vault contract implementing `ICorporateActionsV1`.
    /// @return migratedBalance The balance after sequential multiplier
    /// application. Always 0 when `storedBalance == 0`.
    /// @return newCursor The 1-based index of the last completed stock
    /// split visited. Equals the input cursor if no further completed
    /// splits were found.
    function migratedBalance(uint256 storedBalance, uint256 cursor, ICorporateActionsV1 vault)
        internal
        view
        returns (uint256, uint256 newCursor)
    {
        newCursor = cursor;

        (uint256 nodeIndex,,) = vault.nextOfType(cursor, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);

        // Fast path: zero balance still advances the cursor through
        // completed splits without any multiplier math. Required for fresh
        // recipients of transfers: without it, a subsequent write would
        // land at a stale cursor and the next balanceOf read would re-apply
        // every completed multiplier to a post-rebase balance, inflating
        // it. See LibRebase.migratedBalance for the same mechanism on the
        // share side.
        if (storedBalance == 0) {
            while (nodeIndex != 0) {
                newCursor = nodeIndex;
                (nodeIndex,,) = vault.nextOfType(nodeIndex, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
            }
            return (0, newCursor);
        }

        uint256 balance = storedBalance;

        while (nodeIndex != 0) {
            newCursor = nodeIndex;
            Float multiplier = LibStockSplit.decodeParametersV1(vault.getActionParameters(nodeIndex));
            balance = LibRebaseMath.applyMultiplier(balance, multiplier);

            (nodeIndex,,) = vault.nextOfType(nodeIndex, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
        }

        return (balance, newCursor);
    }
}

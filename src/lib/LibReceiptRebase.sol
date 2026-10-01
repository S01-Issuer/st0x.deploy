// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Float} from "rain-math-float-0.2.4/src/lib/LibDecimalFloat.sol";
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
/// The data source differs from `LibRebase`:
///
/// - `LibRebase` (share side) reads stock split nodes directly from the
///   vault's `LibCorporateAction.CorporateActionStorage.nodes` array,
///   under the vault's own delegatecall context.
/// - `LibReceiptRebase` (receipt side) runs on the receipt contract, a
///   separate contract at its own address. It reads nodes through
///   cross-contract view calls against `ICorporateActionsV1.nextOfType`
///   and `ICorporateActionsV1.getActionParameters` on the vault.
///
/// Walk semantics:
///   - Zero-balance accounts still advance the cursor through completed
///     splits, so a later write for a fresh recipient lands at the current
///     cursor rather than a stale one.
///   - Non-zero balances apply each multiplier sequentially via
///     `LibRebaseMath.applyMultiplier`, matching the share-side
///     rasterization step exactly.
///   - If the walk visits no further completed splits the function
///     returns `(storedBalance, cursor)` unchanged.
///
/// Each completed split visited costs two cross-contract view calls
/// (`nextOfType` + `getActionParameters`).
///
/// The walk has no defence against a vault implementation serving
/// inconsistent answers across `nextOfType` / `getActionParameters`
/// iterations; the receipt trusts whatever implementation the vault beacon's
/// owner installs behind its manager pointer.
library LibReceiptRebase {
    /// @notice Walk the vault's completed stock split list from
    /// `fromActionId` forward, returning the rebased balance and the
    /// advanced action id.
    ///
    /// @param storedBalance The raw stored receipt balance for
    /// `(holder, id)`, read directly from OZ's ERC1155 storage.
    /// @param fromActionId The action id of the last vault corporate-action
    /// node this `(holder, id)` pair was migrated through. The default 0
    /// is the vault's bootstrap node — fresh `(holder, id)` pairs start
    /// there and the walk advances them through every subsequent
    /// completed stock split.
    /// @param vault The vault contract implementing `ICorporateActionsV1`.
    /// @return migratedBalance The balance after sequential multiplier
    /// application. Always 0 when `storedBalance == 0`.
    /// @return toActionId The action id of the last completed stock split
    /// visited. Equals `fromActionId` if no further completed splits were
    /// found.
    function migratedBalance(uint256 storedBalance, uint256 fromActionId, ICorporateActionsV1 vault)
        internal
        view
        returns (uint256, uint256)
    {
        uint256 toActionId = fromActionId;

        // effectiveTime is discarded: the COMPLETED filter already applied it
        // on the vault side. actionType skips the float multiplier read for
        // the identity init node.
        // slither-disable-next-line unused-return
        (uint256 nodeIndex, uint256 actionType,) =
            vault.nextOfType(fromActionId, BALANCE_MIGRATION_TYPES_MASK, CompletionFilter.COMPLETED);

        // Fast path: zero balance still advances the cursor through every
        // completed migration node without any multiplier math. See
        // LibRebase.migratedBalance for the share side.
        if (storedBalance == 0) {
            while (nodeIndex != NODE_NONE) {
                toActionId = nodeIndex;
                // slither-disable-next-line unused-return
                (nodeIndex, actionType,) =
                    vault.nextOfType(nodeIndex, BALANCE_MIGRATION_TYPES_MASK, CompletionFilter.COMPLETED);
            }
            return (0, toActionId);
        }

        uint256 balance = storedBalance;

        while (nodeIndex != NODE_NONE) {
            toActionId = nodeIndex;
            // Init is identity: no multiplier, no balance change, and no
            // `getActionParameters` call; the bootstrap node's parameters are
            // empty and would not decode as a Float.
            if (actionType == ACTION_TYPE_STOCK_SPLIT_V1) {
                Float multiplier = LibStockSplit.decodeParametersV1(vault.getActionParameters(nodeIndex));
                balance = LibRebaseMath.applyMultiplier(balance, multiplier);
            }

            // slither-disable-next-line unused-return
            (nodeIndex, actionType,) =
                vault.nextOfType(nodeIndex, BALANCE_MIGRATION_TYPES_MASK, CompletionFilter.COMPLETED);
        }

        return (balance, toActionId);
    }
}

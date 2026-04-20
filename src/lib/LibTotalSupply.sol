// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float} from "rain.math.float/lib/LibDecimalFloat.sol";
import {LibCorporateAction, ACTION_TYPE_STOCK_SPLIT_V1} from "./LibCorporateAction.sol";
import {CompletionFilter, LibCorporateActionNode} from "./LibCorporateActionNode.sol";
import {LibStockSplit} from "./LibStockSplit.sol";
import {LibERC20Storage} from "./LibERC20Storage.sol";
import {LibRebaseMath} from "./LibRebaseMath.sol";

/// @title LibTotalSupply
/// @notice Tracks totalSupply accurately through lazy account migration using
/// per-cursor pots.
///
/// ## Problem
///
/// When a stock split completes, the correct totalSupply is the sum of every
/// account's individually-rasterized balance. But lazily migrated accounts
/// haven't been rasterized yet, so we can't compute that sum directly.
///
/// Applying the multiplier to the aggregate sum overestimates because
/// `trunc(sum * m) >= sum(trunc(ai * m))`. A single unmigrated/migrated
/// pair cannot improve precision through migration: subtracting and adding
/// the same value leaves the sum unchanged.
///
/// ## Solution: per-cursor pots
///
/// Instead of one aggregate unmigrated number, we maintain a separate
/// unmigrated sum for each cursor position (migration epoch). Each pot tracks
/// the sum of stored balances for accounts at that cursor level.
///
///   `unmigrated[k]` = sum of stored balances for accounts whose migration
///   cursor is `k`.
///
/// totalSupply is computed by walking completed splits and accumulating:
///
///   running = unmigrated[0]
///   for each completed split at position p with multiplier m:
///     running = trunc(running * m) + unmigrated[p]
///   totalSupply = running
///
/// ## Migration
///
/// When an account migrates from cursor k to cursor k':
///   unmigrated[k] -= storedBalance
///   unmigrated[k'] += migratedBalance
///
/// This genuinely improves precision: subtracting a raw balance from a
/// pre-multiplier pot and adding the individually-rasterized balance to a
/// post-multiplier pot replaces an aggregate estimate with an exact value.
///
/// ## Convergence
///
/// When all accounts have migrated through all completed splits,
/// `unmigrated[0..latest-1]` are all zero and `unmigrated[latest]` equals the
/// exact sum of all rasterized balances. The overestimate fully resolves.
///
/// ## No folding required
///
/// Unlike the two-bucket approach, pots do not need to be folded when a new
/// split completes. The view function automatically picks up new multipliers.
/// `fold()` only bootstraps `unmigrated[0]` from OZ on first use and tracks
/// the latest completed split for mint/burn assignment.
library LibTotalSupply {
    /// @notice Compute the effective totalSupply without state changes.
    /// Walks all completed splits, accumulating per-pot contributions with
    /// sequential rasterization between each multiplier.
    /// @return supply The effective total supply.
    function effectiveTotalSupply() internal view returns (uint256 supply) {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();

        // No splits ever scheduled — use OZ fallback.
        if (s.nodes.length == 0) {
            return LibERC20Storage.getTotalSupply();
        }

        // Start with the bootstrap pot.
        uint256 running;
        if (s.totalSupplyBootstrapped) {
            running = s.unmigrated[0];
        } else {
            uint256 firstIndex =
                LibCorporateActionNode.nextOfType(0, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
            if (firstIndex == 0) {
                return LibERC20Storage.getTotalSupply();
            }
            running = LibERC20Storage.getTotalSupply();
        }

        // Walk completed splits, applying each multiplier and picking up pots.
        uint256 nodeIndex = LibCorporateActionNode.nextOfType(0, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);

        while (nodeIndex != 0) {
            Float multiplier = LibStockSplit.decodeParametersV1(s.nodes[nodeIndex].parameters);
            // Rasterize via the shared rebase primitive so every step of
            // the totalSupply walk uses the same rounding characteristics
            // as per-account migration. See `LibRebaseMath.applyMultiplier`.
            running = LibRebaseMath.applyMultiplier(running, multiplier);
            running += s.unmigrated[nodeIndex];

            nodeIndex =
                LibCorporateActionNode.nextOfType(nodeIndex, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
        }

        return running;
    }

    /// @notice Bootstrap totalSupply tracking and update the latest split
    /// cursor. Must be called in `_update` before any account migrations.
    function fold() internal {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();

        // No splits ever scheduled — nothing to do.
        if (s.nodes.length == 0) return;

        // Bootstrap from OZ's totalSupply on first completed split.
        if (!s.totalSupplyBootstrapped) {
            uint256 firstIndex =
                LibCorporateActionNode.nextOfType(0, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
            if (firstIndex == 0) return;

            s.unmigrated[0] = LibERC20Storage.getTotalSupply();
            s.totalSupplyBootstrapped = true;
        }

        // Walk from the last known split to find newly completed ones.
        uint256 nodeIndex = LibCorporateActionNode.nextOfType(
            s.totalSupplyLatestSplit, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED
        );

        while (nodeIndex != 0) {
            s.totalSupplyLatestSplit = nodeIndex;
            nodeIndex =
                LibCorporateActionNode.nextOfType(nodeIndex, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
        }
    }

    /// @notice Update tracking when an account is migrated.
    /// @param fromCursor The account's cursor before migration.
    /// @param storedBalance The account's stored balance before migration.
    /// @param toCursor The account's cursor after migration.
    /// @param newBalance The account's rasterized balance after migration.
    function onAccountMigrated(uint256 fromCursor, uint256 storedBalance, uint256 toCursor, uint256 newBalance)
        internal
    {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        s.unmigrated[fromCursor] -= storedBalance;
        s.unmigrated[toCursor] += newBalance;
    }

    /// @notice Update tracking for a mint (adds to the latest cursor pot).
    /// @param amount The minted amount.
    function onMint(uint256 amount) internal {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        if (s.totalSupplyBootstrapped) {
            s.unmigrated[s.totalSupplyLatestSplit] += amount;
        }
    }

    /// @notice Update tracking for a burn (subtracts from the latest cursor pot).
    /// @param amount The burned amount.
    function onBurn(uint256 amount) internal {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        if (s.totalSupplyBootstrapped) {
            s.unmigrated[s.totalSupplyLatestSplit] -= amount;
        }
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
import {LibCorporateAction, CorporateActionNode, ACTION_TYPE_STOCK_SPLIT} from "./LibCorporateAction.sol";
import {LibStockSplit} from "./LibStockSplit.sol";
import {LibERC20Storage} from "./LibERC20Storage.sol";

using LibCorporateAction for uint256;

/// @title LibTotalSupply
/// @notice Tracks totalSupply accurately through lazy account migration.
///
/// ## Problem
///
/// When a stock split completes, the correct totalSupply is the sum of every
/// account's individually-rasterized balance. But lazily migrated accounts
/// haven't been rasterized yet, so we can't compute that sum directly.
///
/// ## Solution: unmigrated/migrated offset
///
/// Two values partition totalSupply:
///
/// - `totalUnmigrated` — the aggregate supply with multipliers applied eagerly
///   to the sum. This is an overestimate because `trunc(sum * m)` >=
///   `sum(trunc(ai * m))` — per-account truncation rounds each term down
///   independently. The worst-case overestimate is bounded by the number of
///   unmigrated accounts (one wei of rounding per account per split).
///
/// - `totalMigrated` — the sum of exact rasterized balances for accounts that
///   have already been migrated. Each migration replaces an estimated
///   contribution in `totalUnmigrated` with an exact one in `totalMigrated`.
///
/// `totalSupply() = totalUnmigrated + totalMigrated`
///
/// ## Folding on new splits
///
/// When a new split (multiplier `m`) completes, ALL accounts are unmigrated
/// relative to that split — including those previously migrated. So we fold:
///
///   `totalUnmigrated = (totalUnmigrated + totalMigrated) * m`
///   `totalMigrated = 0`
///
/// ## Convergence
///
/// As accounts migrate, the overestimate shrinks monotonically. When all
/// accounts have migrated through all completed splits, `totalUnmigrated = 0`
/// and `totalMigrated` equals the exact sum of all balances.
library LibTotalSupply {
    /// @notice Compute the effective totalSupply without state changes.
    /// Virtually applies any pending multipliers by folding.
    /// @return supply The effective total supply.
    function effectiveTotalSupply() internal view returns (uint256 supply) {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        uint256 unmigrated = s.totalUnmigrated;
        uint256 migrated = s.totalMigrated;
        uint256 cursor = s.totalSupplyCursor;

        // Check if there are pending completed splits after the cursor.
        uint256 nextSplit = cursor.nextCompletedOfType(ACTION_TYPE_STOCK_SPLIT);

        // No pending completed splits — use stored values or OZ fallback.
        if (nextSplit == 0) {
            if (cursor == 0) return LibERC20Storage.getTotalSupply();
            return unmigrated + migrated;
        }

        // Bootstrap from OZ's totalSupply if no fold has happened yet.
        if (cursor == 0 && unmigrated == 0 && migrated == 0) {
            unmigrated = LibERC20Storage.getTotalSupply();
        }

        // Virtually fold pending multipliers. Rasterize to uint256 after
        // each multiplier to match what storage writes would produce.
        uint256 total = unmigrated + migrated;
        uint256 current = nextSplit;

        while (current != 0) {
            CorporateActionNode storage node = LibCorporateAction.getStorage().nodes[current];
            Float multiplier = LibStockSplit.decodeParameters(node.parameters);
            // forge-lint: disable-next-line(unsafe-typecast)
            (total,) = LibDecimalFloat.toFixedDecimalLossy(
                LibDecimalFloat.mul(LibDecimalFloat.packLossless(int256(total), 0), multiplier), 0
            );

            current = current.nextCompletedOfType(ACTION_TYPE_STOCK_SPLIT);
        }

        return total;
    }

    /// @notice Eagerly fold totalSupply for newly completed splits. Must be
    /// called in `_update` before any account migrations.
    function fold() internal {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        uint256 cursor = s.totalSupplyCursor;

        uint256 nextSplit = cursor.nextCompletedOfType(ACTION_TYPE_STOCK_SPLIT);
        if (nextSplit == 0) return;

        // Bootstrap: first fold reads OZ's totalSupply as the starting value.
        uint256 total;
        if (cursor == 0 && s.totalUnmigrated == 0 && s.totalMigrated == 0) {
            total = LibERC20Storage.getTotalSupply();
        } else {
            total = s.totalUnmigrated + s.totalMigrated;
        }

        // Rasterize to uint256 after each multiplier to match what storage
        // writes would produce between each split.
        uint256 current = nextSplit;
        uint256 lastSplit = cursor;

        while (current != 0) {
            CorporateActionNode storage node = LibCorporateAction.getStorage().nodes[current];
            Float multiplier = LibStockSplit.decodeParameters(node.parameters);
            // forge-lint: disable-next-line(unsafe-typecast)
            (total,) = LibDecimalFloat.toFixedDecimalLossy(
                LibDecimalFloat.mul(LibDecimalFloat.packLossless(int256(total), 0), multiplier), 0
            );
            lastSplit = current;

            current = current.nextCompletedOfType(ACTION_TYPE_STOCK_SPLIT);
        }

        s.totalUnmigrated = total;
        s.totalMigrated = 0;
        s.totalSupplyCursor = lastSplit;
    }

    /// @notice Update tracking when an account is migrated.
    /// @param effectiveBalance The account's rasterized balance.
    function onAccountMigrated(uint256 effectiveBalance) internal {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        s.totalUnmigrated -= effectiveBalance;
        s.totalMigrated += effectiveBalance;
    }

    /// @notice Update tracking for a mint (totalMigrated increases).
    /// @param amount The minted amount.
    function onMint(uint256 amount) internal {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        if (s.totalSupplyCursor != 0) {
            s.totalMigrated += amount;
        }
    }

    /// @notice Update tracking for a burn (totalMigrated decreases).
    /// @param amount The burned amount.
    function onBurn(uint256 amount) internal {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        if (s.totalSupplyCursor != 0) {
            s.totalMigrated -= amount;
        }
    }
}

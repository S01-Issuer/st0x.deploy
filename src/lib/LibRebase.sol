// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Float} from "rain.math.float/lib/LibDecimalFloat.sol";
import {LibCorporateAction} from "./LibCorporateAction.sol";
import {
    ACTION_TYPE_INIT_V1,
    ACTION_TYPE_STOCK_SPLIT_V1,
    BALANCE_MIGRATION_TYPES_MASK
} from "../interface/ICorporateActionsV1.sol";
import {CompletionFilter, LibCorporateActionNode, NODE_NONE} from "./LibCorporateActionNode.sol";
import {LibRebaseMath} from "./LibRebaseMath.sol";
import {LibStockSplit} from "./LibStockSplit.sol";

/// @title LibRebase
/// @notice Walks the corporate action linked list to apply stock split
/// multipliers sequentially. Multipliers are read directly from completed
/// nodes filtered by ACTION_TYPE_STOCK_SPLIT_V1.
///
/// ## Sequential precision
///
/// Multipliers are NEVER collapsed into a cumulative product. Each
/// multiplier is rasterized to uint256 (via `toFixedDecimalLossy`, which
/// truncates toward zero) before the next multiplier is applied, matching
/// the result an account would get if it had been written to storage
/// between every split. This guarantees that a dormant account (migrated
/// all at once on first touch) and an active account (migrated step by
/// step as each split lands) converge to the **same** balance.
///
/// Worked example — applying the sequence `1/3, 3, 1/3, 3` to a stored
/// balance of 100. Two things compound here: (a) Solidity integer
/// truncation at each `toFixedDecimalLossy` step, and (b) Rain Float's
/// finite-precision representation of 1/3, which is slightly **less**
/// than exact 1/3 (e.g. `0.333…3` with a finite number of digits, not
/// a repeating decimal). The second point matters in the third step
/// below: `99 × 1/3_float` lands just under exact 33, not at exact 33:
///
/// ```
/// start:         100
/// × 1/3:         100 × 1/3_float ≈ 33.333…    → trunc → 33
/// × 3:            33 × 3          = 99         (exact)
/// × 1/3:          99 × 1/3_float ≈ 32.999…    → trunc → 32
/// × 3:            32 × 3          = 96         (exact)
/// ```
///
/// Final balance: **96**, not 100 and not 99. The collapsed-product
/// answer would be `1/3 × 3 × 1/3 × 3 = 1`, giving 100 exactly —
/// different from the sequential result. The difference isn't a bug:
/// we must preserve the sequential result so that two accounts
/// migrating through the same node list at different times arrive at
/// identical values, otherwise dormant-account balances would drift
/// relative to active-account balances and the core rebase invariant
/// would break.
///
/// The `testSequentialPrecision` regression test
/// (`test/src/lib/LibRebase.t.sol`) locks this exact input → 96
/// relationship in place. Any change to Rain Float's precision
/// characteristics will surface there first.
library LibRebase {
    /// @notice Calculate the migrated balance by walking completed stock split
    /// nodes from a cursor, applying each multiplier sequentially.
    ///
    /// Cursor advancement is performed even when `storedBalance == 0`. Without
    /// it, a fresh recipient of a mint or transfer-in would have its cursor
    /// stuck at zero: a subsequent stored-balance write (via `super._update`
    /// in the vault) would land at a stale cursor and the next read of
    /// `balanceOf` would re-apply every completed multiplier to a balance
    /// already written at the post-rebase basis — over-multiplying and
    /// silently inflating the recipient's balance.
    /// Regression tests: `testZeroBalanceAdvancesCursor*` in
    /// `test/src/lib/LibRebase.t.sol`, and the fresh-recipient regression
    /// tests in `test/src/concrete/StoxReceiptVault.t.sol`.
    ///
    /// @param storedBalance The account's raw stored balance.
    /// @param cursor The index of the last node this account was migrated
    /// through. The default 0 is the bootstrap node — fresh holders start
    /// at the bootstrap, and the walk advances them through every
    /// subsequent completed split.
    /// @return migratedBalance The balance after sequential multiplier
    /// application. Always 0 when `storedBalance == 0`.
    /// @return newCursor The index of the last completed split node visited.
    /// Equals the input cursor if there were no further completed splits.
    function migratedBalance(uint256 storedBalance, uint256 cursor) internal view returns (uint256, uint256 newCursor) {
        newCursor = cursor;

        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();

        uint256 balance = storedBalance;
        uint256 nodeIndex =
            LibCorporateActionNode.nextOfType(cursor, BALANCE_MIGRATION_TYPES_MASK, CompletionFilter.COMPLETED);

        while (nodeIndex != NODE_NONE) {
            newCursor = nodeIndex;
            // Skip the multiplier read and float math whenever the balance
            // is already zero. This covers both dormant zero-balance accounts
            // (never held / fully burned) and mid-iteration truncation to
            // zero (e.g. `balance=1, multiplier=0.5` → 0 after one step),
            // because every subsequent `trunc(0 × multiplier) = 0`. The
            // cursor still advances on every pass — skipping the advancement
            // would inflate fresh recipients' balances on their next write;
            // see the function NatSpec for the mechanism.
            //
            // Init nodes (`ACTION_TYPE_INIT_V1`) are also identity — the
            // bootstrap step exists so every holder's cursor advances
            // through index 0 once, replacing the special "before any
            // action" state. No multiplier read, no float math.
            if (balance != 0 && s.nodes[nodeIndex].actionType == ACTION_TYPE_STOCK_SPLIT_V1) {
                Float multiplier = LibStockSplit.decodeParametersV1(s.nodes[nodeIndex].parameters);
                // Rasterize after each multiplier to match what storage
                // writes would produce. This ensures dormant and active
                // accounts converge to identical balances.
                // `LibRebaseMath.applyMultiplier` is the shared primitive
                // used by every rebase path in the codebase (share side,
                // totalSupply, receipt side) — see `LibRebaseMath.sol` for
                // the safety argument on the int256 cast.
                balance = LibRebaseMath.applyMultiplier(balance, multiplier);
            }

            nodeIndex =
                LibCorporateActionNode.nextOfType(nodeIndex, BALANCE_MIGRATION_TYPES_MASK, CompletionFilter.COMPLETED);
        }

        return (balance, newCursor);
    }
}

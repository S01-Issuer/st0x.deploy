// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
import {LibCorporateAction, ACTION_TYPE_STOCK_SPLIT} from "./LibCorporateAction.sol";
import {CompletionFilter, LibCorporateActionNode} from "./LibCorporateActionNode.sol";
import {LibStockSplit} from "./LibStockSplit.sol";

/// @title LibRebase
/// @notice Walks the corporate action linked list to apply stock split
/// multipliers sequentially. Multipliers are read directly from completed
/// nodes filtered by ACTION_TYPE_STOCK_SPLIT.
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
///
/// See `audit/2026-04-09-01` Item 7.
library LibRebase {
    /// @notice Calculate the migrated balance by walking completed stock split
    /// nodes from a cursor, applying each multiplier sequentially.
    ///
    /// Cursor advancement is performed even when `storedBalance == 0`. This is
    /// load-bearing for fresh recipients of mints and transfers: if the cursor
    /// did not advance for a zero-balance account, a subsequent stored-balance
    /// write (via `super._update` in the vault) would land at a stale cursor
    /// and the next read of `balanceOf` would re-apply every completed
    /// multiplier to a balance that was already written at the post-rebase
    /// basis — over-multiplying and silently inflating the recipient's balance.
    /// See `audit/2026-04-07-01/pass1/StoxReceiptVault.md::A03-1` and
    /// `pass1/LibRebase.md::A26-1` for the full reproduction.
    ///
    /// @param storedBalance The account's raw stored balance.
    /// @param cursor The index of the last node this account was migrated
    /// through. Use 0 to start from the head.
    /// @return migratedBalance The balance after sequential multiplier
    /// application. Always 0 when `storedBalance == 0`.
    /// @return newCursor The index of the last completed split node visited.
    /// Equals the input cursor if there were no further completed splits.
    function migratedBalance(uint256 storedBalance, uint256 cursor) internal view returns (uint256, uint256 newCursor) {
        newCursor = cursor;

        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();

        uint256 nodeIndex =
            LibCorporateActionNode.nextOfType(cursor, ACTION_TYPE_STOCK_SPLIT, CompletionFilter.COMPLETED);

        // Fast path: zero balance still advances the cursor through completed
        // splits without doing any multiplier math.
        if (storedBalance == 0) {
            while (nodeIndex != 0) {
                newCursor = nodeIndex;
                nodeIndex =
                    LibCorporateActionNode.nextOfType(nodeIndex, ACTION_TYPE_STOCK_SPLIT, CompletionFilter.COMPLETED);
            }
            return (0, newCursor);
        }

        uint256 balance = storedBalance;
        bool modified = false;

        while (nodeIndex != 0) {
            newCursor = nodeIndex;
            Float multiplier = LibStockSplit.decodeParameters(s.nodes[nodeIndex].parameters);
            // Rasterize after each multiplier to match what storage writes
            // would produce. This ensures dormant and active accounts
            // converge to identical balances. The `int256(balance)` cast is
            // safe because realistic ERC20 balances are well below 2^255.
            (balance,) = LibDecimalFloat.toFixedDecimalLossy(
                // forge-lint: disable-next-line(unsafe-typecast)
                LibDecimalFloat.mul(LibDecimalFloat.packLossless(int256(balance), 0), multiplier),
                0
            );
            modified = true;

            nodeIndex =
                LibCorporateActionNode.nextOfType(nodeIndex, ACTION_TYPE_STOCK_SPLIT, CompletionFilter.COMPLETED);
        }

        if (!modified) {
            return (storedBalance, cursor);
        }

        return (balance, newCursor);
    }
}

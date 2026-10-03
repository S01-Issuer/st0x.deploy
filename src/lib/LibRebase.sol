// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Float} from "rain-math-float-0.2.4/src/lib/LibDecimalFloat.sol";
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
/// answer would be `1/3 × 3 × 1/3 × 3 = 1`, giving 100 exactly. Two
/// accounts migrating through the same node list at different times
/// arrive at identical values.
library LibRebase {
    /// @notice Calculate the migrated balance by walking completed stock split
    /// nodes from a cursor, applying each multiplier sequentially.
    ///
    /// The cursor advances even when `storedBalance == 0`, so a later
    /// stored-balance write for a fresh recipient lands at the current
    /// cursor rather than a stale one that would re-apply every completed
    /// multiplier on the next `balanceOf` read.
    ///
    /// @param storedBalance The account's raw stored balance.
    /// @param fromActionId The action id of the last node this account was
    /// migrated through. The default 0 is the bootstrap node — fresh
    /// holders start at the bootstrap, and the walk advances them through
    /// every subsequent completed split.
    /// @return migratedBalance The balance after sequential multiplier
    /// application. Always 0 when `storedBalance == 0`.
    /// @return toActionId The action id of the last completed split node
    /// visited. Equals `fromActionId` if there were no further completed
    /// splits.
    function migratedBalance(uint256 storedBalance, uint256 fromActionId) internal view returns (uint256, uint256) {
        uint256 toActionId = fromActionId;

        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();

        uint256 balance = storedBalance;
        uint256 nodeIndex =
            LibCorporateActionNode.nextOfType(fromActionId, BALANCE_MIGRATION_TYPES_MASK, CompletionFilter.COMPLETED);

        while (nodeIndex != NODE_NONE) {
            toActionId = nodeIndex;
            // Skip the multiplier read and float math whenever the balance
            // is already zero, whether dormant or truncated to zero
            // mid-walk (e.g. `balance=1, multiplier=0.5` → 0), since every
            // subsequent `trunc(0 × multiplier) = 0`. The cursor still
            // advances on every pass.
            //
            // Init nodes (`ACTION_TYPE_INIT_V1`) are identity: no multiplier
            // read, no float math.
            if (balance != 0 && s.nodes[nodeIndex].actionType == ACTION_TYPE_STOCK_SPLIT_V1) {
                Float multiplier = LibStockSplit.decodeParametersV1(s.nodes[nodeIndex].parameters);
                // Rasterize after each multiplier to match what storage
                // writes would produce, so dormant and active accounts
                // converge to identical balances.
                balance = LibRebaseMath.applyMultiplier(balance, multiplier);
            }

            nodeIndex =
                LibCorporateActionNode.nextOfType(nodeIndex, BALANCE_MIGRATION_TYPES_MASK, CompletionFilter.COMPLETED);
        }

        return (balance, toActionId);
    }
}

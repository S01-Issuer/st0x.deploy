// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Float} from "rain.math.float/lib/LibDecimalFloat.sol";
import {LibCorporateAction} from "./LibCorporateAction.sol";
import {
    ACTION_TYPE_INIT_V1, ACTION_TYPE_STOCK_SPLIT_V1, BALANCE_MIGRATION_TYPES_MASK
} from "../interface/ICorporateActionsV1.sol";
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
/// totalSupply is computed by walking the init/bootstrap node and every
/// completed split, accumulating:
///
///   running = unmigrated[0]
///   for each completed init-or-split node at position p with multiplier m:
///     running = trunc(running * m) + unmigrated[p]   (m = 1 for the init node)
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
/// When all accounts have migrated through every completed split,
/// `unmigrated[0..latest-1]` are all zero and `unmigrated[latest]` equals the
/// exact sum of all rasterized balances. The overestimate fully resolves.
///
/// ## Pots are not consolidated
///
/// Unlike the two-bucket approach, pots are never merged or consolidated as
/// new splits complete. The view walks all completed migration pots at read
/// time and automatically picks up new multipliers.
///
/// ## Bootstrap as a real init node
///
/// The pre-action snapshot of OZ's `_totalSupply` lives in `unmigrated[0]`,
/// captured by `LibCorporateAction._ensureBootstrap` on the first
/// `schedule()` call. The bootstrap simultaneously pushes the index-1 init
/// node (`actionType = ACTION_TYPE_INIT_V1`, `effectiveTime =
/// block.timestamp`) so the migration walk has a real first step rather
/// than a magic invisible slot. The init step is identity for stock-split
/// migrations, which means every holder's cursor advances `0 → 1 → ...`
/// uniformly through the list — there is no special-cased "before any
/// action" state and the disambiguation between "cursor at index 0" and
/// "cursor not yet set" disappears: every holder starts at the pre-init
/// cursor 0 and migration is simply walking the chronological list.
///
/// `fold()` advances `totalSupplyLatestCursor` through both the init node
/// and every completed split using `BALANCE_MIGRATION_TYPES_MASK`, so
/// mint/burn deltas always route to the same pot every account's
/// `_migrateAccount` lands them in.
///
/// ## Pot invariant
///
/// At every `_update` boundary (post-`_ensureBootstrap`), for every cursor `k`:
///
///   `I(k): unmigrated[k] == Σ_{acc : cursor(acc) == k, acc != address(0)} underlyingBalance(acc)`
///
/// i.e. each pot holds the exact sum of raw stored balances for accounts
/// sitting at that cursor. The invariant is what makes:
///   - `effectiveTotalSupply`'s per-pot walk correct (it's the sum of all
///     holders' post-migration balances),
///   - `onAccountMigrated`'s checked subtraction safe (the pot being
///     decremented always contains at least the summand being removed),
///   - `onBurn`'s checked subtraction safe (same reasoning, but against OZ's
///     own sufficient-balance guard).
///
/// ### Proof of preservation
///
/// **Base case** (immediately after `_ensureBootstrap` runs in the first
/// `schedule()`):
/// - Every account has `cursor == 0` because no `_update` has fired yet.
/// - `unmigrated[0] := underlyingTotalSupply() == Σ_acc underlyingBalance(acc)`
///   by OZ's own invariant (`_totalSupply` equals the sum of `_balances`).
/// - So `unmigrated[0] == Σ_{cursor==0} underlyingBalance(acc)`. I(0) holds.
/// - For `k > 0`, no account has cursor `k` and `unmigrated[k] == 0`. I(k) holds.
///
/// **Inductive step.** Assume `I(k)` holds for all `k` on entry to an
/// `_update` call. Show it holds again on exit. The sequence is
/// `fold → _migrateAccount(from) → _migrateAccount(to) → super._update →
/// (onMint | onBurn if from/to == 0)`. The invariant can be temporarily
/// violated in between these steps — we only claim it holds at entry
/// and exit.
///
/// 1. `fold()` mutates only `totalSupplyLatestCursor`; no pot write and no
///    balance write. I(k) unchanged.
///
/// 2. `_migrateAccount(account)` advancing the cursor from `c` to `c'`
///    with stored balance `b` rasterizing to `b'`:
///    - Writes `cursor(account) = c'` and `underlyingBalance(account) = b'`.
///    - Calls `onAccountMigrated`, which does `unmigrated[c] -= b;
///      unmigrated[c'] += b'`.
///    - I(c) after: pre-step `unmigrated[c]` included `b` (account was at
///      cursor `c` with balance `b` by IH membership). Account now leaves
///      `c`, so `Σ_{cursor==c}` drops by `b`. Pot drops by `b`. ✓
///    - I(c') after: account arrives at `c'` with balance `b'`, so
///      `Σ_{cursor==c'}` rises by `b'`. Pot rises by `b'`. ✓
///    - Underflow safety: `unmigrated[c] >= b` by IH membership. ✓
///
/// 3. `super._update(from, to, amount)`:
///    - Mint case (`from == 0`): `_balances[to] += amount;
///      _totalSupply += amount`. `Σ_{cursor==latestCursor}` rises by
///      `amount` (since `to` is at `latestCursor` post-migrate). Pot is
///      NOT written yet, so the invariant is temporarily violated.
///    - Burn case (`to == 0`): reverts if `_balances[from] < amount`
///      (`ERC20InsufficientBalance`). On success,
///      `_balances[from] -= amount; _totalSupply -= amount`.
///      `Σ_{cursor==latestCursor}` drops by `amount`. Pot NOT written
///      yet — invariant temporarily violated.
///    - Transfer case: `_balances[from] -= amount; _balances[to] += amount`.
///      Both accounts at `latestCursor`, so `Σ_{cursor==latestCursor}`
///      unchanged. I(k) unchanged. Done for transfer.
///
/// 4. `onMint(amount)` (mint case only): adds `amount` to
///    `unmigrated[totalSupplyLatestCursor]`. Restores the invariant that
///    step 3 temporarily violated — pot now matches the new balance sum. ✓
///
/// 5. `onBurn(amount)` (burn case only): subtracts `amount` from
///    `unmigrated[totalSupplyLatestCursor]`. Restores the invariant. ✓
///    Underflow safety: OZ's check in step 3 already enforced
///    `_balances[from] >= amount`. By IH at `_update` entry,
///    `unmigrated[latestCursor] >= _balances[from] >= amount`, so the
///    subtraction cannot underflow. This is why `onBurn` runs AFTER
///    `super._update` — if it ran before, a lone-holder over-burn would
///    underflow the pot with a raw panic instead of surfacing OZ's
///    `ERC20InsufficientBalance` error.
///
/// Every `_update` call returns with the invariant intact; by induction
/// the invariant holds at every `_update` boundary. Q.E.D.
library LibTotalSupply {
    /// @notice Compute the effective totalSupply without state changes.
    /// Walks the init node and every completed split, accumulating per-pot
    /// contributions with sequential rasterization between each multiplier.
    /// The init node contributes identity (no multiplier), so the
    /// pre-init pot at index 0 plus the post-init pot at index 1 simply
    /// equals OZ's `_totalSupply` at the moment bootstrap fired (modulo
    /// any post-bootstrap mint/burn deltas, which onMint/onBurn route to
    /// the latest pot).
    /// @return supply The effective total supply.
    function effectiveTotalSupply() internal view returns (uint256 supply) {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();

        // No actions ever scheduled — bootstrap has not fired, so OZ's
        // totalSupply is authoritative.
        if (s.nodes.length == 0) {
            return LibERC20Storage.underlyingTotalSupply();
        }

        uint256 running = s.unmigrated[0];

        uint256 nodeIndex =
            LibCorporateActionNode.nextOfType(0, BALANCE_MIGRATION_TYPES_MASK, CompletionFilter.COMPLETED);

        while (nodeIndex != 0) {
            uint256 actionType = s.nodes[nodeIndex].actionType;
            if (actionType == ACTION_TYPE_STOCK_SPLIT_V1) {
                Float multiplier = LibStockSplit.decodeParametersV1(s.nodes[nodeIndex].parameters);
                // Rasterize via the shared rebase primitive so every step of
                // the totalSupply walk uses the same rounding characteristics
                // as per-account migration. See `LibRebaseMath.applyMultiplier`.
                running = LibRebaseMath.applyMultiplier(running, multiplier);
            }
            // ACTION_TYPE_INIT_V1: identity, no multiplier read.
            running += s.unmigrated[nodeIndex];

            nodeIndex = LibCorporateActionNode.nextOfType(
                nodeIndex, BALANCE_MIGRATION_TYPES_MASK, CompletionFilter.COMPLETED
            );
        }

        return running;
    }

    /// @notice Advance `totalSupplyLatestCursor` through any newly-completed
    /// init-or-split nodes. Called from `_update` before any account
    /// migrations so onMint/onBurn route to the correct pot.
    function fold() internal {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();

        // No actions ever scheduled — bootstrap has not fired; nothing to
        // advance and no pot to route mint/burn into.
        if (s.nodes.length == 0) return;

        // Walk from the last known cursor to find newly completed migration
        // nodes (init or stock-split). Track the latest seen in a local and
        // write once at the end — each loop-body SSTORE would otherwise be
        // stomped by the next iteration.
        uint256 nodeIndex = LibCorporateActionNode.nextOfType(
            s.totalSupplyLatestCursor, BALANCE_MIGRATION_TYPES_MASK, CompletionFilter.COMPLETED
        );

        uint256 latest;
        while (nodeIndex != 0) {
            latest = nodeIndex;
            nodeIndex = LibCorporateActionNode.nextOfType(
                nodeIndex, BALANCE_MIGRATION_TYPES_MASK, CompletionFilter.COMPLETED
            );
        }
        if (latest != 0) s.totalSupplyLatestCursor = latest;
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
        // Checked subtraction: safe by the pot invariant I(fromCursor) stated
        // at the top of this library. `storedBalance` is one of the summands
        // of `unmigrated[fromCursor]`, so the subtraction cannot underflow.
        s.unmigrated[fromCursor] -= storedBalance;
        s.unmigrated[toCursor] += newBalance;
    }

    /// @notice Update tracking for a mint (adds to the latest cursor pot).
    /// @dev When `nodes.length == 0` (no `schedule` ever called) this is a
    /// no-op: there is no init node, no pot, and `effectiveTotalSupply`
    /// falls back to OZ's `_totalSupply` directly. Once the first
    /// `schedule()` runs, `_ensureBootstrap` snapshots OZ's totalSupply
    /// into `unmigrated[0]` and `fold()` will advance
    /// `totalSupplyLatestCursor` to the init node on the next `_update`,
    /// so all subsequent mints route into the post-init pot.
    /// @param amount The minted amount.
    function onMint(uint256 amount) internal {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        if (s.nodes.length != 0) {
            s.unmigrated[s.totalSupplyLatestCursor] += amount;
        }
    }

    /// @notice Update tracking for a burn (subtracts from the latest cursor pot).
    /// @dev Pre-bootstrap is a no-op for the same reason as `onMint`.
    /// @param amount The burned amount.
    function onBurn(uint256 amount) internal {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        if (s.nodes.length != 0) {
            // Checked subtraction: safe by the pot invariant composed with
            // OZ's own `ERC20InsufficientBalance` guard on the burning
            // account's balance. See library NatSpec, proof step 5.
            s.unmigrated[s.totalSupplyLatestCursor] -= amount;
        }
    }
}

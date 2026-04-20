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
/// ## Pots are not consolidated
///
/// Unlike the two-bucket approach, pots are never merged or consolidated as
/// new splits complete. The view walks all completed-split pots at read
/// time and automatically picks up new multipliers.
///
/// `fold()` is still called on every `_update`, but it only does two things:
/// bootstrap `unmigrated[0]` from OZ's raw totalSupply on the first
/// completed-split encounter, and advance `totalSupplyLatestSplit` so
/// mint/burn tracking routes to the correct pot. It does NOT recompute or
/// redistribute any existing pot.
///
/// ## Pot invariant
///
/// At every `_update` boundary (post-bootstrap), for every cursor `k`:
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
/// **Base case** (immediately after first `fold()` bootstrap):
/// - Every account has `cursor == 0` because no migration has run yet.
/// - `unmigrated[0] := underlyingTotalSupply() == Σ_acc underlyingBalance(acc)`
///   by OZ's own invariant (`_totalSupply` equals the sum of `_balances`).
/// - So `unmigrated[0] == Σ_{cursor==0} underlyingBalance(acc)`. I(0) holds.
/// - For `k > 0`, no account has cursor `k` and `unmigrated[k] == 0`. I(k) holds.
///
/// **Inductive step.** Assume `I(k)` holds for all `k` pre-transition. Show
/// each mutation in the ordered `_update` sequence preserves it. The
/// sequence is `fold → _migrateAccount(from) → _migrateAccount(to) →
/// (onMint | onBurn) → super._update`.
///
/// 1. `fold()` post-bootstrap mutates only `totalSupplyLatestSplit`; no pot
///    write. I(k) unchanged.
///
/// 2. `_migrateAccount(account)` advancing the cursor from `c` to `c'`
///    with stored balance `b` rasterizing to `b'`:
///    - Writes `cursor(account) = c'` and `underlyingBalance(account) = b'`.
///    - Calls `onAccountMigrated`, which does `unmigrated[c] -= b;
///      unmigrated[c'] += b'`.
///    - I(c) after: pre-transition `unmigrated[c]` included `b` (account was
///      at cursor `c` with balance `b` by IH membership). Account now leaves
///      `c`, so `Σ_{cursor==c}` drops by `b`. Pot drops by `b`. ✓
///    - I(c') after: account arrives at `c'` with balance `b'`, so
///      `Σ_{cursor==c'}` rises by `b'`. Pot rises by `b'`. ✓
///    - Underflow safety: `unmigrated[c] >= b` by IH membership. ✓
///
/// 3. `onMint(amount)` for a mint (`from == 0`, `to != 0`):
///    - Pre-call, `to` has just been migrated and has `cursor(to) ==
///      totalSupplyLatestSplit`. OZ has not yet added `amount` to
///      `_balances[to]`.
///    - `onMint` adds `amount` to `unmigrated[totalSupplyLatestSplit]`.
///    - `super._update` then sets `_balances[to] += amount`, so
///      `Σ_{cursor==latestSplit}` rises by `amount`. Pot rose by `amount`. ✓
///
/// 4. `onBurn(amount)` for a burn (`from != 0`, `to == 0`):
///    - Pre-call, `from` has just been migrated and has `cursor(from) ==
///      totalSupplyLatestSplit`.
///    - `onBurn` subtracts `amount` from `unmigrated[totalSupplyLatestSplit]`.
///    - `super._update` then sets `_balances[from] -= amount`, so
///      `Σ_{cursor==latestSplit}` drops by `amount`. Pot dropped by
///      `amount`. ✓
///    - Underflow safety: OZ's `_update` reverts the burn with
///      `ERC20InsufficientBalance` if `_balances[from] < amount`. Since
///      `_balances[from]` is a summand of `unmigrated[totalSupplyLatestSplit]`
///      by IH, and OZ's guard enforces `_balances[from] >= amount`, we have
///      `unmigrated[totalSupplyLatestSplit] >= amount`. ✓
///
/// 5. Plain transfer (`from != 0`, `to != 0`) in `super._update`:
///    - Both accounts were migrated to `totalSupplyLatestSplit` pre-call.
///    - `_balances[from] -= amount; _balances[to] += amount`. Net change
///      to `Σ_{cursor==latestSplit}` is zero. No pot write needed. ✓
///
/// Every transition preserves I(k); the invariant holds at every
/// `_update` boundary post-bootstrap by induction. Q.E.D.
library LibTotalSupply {
    /// @notice Compute the effective totalSupply without state changes.
    /// Walks all completed splits, accumulating per-pot contributions with
    /// sequential rasterization between each multiplier.
    /// @return supply The effective total supply.
    function effectiveTotalSupply() internal view returns (uint256 supply) {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();

        // No splits ever scheduled — use OZ fallback.
        if (s.nodes.length == 0) {
            return LibERC20Storage.underlyingTotalSupply();
        }

        // Find the first completed split. Used both to decide whether to
        // fall back to OZ (no completed splits → supply is whatever OZ
        // says) and as the starting node for the walk below.
        uint256 nodeIndex = LibCorporateActionNode.nextOfType(0, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);

        uint256 running;
        if (s.totalSupplyBootstrapped) {
            running = s.unmigrated[0];
        } else {
            if (nodeIndex == 0) return LibERC20Storage.underlyingTotalSupply();
            running = LibERC20Storage.underlyingTotalSupply();
        }

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
        //
        // Safety: `underlyingTotalSupply()` returns OZ's `_totalSupply`, and
        // the pot invariant requires it to equal `Σ _balances` at the moment
        // of this read. That equality is maintained by OZ's `_update` but
        // broken by `_migrateAccount`, which writes balances directly via
        // `LibERC20Storage.setUnderlyingBalance` without touching
        // `_totalSupply`.
        //
        // Bootstrap fires exactly once, at the top of the first `_update`
        // where a completed stock split exists. In every prior `_update`,
        // `_migrateAccount` called `LibRebase.migratedBalance` which walks
        // only completed splits — so in a world with no completed splits,
        // it early-returned without writing any balance. Therefore at the
        // moment bootstrap runs here, no `setUnderlyingBalance` has ever
        // fired, and OZ's invariant still holds.
        //
        // If this ordering changes (e.g. `fold()` moved after
        // `_migrateAccount`, or a new caller of `setUnderlyingBalance`
        // added), this bootstrap is no longer safe and must be
        // re-derived.
        if (!s.totalSupplyBootstrapped) {
            uint256 firstIndex =
                LibCorporateActionNode.nextOfType(0, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
            if (firstIndex == 0) return;

            s.unmigrated[0] = LibERC20Storage.underlyingTotalSupply();
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
        // Checked subtraction: safe by the pot invariant I(fromCursor) stated
        // at the top of this library. `storedBalance` is one of the summands
        // of `unmigrated[fromCursor]`, so the subtraction cannot underflow.
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
            // Checked subtraction: safe by the pot invariant composed with
            // OZ's own `ERC20InsufficientBalance` guard on the burning
            // account's balance. See library NatSpec, proof step 4.
            s.unmigrated[s.totalSupplyLatestSplit] -= amount;
        }
    }
}

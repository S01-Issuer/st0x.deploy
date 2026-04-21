// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {OffchainAssetReceiptVault} from "rain.vats/concrete/vault/OffchainAssetReceiptVault.sol";
import {LibCorporateAction} from "../lib/LibCorporateAction.sol";
import {LibRebase} from "../lib/LibRebase.sol";
import {LibTotalSupply} from "../lib/LibTotalSupply.sol";
import {LibERC20Storage} from "../lib/LibERC20Storage.sol";

/// @title StoxReceiptVault
/// @notice An OffchainAssetReceiptVault that supports corporate actions such
/// as stock splits. Balances automatically reflect any pending corporate
/// action multipliers.
///
/// Migration is lazy: each account's stored balance is rasterized to the
/// current rebase version on first interaction (transfer, mint, burn).
/// Balance writes go directly to OZ's ERC20 storage via assembly — no
/// mint/burn, no Transfer events, no totalSupply side effects.
///
/// totalSupply uses per-cursor pots so that account migrations genuinely
/// improve precision. See LibTotalSupply for the full explanation.
///
/// @dev "Migration" here covers two distinct operations that usually happen
/// together but MUST be treated separately:
/// 1. **Balance rasterization** — rewriting `LibERC20Storage.underlyingBalance(account)`
///    from its pre-rebase value to the post-rebase value.
/// 2. **Cursor advancement** — updating `accountMigrationCursor[account]` to
///    the index of the latest completed split this account has now seen.
///
/// For zero-balance accounts, (1) is a no-op but (2) still matters: without
/// it a subsequent mint or transfer-in would land at a stale cursor and the
/// next `balanceOf` read would erroneously re-apply completed multipliers to
/// a balance that was already written at the post-rebase basis, silently
/// inflating the recipient's balance. See `LibRebase.migratedBalance` and
/// its zero-balance regression tests.
contract StoxReceiptVault is OffchainAssetReceiptVault {
    /// @notice Emitted when an account's stored balance is rasterized to the
    /// post-rebase basis and / or its migration cursor advances through
    /// completed corporate actions. Fires from `_update` via `_migrateAccount`,
    /// before the mint / burn / transfer delta is applied. Only fires when
    /// the stored balance actually changes; pure cursor-only advancements
    /// (zero-balance accounts) do not emit.
    /// @param account The account whose migration state changed.
    /// @param fromCursor The account's migration cursor before this migration
    /// (0 means never migrated). Corresponds to the 1-based index of the last
    /// completed corporate action this account had already seen.
    /// @param toCursor The account's migration cursor after this migration.
    /// @param oldBalance The account's **stored** balance before rasterization
    /// — i.e. the value returned by `LibERC20Storage.underlyingBalance(account)` at
    /// the moment the migration starts, NOT the post-rebase effective balance.
    /// @param newBalance The account's **stored** balance after rasterization.
    /// For a single forward 2x split applied to a pre-rebase stored balance of
    /// 100, this is 200.
    event AccountMigrated(
        address indexed account, uint256 fromCursor, uint256 toCursor, uint256 oldBalance, uint256 newBalance
    );

    /// @notice Returns `account`'s ERC20 balance including any pending rebase
    /// multipliers from completed corporate actions. Does NOT mutate state —
    /// if the account's stored balance is stale relative to the latest
    /// completed split, this call computes the rebased value on the fly and
    /// returns it. The actual rasterization happens lazily on the next
    /// `_update` touch.
    /// @param account The account to query.
    /// @return The effective balance after applying all completed stock splits
    /// on top of the account's last-migrated cursor.
    function balanceOf(address account) public view virtual override returns (uint256) {
        uint256 stored = LibERC20Storage.underlyingBalance(account);
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        // The second return value is the new cursor — intentionally discarded
        // here because `balanceOf` is a pure read that must not mutate state;
        // the cursor advancement happens on the next `_update` touch via
        // `_migrateAccount`.
        // slither-disable-next-line unused-return
        (uint256 balance,) = LibRebase.migratedBalance(stored, s.accountMigrationCursor[account]);
        return balance;
    }

    /// @notice Returns the effective total supply after applying every
    /// completed corporate action's multiplier on top of the per-cursor pot
    /// model tracked by `LibTotalSupply`. See `LibTotalSupply` for the full
    /// explanation of the per-pot walking recurrence.
    /// @return An upper bound on `sum(balanceOf)` that converges to exact
    /// equality once every holder sharing a pre-split cursor has migrated
    /// through the split. The walk applies each multiplier to the aggregate
    /// pot, so for fractional multipliers `trunc(Σ aᵢ * m) ≥ Σ trunc(aᵢ * m)`
    /// — the gap is the per-account truncation dust, and it disappears as
    /// accounts migrate.
    function totalSupply() public view virtual override returns (uint256) {
        return LibTotalSupply.effectiveTotalSupply();
    }

    /// @dev Bootstraps totalSupply tracking, migrates both sender and
    /// recipient, calls super, then tracks mint/burn deltas in the pot.
    /// `onMint` / `onBurn` run AFTER `super._update` so OZ's own validation
    /// (e.g. `ERC20InsufficientBalance` on an over-burn) fires first. If
    /// these ran before super, a lone-holder over-burn at `latestSplit`
    /// would underflow the pot with a raw arithmetic panic rather than
    /// surfacing OZ's intended error.
    function _update(address from, address to, uint256 amount) internal virtual override {
        LibTotalSupply.fold();
        _migrateAccount(from);
        _migrateAccount(to);

        super._update(from, to, amount);

        if (from == address(0)) {
            LibTotalSupply.onMint(amount);
        } else if (to == address(0)) {
            LibTotalSupply.onBurn(amount);
        }
    }

    /// @dev Migrate a single account through every completed split that has
    /// not yet been applied to it (i.e. completed split nodes whose index is
    /// past the account's current `accountMigrationCursor`). This both
    /// rasterizes the account's stored balance to the post-rebase basis and
    /// advances the cursor; for zero-balance accounts the balance rewrite is
    /// a no-op but the cursor advancement still matters — see
    /// `LibRebase.migratedBalance` and its zero-balance regression tests for
    /// the bug this prevents.
    ///
    /// `internal` (rather than `private`) so test harnesses derived from this
    /// contract can exercise the migration logic in isolation. The function is
    /// only ever called from this contract's `_update` override.
    function _migrateAccount(address account) internal {
        if (account == address(0)) return;

        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        uint256 currentCursor = s.accountMigrationCursor[account];
        uint256 storedBalance = LibERC20Storage.underlyingBalance(account);

        (uint256 newBalance, uint256 newCursor) = LibRebase.migratedBalance(storedBalance, currentCursor);

        if (newCursor == currentCursor) return;

        s.accountMigrationCursor[account] = newCursor;

        if (newBalance != storedBalance) {
            LibERC20Storage.setUnderlyingBalance(account, newBalance);
            emit AccountMigrated(account, currentCursor, newCursor, storedBalance, newBalance);
        }

        LibTotalSupply.onAccountMigrated(currentCursor, storedBalance, newCursor, newBalance);
    }
}

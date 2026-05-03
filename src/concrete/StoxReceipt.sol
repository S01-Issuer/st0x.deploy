// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Receipt} from "rain.vats/concrete/receipt/Receipt.sol";
import {ERC1155Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC1155/ERC1155Upgradeable.sol";
import {IERC1155} from "openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";
import {ICorporateActionsV1} from "../interface/ICorporateActionsV1.sol";
import {LibCorporateActionReceipt} from "../lib/LibCorporateActionReceipt.sol";
import {LibERC1155Storage} from "../lib/LibERC1155Storage.sol";
import {LibReceiptRebase} from "../lib/LibReceiptRebase.sol";

/// @title StoxReceipt
/// @notice A `Receipt` specialized for Stox. Extends the rain.vats receipt with
/// lazy per-`(holder, id)` rebase migration for corporate actions (stock
/// splits).
///
/// ## Rebase model
///
/// When a stock split lands on the vault, every receipt balance must rebase
/// in lockstep with the vault's ERC-20 share balance — otherwise a holder
/// arbitrages the two representations (redeem an un-rebased receipt for the
/// pre-split underlying while holding a post-split share worth double).
///
/// Migration is lazy, identical in shape to the share-side model:
///   - Each `(holder, id)` pair tracks its own migration cursor — the 1-based
///     index of the last completed stock split node it has been migrated
///     through. Storage lives at a dedicated ERC-7201 namespace on this
///     contract (`LibCorporateActionReceipt`).
///   - On every `_update` (transfer / mint / burn), both `from` and `to` are
///     migrated through all completed stock splits for each `id` in the
///     batch before the transfer executes.
///   - Migration writes the rasterized balance directly to OZ ERC-1155
///     storage via `LibERC1155Storage.setUnderlyingBalance`, avoiding spurious
///     `TransferSingle` events, recursive `_update` calls, and a second
///     manager-authorizer callback.
///
/// The multiplier source is the vault's corporate action linked list, read
/// through `ICorporateActionsV1` on the manager (vault) address. The shared
/// `LibReceiptRebase.migratedBalance` helper walks the list and applies each
/// multiplier via `LibRebaseMath.applyMultiplier` — the same primitive used
/// by the share-side `LibRebase` and `LibTotalSupply`, guaranteeing bitwise-
/// identical rasterization on both sides.
///
/// ## `balanceOf` override
///
/// `balanceOf(account, id)` is overridden to return the effective balance
/// (stored balance with all pending multipliers applied) without mutating
/// state, matching the share-side `StoxReceiptVault.balanceOf` pattern.
///
/// ## Zero-balance cursor advancement
///
/// Same invariant as the share side: for a `(holder, id)` pair with
/// `storedBalance == 0`, the cursor is still advanced through completed
/// splits during migration. If it were not, a subsequent mint or transfer-in
/// to that `(holder, id)` would land at a stale cursor and the next
/// `balanceOf` read would re-apply every completed multiplier to a freshly-
/// written post-rebase balance, silently inflating the position. See the
/// `testZeroBalanceAdvancesCursor` regression in both `LibRebase.t.sol` and
/// `LibReceiptRebase.t.sol`.
contract StoxReceipt is Receipt {
    /// @notice Emitted whenever `_migrateHolderId` advances a `(account, id)`
    /// pair's migration cursor. The cursor itself is storage state, so the
    /// event fires on every cursor advance regardless of whether
    /// `oldBalance == newBalance`. Fires from `_update` via
    /// `_migrateHolderId`, before the mint / burn / transfer delta is
    /// applied.
    /// @param account The holder whose `(account, id)` migration state changed.
    /// @param id The receipt id.
    /// @param fromCursor The `(account, id)` cursor before this migration
    /// (0 means never migrated).
    /// @param toCursor The `(account, id)` cursor after this migration.
    /// @param oldBalance The raw stored balance before rasterization.
    /// @param newBalance The raw stored balance after rasterization.
    event ReceiptAccountMigrated(
        address indexed account,
        uint256 indexed id,
        uint256 fromCursor,
        uint256 toCursor,
        uint256 oldBalance,
        uint256 newBalance
    );

    /// @notice Returns `account`'s receipt balance for `id` including any
    /// pending rebase multipliers from completed corporate actions on the
    /// vault. Does NOT mutate state — if the stored balance is stale
    /// relative to the latest completed split, this call computes the
    /// rebased value on the fly. Actual rasterization happens lazily on the
    /// next `_update` touch.
    /// @inheritdoc IERC1155
    function balanceOf(address account, uint256 id)
        public
        view
        virtual
        override(ERC1155Upgradeable, IERC1155)
        returns (uint256)
    {
        return _balanceOf(account, id, _vault());
    }

    /// @notice Batch-aware `balanceOf`. OZ's default `balanceOfBatch` reads
    /// `_balances[id][account]` directly and would bypass the rebase override,
    /// returning raw stored balances instead of rebased ones. This override
    /// applies the same multiplier chain per element so that batch reads are
    /// consistent with single-element `balanceOf`.
    /// @inheritdoc ERC1155Upgradeable
    function balanceOfBatch(address[] memory accounts, uint256[] memory ids)
        public
        view
        virtual
        override(ERC1155Upgradeable, IERC1155)
        returns (uint256[] memory)
    {
        if (accounts.length != ids.length) {
            revert ERC1155InvalidArrayLength(ids.length, accounts.length);
        }
        ICorporateActionsV1 vault = _vault();
        uint256[] memory batchBalances = new uint256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; ++i) {
            batchBalances[i] = _balanceOf(accounts[i], ids[i], vault);
        }
        return batchBalances;
    }

    /// @dev Shared implementation of the rebased balance read. Takes the
    /// vault as a parameter so callers inside a loop (`balanceOfBatch`)
    /// can fetch it once and pass it in, avoiding an external self-call
    /// per iteration.
    function _balanceOf(address account, uint256 id, ICorporateActionsV1 vault) internal view returns (uint256) {
        uint256 stored = LibERC1155Storage.underlyingBalance(account, id);
        uint256 cursor = LibCorporateActionReceipt.getStorage().accountIdCursor[account][id];
        // The second return value is the new cursor — intentionally discarded
        // here because this is a pure read that must not mutate state;
        // cursor advancement happens on the next `_update` via
        // `_migrateHolderId`.
        // slither-disable-next-line unused-return
        (uint256 effective,) = LibReceiptRebase.migratedBalance(stored, cursor, vault);
        return effective;
    }

    /// @dev Migrates both sender and recipient across every id in the batch,
    /// then calls `super._update` to run the manager authorizer callback and
    /// the actual OZ ERC-1155 transfer.
    ///
    /// **Reentrancy note:** `super._update` is the LAST statement in this
    /// function. OZ's ERC-1155 calls `onERC1155Received` /
    /// `onERC1155BatchReceived` on contract recipients from inside
    /// `super._update`. By the time the receiver hook fires, all migration
    /// state is fully consistent — cursors advanced, balances rasterized,
    /// events emitted. A malicious receiver calling back into `balanceOf`,
    /// `_update`, or any other view/mutator sees correct post-migration
    /// state. No state is modified after `super._update` returns, so there
    /// is no window for reentrancy to observe inconsistent data.
    /// If a future refactor moves ANY state mutation after `super._update`,
    /// this analysis is invalidated and reentrancy risk must be re-evaluated.
    /// @inheritdoc ERC1155Upgradeable
    function _update(address from, address to, uint256[] memory ids, uint256[] memory amounts)
        internal
        virtual
        override
    {
        // Snapshot the vault once so we don't pay the external self-call
        // per iteration. `manager()` is the external view on Receipt that
        // returns the configured vault address from Receipt7201Storage.
        ICorporateActionsV1 vault = _vault();

        // Migrate each (account, id) pair before the transfer executes.
        // `_migrateHolderId` short-circuits on `address(0)` so mint (from ==
        // 0) and burn (to == 0) pass straight through to super._update.
        for (uint256 i = 0; i < ids.length; i++) {
            _migrateHolderId(from, ids[i], vault);
            _migrateHolderId(to, ids[i], vault);
        }

        // Now that both sides are rasterized to the current cursor, run
        // the inherited `_update` (manager authorizer callback + OZ ERC-1155
        // transfer).
        super._update(from, to, ids, amounts);
    }

    /// @dev Migrate a single `(account, id)` pair through every completed
    /// stock split the pair has not yet been migrated through. Both the
    /// balance rasterization and the cursor advancement happen here; for
    /// zero-balance pairs the rewrite is a no-op but the cursor advancement
    /// still matters — see contract-level NatSpec for the inflation bug this
    /// prevents.
    ///
    /// `internal` so test harnesses derived from this contract can exercise
    /// the migration logic in isolation.
    function _migrateHolderId(address account, uint256 id, ICorporateActionsV1 vault) internal {
        if (account == address(0)) return;

        LibCorporateActionReceipt.CorporateActionReceiptStorage storage s = LibCorporateActionReceipt.getStorage();
        uint256 currentCursor = s.accountIdCursor[account][id];
        uint256 storedBalance = LibERC1155Storage.underlyingBalance(account, id);

        (uint256 newBalance, uint256 newCursor) = LibReceiptRebase.migratedBalance(storedBalance, currentCursor, vault);

        if (newCursor == currentCursor) return;

        s.accountIdCursor[account][id] = newCursor;

        // Skip the SSTORE when the rasterized balance is unchanged.
        if (newBalance != storedBalance) {
            LibERC1155Storage.setUnderlyingBalance(account, id, newBalance);
        }
        emit ReceiptAccountMigrated(account, id, currentCursor, newCursor, storedBalance, newBalance);
    }

    /// @dev Cached / fresh read of the configured vault address, cast to
    /// the corporate-actions read interface. Uses `this.manager()` (an
    /// external self-call) to avoid hardcoding the rain.vats
    /// `Receipt7201Storage` slot literal in this file — the cost is one
    /// CALL opcode per `_update`, which is amortized across every
    /// `(account, id)` pair the batch touches.
    function _vault() internal view returns (ICorporateActionsV1) {
        return ICorporateActionsV1(this.manager());
    }
}

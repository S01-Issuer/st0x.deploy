// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Receipt} from "rain-vats-0.2.1/src/concrete/receipt/Receipt.sol";
import {ERC1155Upgradeable} from "@openzeppelin-contracts-upgradeable-5.6.1/token/ERC1155/ERC1155Upgradeable.sol";
import {IERC1155} from "@openzeppelin-contracts-5.6.1/token/ERC1155/IERC1155.sol";
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
/// When a stock split completes on the vault, every receipt balance rebases
/// in lockstep with the vault's ERC-20 share balance.
///
/// Migration is lazy, the same shape as the share side:
///   - Each `(holder, id)` pair tracks its own migration cursor: the
///     vault's node index of the last completed stock split this pair has
///     been migrated through. Storage lives at a dedicated ERC-7201
///     namespace on this contract (`LibCorporateActionReceipt`). The
///     default cursor 0 is the vault's bootstrap node.
///   - On every `_update` (transfer / mint / burn), both `from` and `to` are
///     migrated through all completed stock splits for each `id` in the
///     batch before the transfer executes.
///   - Migration writes the rasterized balance directly to OZ ERC-1155
///     storage via `LibERC1155Storage.setUnderlyingBalance`, without going
///     through `_update`.
///
/// The multiplier source is the vault's corporate action linked list, read
/// through `ICorporateActionsV1` on the manager (vault) address.
/// `LibReceiptRebase.migratedBalance` walks the list and applies each
/// multiplier via `LibRebaseMath.applyMultiplier`, the same primitive used
/// by the share-side `LibRebase` and `LibTotalSupply`, so both sides
/// rasterize identically.
///
/// ## `balanceOf` override
///
/// `balanceOf(account, id)` returns the effective balance (stored balance
/// with all pending multipliers applied) without mutating state, matching
/// the share-side `StoxReceiptVault.balanceOf`.
///
/// ## Zero-balance cursor advancement
///
/// As on the share side, a `(holder, id)` pair with `storedBalance == 0`
/// still has its cursor advanced through completed splits during migration,
/// so a later mint or transfer-in lands at the current cursor rather than a
/// stale one that would re-apply every completed multiplier on the next
/// `balanceOf` read.
contract StoxReceipt is Receipt {
    /// @notice Emitted whenever `migrateHolderId` advances a `(account, id)`
    /// pair's migration cursor. The cursor itself is storage state, so the
    /// event fires on every cursor advance regardless of whether
    /// `oldBalance == newBalance`. Fires from `_update` via
    /// `migrateHolderId`, before the mint / burn / transfer delta is
    /// applied.
    /// @param account The holder whose `(account, id)` migration state changed.
    /// @param id The receipt id.
    /// @param fromActionId The action id the `(account, id)` cursor
    /// was at before this migration. The default 0 is the vault's bootstrap
    /// node.
    /// @param toActionId The action id the `(account, id)` cursor is
    /// at after this migration.
    /// @param oldBalance The raw stored balance before rasterization.
    /// @param newBalance The raw stored balance after rasterization.
    event ReceiptAccountMigrated(
        address indexed account,
        uint256 indexed id,
        uint256 fromActionId,
        uint256 toActionId,
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
        return balanceOfFor(account, id, getVault());
    }

    /// @notice Batch-aware `balanceOf`. OZ's `balanceOfBatch` reads
    /// `_balances[id][account]` directly; this override applies the same
    /// multiplier chain per element as single-element `balanceOf`.
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
        ICorporateActionsV1 vault = getVault();
        uint256[] memory batchBalances = new uint256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; ++i) {
            batchBalances[i] = balanceOfFor(accounts[i], ids[i], vault);
        }
        return batchBalances;
    }

    /// @dev Shared implementation of the rebased balance read. Takes the
    /// vault as a parameter so `balanceOfBatch` fetches it once.
    function balanceOfFor(address account, uint256 id, ICorporateActionsV1 vault) internal view returns (uint256) {
        uint256 stored = LibERC1155Storage.underlyingBalance(account, id);
        uint256 cursor = LibCorporateActionReceipt.getStorage().accountIdCursor[account][id];
        // The second return value is the new cursor, discarded because this
        // is a read; cursor advancement happens on the next `_update` via
        // `migrateHolderId`.
        // slither-disable-next-line unused-return
        (uint256 effective,) = LibReceiptRebase.migratedBalance(stored, cursor, vault);
        return effective;
    }

    /// @dev Migrates both sender and recipient across every id in the batch,
    /// then calls `super._update` to run the manager authorizer callback and
    /// the actual OZ ERC-1155 transfer.
    ///
    /// `super._update` is the last statement in this function. OZ's ERC-1155
    /// calls `onERC1155Received` / `onERC1155BatchReceived` on contract
    /// recipients from inside `super._update`; by then all migration state is
    /// consistent (cursors advanced, balances rasterized, events emitted) and
    /// no state is modified after `super._update` returns.
    ///
    /// Migration walks `vault.nextOfType` / `vault.getActionParameters` per
    /// node without snapshotting, trusting each STATICCALL return
    /// individually; the receipt trusts whatever implementation the vault
    /// beacon's owner installs behind its manager pointer.
    /// @inheritdoc ERC1155Upgradeable
    function _update(address from, address to, uint256[] memory ids, uint256[] memory amounts)
        internal
        virtual
        override
    {
        // Read the vault once for the whole batch.
        ICorporateActionsV1 vault = getVault();

        // Migrate each (account, id) pair before the transfer executes.
        // `migrateHolderId` short-circuits on `address(0)` so mint (from ==
        // 0) and burn (to == 0) pass straight through to super._update.
        for (uint256 i = 0; i < ids.length; i++) {
            migrateHolderId(from, ids[i], vault);
            migrateHolderId(to, ids[i], vault);
        }

        // Both sides are rasterized to the current cursor; run the inherited
        // `_update` (manager authorizer callback + OZ ERC-1155 transfer).
        super._update(from, to, ids, amounts);
    }

    /// @dev Migrate a single `(account, id)` pair through every completed
    /// stock split the pair has not yet been migrated through. Both the
    /// balance rasterization and the cursor advancement happen here; for
    /// zero-balance pairs the rewrite is a no-op and the cursor still
    /// advances.
    ///
    /// `internal` so test harnesses derived from this contract can call it
    /// directly.
    function migrateHolderId(address account, uint256 id, ICorporateActionsV1 vault) internal {
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

    /// @dev The configured vault address, read via `this.manager()` and cast
    /// to the corporate-actions read interface.
    function getVault() internal view returns (ICorporateActionsV1) {
        return ICorporateActionsV1(this.manager());
    }
}

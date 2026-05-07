// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title RebaseMigratable
/// @notice Shared skeleton for the lazy rebase-migration algorithm. Both
/// `StoxReceiptVault` (share side) and `StoxReceipt` (receipt side) lazily
/// rasterize each holder's stored balance to the latest completed corporate
/// action on first touch in `_update`. The orchestration is identical:
///
/// 1. Zero-address short-circuit (mint `from`, burn `to`).
/// 2. Read the holder's current cursor + stored balance.
/// 3. Walk the rebase from that cursor forward, returning the rasterized
///    balance and the advanced cursor.
/// 4. Early-return if the cursor didn't advance (no completed action newer
///    than the holder's last touch).
/// 5. Write the new cursor.
/// 6. If the balance changed (it can stay equal under the identity bootstrap
///    or after a truncate-to-zero), write the new stored balance.
/// 7. Emit the migration event.
/// 8. Run the post-migrate hook (share side updates the totalSupply pots;
///    receipt side is a no-op).
///
/// The differences are entirely plug-points (which storage to read/write,
/// which rebase walk to invoke, which event to emit, whether the post-hook
/// touches additional state). This abstract owns the orchestration; the
/// concrete contracts implement the plug-points and the shape stays a
/// single-source-of-truth instead of being mirrored across two files.
///
/// **`id` parameter.** The receipt side is keyed by `(holder, id)` for the
/// ERC-1155 token id. The share side has no id concept — its overrides
/// ignore the parameter, and its `_emitMigrated` hook drops the field
/// from the event signature. The slight smell of an always-zero `id` on
/// the share side is the cost of keeping one orchestration; the
/// alternative (separate `_migrateAccount` / `_migrateHolderId` shapes)
/// is exactly the duplication this base eliminates.
abstract contract RebaseMigratable {
    /// @dev Read the holder's current migration cursor.
    /// @param account The holder.
    /// @param id The ERC-1155 token id (ignored by share-side overrides).
    function _readCursor(address account, uint256 id) internal view virtual returns (uint256);

    /// @dev Write the holder's new migration cursor.
    function _writeCursor(address account, uint256 id, uint256 cursor) internal virtual;

    /// @dev Read the holder's raw stored balance (pre-rebase, before any
    /// pending multipliers are applied).
    function _readStoredBalance(address account, uint256 id) internal view virtual returns (uint256);

    /// @dev Write the holder's rasterized stored balance (post-rebase).
    function _writeStoredBalance(address account, uint256 id, uint256 balance) internal virtual;

    /// @dev Walk the rebase from `cursor` forward, returning the rasterized
    /// balance and the advanced cursor.
    function _walkRebase(uint256 storedBalance, uint256 cursor) internal view virtual returns (uint256, uint256);

    /// @dev Emit the migration event with the override's preferred shape.
    /// Share-side overrides drop `id`; receipt-side keeps it.
    function _emitMigrated(
        address account,
        uint256 id,
        uint256 fromActionId,
        uint256 toActionId,
        uint256 oldBalance,
        uint256 newBalance
    ) internal virtual;

    /// @dev Hook called after the migration is fully written. Share side
    /// updates the per-cursor totalSupply pots via
    /// `LibTotalSupply.onAccountMigrated`; receipt side is a no-op.
    function _postMigrate(uint256 fromActionId, uint256 toActionId, uint256 oldBalance, uint256 newBalance)
        internal
        virtual;

    /// @dev Run the lazy rebase migration for `(account, id)`. Idempotent —
    /// calling on an account already at the latest cursor is a no-op.
    function _migrate(address account, uint256 id) internal {
        if (account == address(0)) return;

        uint256 currentCursor = _readCursor(account, id);
        uint256 storedBalance = _readStoredBalance(account, id);

        (uint256 newBalance, uint256 newCursor) = _walkRebase(storedBalance, currentCursor);

        if (newCursor == currentCursor) return;

        _writeCursor(account, id, newCursor);

        // Skip the SSTORE when the rasterized balance is unchanged. Equal
        // balances arise under the identity bootstrap (no real multiplier
        // applied) and when fractional truncation lands on the same
        // integer (e.g. a 1-wei balance at any multiplier). The cursor
        // advancement above is what matters for these cases.
        if (newBalance != storedBalance) {
            _writeStoredBalance(account, id, newBalance);
        }

        _emitMigrated(account, id, currentCursor, newCursor, storedBalance, newBalance);

        _postMigrate(currentCursor, newCursor, storedBalance, newBalance);
    }
}

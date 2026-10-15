// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title RebaseMigratable
/// @notice The lazy rebase migration shared by the share side
/// (`StoxReceiptVault`) and the receipt side (`StoxReceipt`). Each side
/// supplies its own storage, rebase walk, event and post-migration hook; the
/// share side has no token id and ignores `id`.
abstract contract RebaseMigratable {
    function readCursor(address account, uint256 id) internal view virtual returns (uint256);

    function writeCursor(address account, uint256 id, uint256 cursor) internal virtual;

    function readStoredBalance(address account, uint256 id) internal view virtual returns (uint256);

    function writeStoredBalance(address account, uint256 id, uint256 oldBalance, uint256 newBalance) internal virtual;

    function walkRebase(uint256 storedBalance, uint256 cursor) internal view virtual returns (uint256, uint256);

    function emitMigrated(
        address account,
        uint256 id,
        uint256 fromActionId,
        uint256 toActionId,
        uint256 oldBalance,
        uint256 newBalance
    ) internal virtual;

    function postMigrate(uint256 fromActionId, uint256 toActionId, uint256 oldBalance, uint256 newBalance)
        internal
        virtual;

    /// @dev Rasterizes `(account, id)` through every completed split past its
    /// cursor. The cursor advances even when the balance does not change, and
    /// the event fires on every advance.
    function migrate(address account, uint256 id) internal {
        if (account == address(0)) return;

        uint256 currentCursor = readCursor(account, id);
        uint256 storedBalance = readStoredBalance(account, id);

        (uint256 newBalance, uint256 newCursor) = walkRebase(storedBalance, currentCursor);

        if (newCursor == currentCursor) return;

        writeCursor(account, id, newCursor);

        if (newBalance != storedBalance) {
            writeStoredBalance(account, id, storedBalance, newBalance);
        }

        emitMigrated(account, id, currentCursor, newCursor, storedBalance, newBalance);

        postMigrate(currentCursor, newCursor, storedBalance, newBalance);
    }
}

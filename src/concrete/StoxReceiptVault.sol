// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {OffchainAssetReceiptVault} from "ethgild/concrete/vault/OffchainAssetReceiptVault.sol";
import {LibCorporateAction} from "../lib/LibCorporateAction.sol";
import {LibRebase} from "../lib/LibRebase.sol";
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
contract StoxReceiptVault is OffchainAssetReceiptVault {
    /// Emitted when an account is migrated to a new rebase version.
    /// @param account The account that was migrated.
    /// @param fromRebaseId The rebase version before migration.
    /// @param toRebaseId The rebase version after migration.
    /// @param oldBalance The stored balance before migration.
    /// @param newBalance The effective balance after migration.
    event AccountMigrated(
        address indexed account, uint256 fromRebaseId, uint256 toRebaseId, uint256 oldBalance, uint256 newBalance
    );

    /// @dev Returns the effective balance including pending rebase multipliers.
    /// This is a view function — it does not rasterize the balance to storage.
    function balanceOf(address account) public view virtual override returns (uint256) {
        uint256 stored = LibERC20Storage.getBalance(account);
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        return LibRebase.effectiveBalance(stored, s.accountRebaseId[account], s.rebaseCount);
    }

    /// @dev Migrates both sender and recipient before applying the transfer.
    /// Migration rasterizes the effective balance by writing directly to the
    /// ERC20 balance storage slot, then updates the account's rebase version.
    /// No mint/burn, no Transfer events — purely internal storage migration.
    function _update(address from, address to, uint256 amount) internal virtual override {
        _migrateAccount(from);
        _migrateAccount(to);
        super._update(from, to, amount);
    }

    /// @dev Migrate a single account to the current rebase version. Writes
    /// the effective balance directly to storage.
    function _migrateAccount(address account) private {
        // address(0) is used for mints and burns — no migration needed.
        if (account == address(0)) return;

        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        uint256 currentVersion = s.accountRebaseId[account];
        uint256 targetVersion = s.rebaseCount;

        if (currentVersion >= targetVersion) return;

        uint256 storedBalance = LibERC20Storage.getBalance(account);
        uint256 newBalance = LibRebase.effectiveBalance(storedBalance, currentVersion, targetVersion);

        s.accountRebaseId[account] = targetVersion;

        if (newBalance != storedBalance) {
            LibERC20Storage.setBalance(account, newBalance);
            emit AccountMigrated(account, currentVersion, targetVersion, storedBalance, newBalance);
        }
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {ERC20Upgradeable} from "@openzeppelin-contracts-upgradeable-5.6.1/token/ERC20/ERC20Upgradeable.sol";
import {LibCorporateAction} from "../../../src/lib/LibCorporateAction.sol";
import {LibERC20Storage} from "../../../src/lib/LibERC20Storage.sol";
import {LibTotalSupply} from "../../../src/lib/LibTotalSupply.sol";

/// @dev Test-only subclass of StoxReceiptVault that bypasses
/// `OffchainAssetReceiptVault._update`'s authorizer / freeze checks, so
/// `StoxReceiptVault`'s migration logic can be exercised without the rain.vats
/// auth/freeze setup. `_update` calls `migrateAccount` for both sides and then
/// `ERC20Upgradeable._update` directly.
contract TestStoxReceiptVault is StoxReceiptVault {
    function _update(address from, address to, uint256 amount) internal override {
        // Mirror the StoxReceiptVault._update flow, bypassing the
        // OffchainAssetReceiptVault authorizer/freeze layer.
        LibTotalSupply.fold();

        migrateAccount(from);
        migrateAccount(to);

        ERC20Upgradeable._update(from, to, amount);

        if (from == address(0)) {
            LibTotalSupply.onMint(amount);
        } else if (to == address(0)) {
            LibTotalSupply.onBurn(amount);
        }
    }

    /// Expose ERC20 _update so tests can drive mints/burns/transfers without
    /// going through the vault's deposit/withdraw flow (which has its own
    /// initialization requirements).
    function publicUpdate(address from, address to, uint256 amount) external {
        _update(from, to, amount);
    }

    /// Expose corporate-action scheduling so tests can set up split state
    /// using this vault's storage namespace.
    function publicSchedule(uint256 actionType, uint64 effectiveTime, bytes memory parameters)
        external
        returns (uint256)
    {
        return LibCorporateAction.schedule(actionType, effectiveTime, parameters);
    }

    /// Expose corporate-action cancellation for tests that need to remove a
    /// pending split before its effective time.
    function publicCancel(uint256 actionIndex) external {
        LibCorporateAction.cancel(actionIndex);
    }

    function rawStoredBalance(address account) external view returns (uint256) {
        return LibERC20Storage.underlyingBalance(account);
    }

    /// Expose OZ's raw `_totalSupply` slot. `totalSupply()` is overridden to
    /// the rebase-aware `LibTotalSupply.effectiveTotalSupply()`, so this is the
    /// only way a test can observe the underlying OZ accumulator that
    /// `ERC20Upgradeable._update` mutates.
    function rawTotalSupply() external view returns (uint256) {
        return LibERC20Storage.underlyingTotalSupply();
    }

    function migrationCursor(address account) external view returns (uint256) {
        return LibCorporateAction.getStorage().accountMigrationCursor[account];
    }

    function totalSupplyLatestCursor() external view returns (uint256) {
        return LibCorporateAction.getStorage().totalSupplyLatestCursor;
    }

    function unmigrated(uint256 cursor) external view returns (uint256) {
        return LibCorporateAction.getStorage().unmigrated[cursor];
    }
}

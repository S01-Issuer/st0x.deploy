// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {ERC20Upgradeable} from "@openzeppelin-contracts-upgradeable-5.6.1/token/ERC20/ERC20Upgradeable.sol";
import {LibCorporateAction} from "../../../src/lib/LibCorporateAction.sol";
import {LibERC20Storage} from "../../../src/lib/LibERC20Storage.sol";
import {LibTotalSupply} from "../../../src/lib/LibTotalSupply.sol";

/// @dev Test-only subclass of StoxReceiptVault that bypasses
/// `OffchainAssetReceiptVault._update`'s authorizer / freeze checks. This lets
/// us exercise `StoxReceiptVault`'s migration logic in isolation without
/// standing up the full rain.vats auth/freeze infrastructure (admin grants,
/// authorizer wiring, certify state, etc).
///
/// The test class re-overrides `_update` to call `migrateAccount` for both
/// sides and then call `ERC20Upgradeable._update` directly, skipping the
/// `OffchainAssetReceiptVault._update` middle layer. The migration semantics
/// being tested live entirely in `StoxReceiptVault` and the libraries it calls,
/// so the bypass is faithful for the purpose of these tests.
contract TestStoxReceiptVault is StoxReceiptVault {
    function _update(address from, address to, uint256 amount) internal override {
        // Mirror the production StoxReceiptVault._update flow exactly, only
        // bypassing the OffchainAssetReceiptVault authorizer/freeze layer.
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

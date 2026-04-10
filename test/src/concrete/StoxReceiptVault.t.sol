// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {LibCorporateAction, ACTION_TYPE_STOCK_SPLIT} from "../../../src/lib/LibCorporateAction.sol";
import {LibERC20Storage} from "../../../src/lib/LibERC20Storage.sol";

/// @dev Test-only subclass of StoxReceiptVault that bypasses
/// `OffchainAssetReceiptVault._update`'s authorizer / freeze checks. This lets
/// us exercise `StoxReceiptVault`'s migration logic in isolation without
/// standing up the full ethgild auth/freeze infrastructure (admin grants,
/// authorizer wiring, certify state, etc).
///
/// The test class re-overrides `_update` to call `_migrateAccount` for both
/// sides and then call `ERC20Upgradeable._update` directly, skipping the
/// `OffchainAssetReceiptVault._update` middle layer. The migration semantics
/// being tested live entirely in `StoxReceiptVault` and the libraries it calls,
/// so the bypass is faithful for the purpose of these tests.
contract TestStoxReceiptVault is StoxReceiptVault {
    function _update(address from, address to, uint256 amount) internal override {
        _migrateAccount(from);
        _migrateAccount(to);
        ERC20Upgradeable._update(from, to, amount);
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

    function rawStoredBalance(address account) external view returns (uint256) {
        return LibERC20Storage.getBalance(account);
    }

    function migrationCursor(address account) external view returns (uint256) {
        return LibCorporateAction.getStorage().accountMigrationCursor[account];
    }
}

contract StoxReceiptVaultTest is Test {
    /// Constructor disables initializers on the implementation.
    function testConstructorDisablesInitializers() external {
        StoxReceiptVault impl = new StoxReceiptVault();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(abi.encode(address(1)));
    }
}

/// Integration tests for the corporate-actions hooks added in PR4.
///
/// These tests are the regression guards for `audit/2026-04-07-01/pass1/
/// StoxReceiptVault.md::A03-1` — the CRITICAL inflation bug where mint or
/// transfer to a fresh recipient after a completed split would over-multiply
/// the recipient's balance, minting tokens out of thin air.
contract StoxReceiptVaultMigrationIntegrationTest is Test {
    TestStoxReceiptVault internal vault;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA401);

    function setUp() public {
        vault = new TestStoxReceiptVault();
        vm.warp(1000);
    }

    function _splitParams(int256 multiplier) internal pure returns (bytes memory) {
        return abi.encode(LibDecimalFloat.packLossless(multiplier, 0));
    }

    /// REGRESSION FOR A03-1 (mint pathway).
    /// Mint to a fresh account AFTER a completed 2x split must credit exactly
    /// the minted amount, not 2x the minted amount. The bug previously caused
    /// `balanceOf(alice) == 200` after minting 100.
    function testMintToFreshAccountAfterCompletedSplitDoesNotInflate() external {
        // Pre-existing supply so the split has something to rebase.
        vault.publicUpdate(address(0), BOB, 1000);

        // Schedule and complete a 2x stock split.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);

        // Mint 100 to Alice — a brand new account.
        vault.publicUpdate(address(0), ALICE, 100);

        // Alice should have exactly 100, not 200.
        assertEq(vault.balanceOf(ALICE), 100, "fresh recipient must not over-multiply on mint");
    }

    /// REGRESSION FOR A03-1 (transfer pathway).
    /// Transfer to a fresh recipient after a completed split must credit
    /// exactly the transferred amount.
    function testTransferToFreshRecipientAfterCompletedSplitDoesNotInflate() external {
        // Bob has a pre-existing balance.
        vault.publicUpdate(address(0), BOB, 50);

        // Schedule and complete a 2x stock split.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);

        // After the split, Bob's balance should be 100.
        assertEq(vault.balanceOf(BOB), 100, "Bob's balance should rebase to 100");

        // Bob transfers 100 to Alice (a brand new account).
        vault.publicUpdate(BOB, ALICE, 100);

        // Alice received 100, not 200.
        assertEq(vault.balanceOf(ALICE), 100, "fresh recipient must not over-multiply on transfer");
        // Bob is now empty.
        assertEq(vault.balanceOf(BOB), 0, "Bob should be empty after sending all");
    }

    /// Mint to a fresh account before any splits — sanity check.
    function testMintBeforeAnySplit() external {
        vault.publicUpdate(address(0), ALICE, 100);
        assertEq(vault.balanceOf(ALICE), 100);
    }

    /// Pre-existing holder's balance correctly reflects a completed split.
    function testBalanceOfRebaseOnExistingHolder() external {
        vault.publicUpdate(address(0), BOB, 50);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);
        assertEq(vault.balanceOf(BOB), 100);
    }

    /// After A03-1's fix, a fresh account that gets touched by a zero-amount
    /// transfer (or any interaction) should have its cursor advanced to the
    /// latest completed split.
    function testFreshAccountCursorAdvancesAfterMigration() external {
        vault.publicUpdate(address(0), BOB, 1000);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);

        // Touch Alice via a 0-amount mint. (The publicUpdate path via mint=0
        // doesn't trigger OZ's mint-amount check at this layer.)
        vault.publicUpdate(address(0), ALICE, 0);

        // Alice's cursor should now be 1 (the completed split).
        assertEq(vault.migrationCursor(ALICE), 1, "fresh account cursor must advance");
    }

    /// Two consecutive splits, then mint to a fresh account: still no inflation.
    function testMintFreshAccountAfterTwoCompletedSplits() external {
        vault.publicUpdate(address(0), BOB, 100);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT, 2500, _splitParams(3));
        vm.warp(3000);

        vault.publicUpdate(address(0), ALICE, 100);

        assertEq(vault.balanceOf(ALICE), 100);
    }

    /// Bob existed before the splits and never interacted; his eventual
    /// migration produces the correct rebased balance.
    function testDormantHolderMigratesCorrectly() external {
        vault.publicUpdate(address(0), BOB, 100);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT, 2500, _splitParams(3));
        vm.warp(3000);

        // Force a migration via a touch.
        vault.publicUpdate(BOB, BOB, 0);

        assertEq(vault.balanceOf(BOB), 600, "100 * 2 * 3 = 600");
        assertEq(vault.rawStoredBalance(BOB), 600, "stored balance is rasterized to post-rebase");
        assertEq(vault.migrationCursor(BOB), 2, "cursor advanced to latest split");
    }

    /// Burn from a holder works correctly after a split.
    function testBurnAfterSplit() external {
        vault.publicUpdate(address(0), BOB, 100);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);

        // Bob's effective balance is 200 after the split.
        assertEq(vault.balanceOf(BOB), 200);

        // Burn 50 from Bob.
        vault.publicUpdate(BOB, address(0), 50);
        assertEq(vault.balanceOf(BOB), 150);
    }

    /// AccountMigrated event fires with correct values when a non-zero
    /// account is migrated through a completed split.
    function testAccountMigratedEventEmitted() external {
        vault.publicUpdate(address(0), BOB, 100);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);

        vm.expectEmit(true, false, false, true, address(vault));
        emit StoxReceiptVault.AccountMigrated(BOB, 0, 1, 100, 200);
        // Touch Bob to trigger migration.
        vault.publicUpdate(BOB, BOB, 0);
    }
}

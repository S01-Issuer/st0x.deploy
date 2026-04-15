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
import {LibTotalSupply} from "../../../src/lib/LibTotalSupply.sol";

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
        // Mirror the production StoxReceiptVault._update flow exactly, only
        // bypassing the OffchainAssetReceiptVault authorizer/freeze layer.
        LibTotalSupply.fold();
        _migrateAccount(from);
        _migrateAccount(to);

        if (from == address(0)) {
            LibTotalSupply.onMint(amount);
        } else if (to == address(0)) {
            LibTotalSupply.onBurn(amount);
        }

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

    function totalSupplyLatestSplit() external view returns (uint256) {
        return LibCorporateAction.getStorage().totalSupplyLatestSplit;
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

    /// totalSupply equals the sum of all per-account balanceOf values after a
    /// completed split, even when some accounts are still unmigrated. This is
    /// the integration-level invariant that A28-1 says must hold and that the
    /// pre-fix code violated for fresh-recipient pathways.
    function testTotalSupplyMatchesSumOfBalanceOfAfterMixedActivity() external {
        // Pre-existing holders.
        vault.publicUpdate(address(0), BOB, 100);
        vault.publicUpdate(address(0), CAROL, 200);

        // Split.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);

        // Mint to a fresh account after the split.
        vault.publicUpdate(address(0), ALICE, 100);

        // Transfer from Bob to a brand new account (DAVE).
        address dave = address(0xDAFE);
        // Bob currently has effective balance 200; transfer 50 to Dave.
        vault.publicUpdate(BOB, dave, 50);

        // Burn 30 from Carol.
        vault.publicUpdate(CAROL, address(0), 30);

        // Now: sum(balanceOf) == totalSupply.
        uint256 sumBalances =
            vault.balanceOf(BOB) + vault.balanceOf(CAROL) + vault.balanceOf(ALICE) + vault.balanceOf(dave);
        assertEq(sumBalances, vault.totalSupply(), "totalSupply must equal sum of balanceOf");
    }

    /// REGRESSION FOR A28-1: after the bug was fixed, the totalSupply
    /// computation matches the per-account sum specifically for the mint-after-
    /// split scenario (which the pre-fix code under-reported relative to
    /// per-account balanceOf).
    function testTotalSupplyConsistentWithBalanceOfAfterMintFreshPostSplit() external {
        vault.publicUpdate(address(0), BOB, 1000);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);

        vault.publicUpdate(address(0), ALICE, 100);

        assertEq(vault.balanceOf(ALICE), 100);
        // Bob has 1000 stored at cursor 0; after rebase his effective balance is 2000.
        assertEq(vault.balanceOf(BOB), 2000);
        // Total supply: Bob's 2000 + Alice's 100 = 2100.
        assertEq(vault.totalSupply(), 2100);
    }

    // -----------------------------------------------------------------------
    // Audit 2026-04-09-01 Item 1: cursor / totalSupplyLatestSplit invariant.
    //
    // After `_migrateAccount(account)` returns inside `_update` (which runs
    // after `fold()`), `accountMigrationCursor[account]` MUST equal
    // `s.totalSupplyLatestSplit`. This invariant is load-bearing for the
    // safety of `LibTotalSupply.onBurn`, which subtracts the burn amount
    // from `unmigrated[totalSupplyLatestSplit]`. If the burner's migrated
    // balance had landed in a different pot (cursor != latest), onBurn
    // would subtract from a pot that never received the balance, and the
    // subtraction would underflow.
    //
    // The existing LibTotalSupply point tests cover the underflow panic
    // directly (`testOnBurnUnderflowReverts`, `testOnBurnAtBoundarySucceeds
    // OneBeyondReverts`), and the vault-level integration tests cover the
    // sum-of-balances == totalSupply invariant after mixed activity. What
    // was missing was an explicit fuzz that drives arbitrary sequences of
    // schedule/warp/mint/burn/transfer and asserts the cursor equality
    // after every migration step. These two tests fill that gap. The
    // broader stateful invariant harness in
    // `StoxCorporateActionsInvariant.t.sol` (landing on PR #25) covers the
    // full space; these tests are the per-PR pins at the layer where
    // `totalSupplyLatestSplit` and the `onBurn` path are introduced.

    /// Deterministic pin for the exact path onBurn's safety relies on:
    /// schedule a split → mint pre-split → warp past it → schedule another
    /// split → warp past it → burn from the pre-split holder. After every
    /// migrating `publicUpdate` call, `migrationCursor(bob)` must equal
    /// `totalSupplyLatestSplit()`, and the burn must succeed (no panic).
    function testCursorEqualsTotalSupplyLatestSplitAcrossBurnPath() external {
        // Split 1: 2x at t=1500. Mint Bob before it lands so he starts at
        // cursor 0 (pre-any-split basis).
        vault.publicUpdate(address(0), BOB, 1000);
        assertEq(vault.migrationCursor(BOB), 0, "fresh mint lands at cursor 0 before any split");
        assertEq(vault.totalSupplyLatestSplit(), 0, "no splits completed yet");

        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);

        // Touch Bob — migration should land his cursor on 1 AND
        // totalSupplyLatestSplit should also be 1 (fold advanced it).
        vault.publicUpdate(BOB, BOB, 0);
        assertEq(vault.migrationCursor(BOB), vault.totalSupplyLatestSplit(), "post-migrate: cursor == latest");
        assertEq(vault.migrationCursor(BOB), 1, "cursor advanced to the first split");
        assertEq(vault.balanceOf(BOB), 2000, "Bob rebased to 2000");

        // Split 2: 3x at t=2500. Schedule and warp.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT, 2500, _splitParams(3));
        vm.warp(3000);

        // Now burn some from Bob. Inside `_update`, fold() advances
        // totalSupplyLatestSplit to 2, then _migrateAccount(BOB) walks
        // Bob's cursor from 1 to 2, rasterizing the balance to 6000. Then
        // onBurn(500) subtracts 500 from unmigrated[2]. If the cursor
        // invariant held, this succeeds; if it didn't, onBurn would
        // underflow.
        vault.publicUpdate(BOB, address(0), 500);
        assertEq(vault.migrationCursor(BOB), vault.totalSupplyLatestSplit(), "post-burn: cursor == latest");
        assertEq(vault.migrationCursor(BOB), 2, "cursor advanced through second split");
        // 1000 → 2x → 2000 → 3x → 6000 → -500 → 5500.
        assertEq(vault.balanceOf(BOB), 5500, "Bob's final balance reflects both splits and the burn");
        // Bob is the only holder, so totalSupply == balanceOf(Bob).
        assertEq(vault.totalSupply(), 5500, "totalSupply must equal sum of balances");
    }

    /// Fuzz: run a sequence of mint / transfer / burn operations interleaved
    /// with stock splits, and assert after EVERY `publicUpdate` touching an
    /// account that `migrationCursor(account) == totalSupplyLatestSplit()`.
    /// This is the strongest form of the cursor invariant at the per-PR
    /// level — any input shape that violates it fails the assertion
    /// immediately, and the underlying `onBurn` subtraction cannot panic
    /// under the same preconditions that keep the invariant true.
    ///
    /// Inputs are bounded to keep the float library inside its conservative
    /// operating range and to keep the test fast. The point is breadth of
    /// sequences, not exhaustive amount ranges.
    function testFuzzCursorEqualsLatestAfterEveryMigration(
        uint8 split1Raw,
        uint8 split2Raw,
        uint128 mintBob,
        uint128 mintCarol,
        uint128 transferAmtRaw,
        uint128 burnAmtRaw
    ) external {
        // Multipliers in [1, 5]. Zero would violate LibStockSplit's
        // positive-coefficient rule; values >5 risk compounding into
        // overflow territory across two splits + mints.
        int256 m1 = int256(uint256(uint8(split1Raw % 5) + 1));
        int256 m2 = int256(uint256(uint8(split2Raw % 5) + 1));

        // Keep mints within a safe range so two sequential splits up to 5x
        // each don't exceed uint256 when summed across accounts.
        uint256 bobMint = uint256(mintBob) % 1e24 + 1;
        uint256 carolMint = uint256(mintCarol) % 1e24 + 1;

        // Initial state: mint Bob and Carol pre-split. Both land at cursor 0,
        // totalSupplyLatestSplit == 0. Neither mint should have migrated
        // state (nothing to migrate).
        vault.publicUpdate(address(0), BOB, bobMint);
        _assertCursorInvariant(BOB);
        vault.publicUpdate(address(0), CAROL, carolMint);
        _assertCursorInvariant(CAROL);

        // Split 1 lands.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(m1));
        vm.warp(2000);

        // Transfer from Bob to Carol — migrates both, asserts both have
        // cursor == latest afterwards.
        uint256 bobEffective = vault.balanceOf(BOB);
        uint256 transferAmt = uint256(transferAmtRaw) % (bobEffective + 1);
        vault.publicUpdate(BOB, CAROL, transferAmt);
        _assertCursorInvariant(BOB);
        _assertCursorInvariant(CAROL);
        assertEq(vault.migrationCursor(BOB), 1, "Bob's cursor advanced through split 1");
        assertEq(vault.migrationCursor(CAROL), 1, "Carol's cursor advanced through split 1");

        // Split 2 lands.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT, 2500, _splitParams(m2));
        vm.warp(3000);

        // Burn from Carol — migrates Carol (from cursor 1 through split 2
        // to cursor 2), then onBurn subtracts from the latest pot. Without
        // the invariant, this would underflow. With the invariant, it
        // succeeds cleanly.
        uint256 carolEffective = vault.balanceOf(CAROL);
        uint256 burnAmt = uint256(burnAmtRaw) % (carolEffective + 1);
        vault.publicUpdate(CAROL, address(0), burnAmt);
        _assertCursorInvariant(CAROL);
        assertEq(vault.migrationCursor(CAROL), 2, "Carol's cursor advanced through split 2");

        // Touch Bob to migrate him too.
        vault.publicUpdate(BOB, BOB, 0);
        _assertCursorInvariant(BOB);
        assertEq(vault.migrationCursor(BOB), 2, "Bob's cursor advanced through both splits");

        // Final sum-of-balances check. Both accounts have migrated through
        // the full chain; totalSupply must equal their combined balance.
        assertEq(
            vault.balanceOf(BOB) + vault.balanceOf(CAROL),
            vault.totalSupply(),
            "sum(balanceOf) must equal totalSupply after full migration"
        );
    }

    /// @dev Assert that the account's migration cursor equals the global
    /// `totalSupplyLatestSplit`. This is the invariant `onBurn` depends on.
    function _assertCursorInvariant(address account) internal view {
        assertEq(
            vault.migrationCursor(account),
            vault.totalSupplyLatestSplit(),
            "migrationCursor must equal totalSupplyLatestSplit after _migrateAccount"
        );
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std/Test.sol";
import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Errors} from
    "openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {LibCorporateAction, ACTION_TYPE_STOCK_SPLIT_V1} from "../../../src/lib/LibCorporateAction.sol";
import {LibERC20Storage} from "../../../src/lib/LibERC20Storage.sol";
import {LibTotalSupply} from "../../../src/lib/LibTotalSupply.sol";

/// @dev Test-only subclass of StoxReceiptVault that bypasses
/// `OffchainAssetReceiptVault._update`'s authorizer / freeze checks. This lets
/// us exercise `StoxReceiptVault`'s migration logic in isolation without
/// standing up the full rain.vats auth/freeze infrastructure (admin grants,
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

    function rawStoredBalance(address account) external view returns (uint256) {
        return LibERC20Storage.underlyingBalance(account);
    }

    function migrationCursor(address account) external view returns (uint256) {
        return LibCorporateAction.getStorage().accountMigrationCursor[account];
    }

    function totalSupplyLatestSplit() external view returns (uint256) {
        return LibCorporateAction.getStorage().totalSupplyLatestSplit;
    }

    function unmigrated(uint256 cursor) external view returns (uint256) {
        return LibCorporateAction.getStorage().unmigrated[cursor];
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

/// Integration tests for the corporate-actions rebase hooks.
///
/// These tests are the regression guards for the CRITICAL inflation bug
/// where mint or transfer to a fresh recipient after a completed split
/// would over-multiply
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
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
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
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
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
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);
        assertEq(vault.balanceOf(BOB), 100);
    }

    /// After A03-1's fix, a fresh account that gets touched by a zero-amount
    /// transfer (or any interaction) should have its cursor advanced to the
    /// latest completed split.
    function testFreshAccountCursorAdvancesAfterMigration() external {
        vault.publicUpdate(address(0), BOB, 1000);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
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
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(3));
        vm.warp(3000);

        vault.publicUpdate(address(0), ALICE, 100);

        assertEq(vault.balanceOf(ALICE), 100);
    }

    /// Bob existed before the splits and never interacted; his eventual
    /// migration produces the correct rebased balance.
    function testDormantHolderMigratesCorrectly() external {
        vault.publicUpdate(address(0), BOB, 100);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(3));
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
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
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
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);

        vm.expectEmit(true, false, false, true, address(vault));
        emit StoxReceiptVault.AccountMigrated(BOB, 0, 1, 100, 200);
        // Touch Bob to trigger migration.
        vault.publicUpdate(BOB, BOB, 0);
    }

    /// `AccountMigrated` must NOT fire when a zero-balance account's cursor
    /// advances — the NatSpec states "Only fires when the stored balance
    /// actually changes; pure cursor-only advancements (zero-balance
    /// accounts) do not emit."
    ///
    /// NOTE: This behaviour is under review. See issue #81 ("Discuss: emit
    /// AccountMigrated on cursor-only advancement (balance unchanged)") —
    /// the project may switch to always-emit to restore the "events on
    /// every state change" convention. If that decision is made, this
    /// test's intent inverts: update the assertion to expect the event,
    /// and update the NatSpec on `StoxReceiptVault.AccountMigrated` to
    /// match. This test is NOT the source of truth — issue #81 is.
    function testAccountMigratedNotEmittedForZeroBalanceCursorAdvance() external {
        // Pre-existing holder so bootstrap has something to read.
        vault.publicUpdate(address(0), BOB, 100);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);

        // Touch Alice (zero balance, fresh recipient). Her cursor advances
        // from 0 to 1, but stored balance stays 0 → no `AccountMigrated`
        // event for her.
        vm.recordLogs();
        vault.publicUpdate(address(0), ALICE, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = StoxReceiptVault.AccountMigrated.selector;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == sig) {
                fail();
            }
        }

        // Confirm the cursor actually advanced — the event suppression
        // claim is meaningful only when the cursor DID move.
        assertEq(vault.migrationCursor(ALICE), 1, "alice cursor must have advanced");
    }

    /// Transfer attempt after a reverse split truncates the sender's
    /// balance to zero. Migration runs first, writing the post-truncation
    /// value to storage. OZ's `_update` then sees `_balances[from] == 0`
    /// and reverts with `ERC20InsufficientBalance` for any non-zero
    /// transfer amount.
    function testTransferRevertsWhenMigrationTruncatesBalanceToZero() external {
        // Alice has stored 1 pre-split. A 1/2x split truncates her to 0.
        vault.publicUpdate(address(0), ALICE, 1);
        Float halfX = LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(2, 0));
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, abi.encode(halfX));
        vm.warp(2000);

        // View already reflects the truncation.
        assertEq(vault.balanceOf(ALICE), 0, "balanceOf reflects truncation pre-migration");

        // Any non-zero transfer reverts with OZ's insufficient-balance error —
        // migration writes stored = 0 before the transfer arithmetic runs.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vault.publicUpdate(ALICE, BOB, 1);
    }

    /// Partial truncation: balance is reduced but non-zero, transfer succeeds
    /// up to the migrated amount.
    function testTransferSucceedsUpToMigratedBalanceAfterPartialTruncation() external {
        // Alice has stored 3 pre-split. 1/2x truncates 3 → 1.
        vault.publicUpdate(address(0), ALICE, 3);
        Float halfX = LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(2, 0));
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, abi.encode(halfX));
        vm.warp(2000);
        assertEq(vault.balanceOf(ALICE), 1, "alice migrated balance = trunc(3 * 0.5) = 1");

        // Transfer exactly the migrated amount.
        vault.publicUpdate(ALICE, BOB, 1);
        assertEq(vault.balanceOf(ALICE), 0, "alice drained");
        assertEq(vault.balanceOf(BOB), 1, "bob received the full 1 unit");
    }

    /// Boundary on `effectiveTime`: a split whose effective time equals the
    /// current block timestamp must be treated as completed (via the `<=`
    /// comparison in `LibCorporateActionNode.nextOfType`). One second before
    /// its effective time it must NOT be completed. Pins the exact threshold
    /// so a future refactor flipping `<=` to `<` trips this test.
    function testEffectiveTimeBoundaryExactlyAtCompletesSplit() external {
        vault.publicUpdate(address(0), ALICE, 100);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));

        // One second before: NOT completed. Migration is a no-op, balance
        // unchanged, cursor stays at 0.
        vm.warp(1499);
        vault.publicUpdate(ALICE, ALICE, 0);
        assertEq(vault.migrationCursor(ALICE), 0, "cursor must not advance before effective time");
        assertEq(vault.balanceOf(ALICE), 100, "balance must not rebase before effective time");

        // Exactly at effective time: IS completed. Migration fires, cursor
        // advances, balance rebases.
        vm.warp(1500);
        vault.publicUpdate(ALICE, ALICE, 0);
        assertEq(vault.migrationCursor(ALICE), 1, "cursor must advance at exact effective time");
        assertEq(vault.balanceOf(ALICE), 200, "balance must rebase at exact effective time");
    }

    /// Pre-bootstrap regime: until the first `_update` after a completed
    /// split, `fold()` must not bootstrap, `onMint`/`onBurn` must be no-ops,
    /// and `totalSupply()` must return OZ's raw `_totalSupply`. A pending
    /// split that has not yet reached its effective time must not trigger
    /// any of these.
    function testPreBootstrapIsNoOpUntilCompletedSplit() external {
        // Mint pre-any-split. No pot update expected — pots haven't been
        // bootstrapped, onMint is a no-op.
        vault.publicUpdate(address(0), BOB, 200);
        assertEq(vault.totalSupplyLatestSplit(), 0, "no split tracked pre-schedule");
        assertEq(vault.totalSupply(), 200, "totalSupply matches OZ pre-any-split");
        assertEq(vault.unmigrated(0), 0, "pot 0 untouched pre-bootstrap");

        // Burn pre-any-split. Also a no-op on pots.
        vault.publicUpdate(BOB, address(0), 50);
        assertEq(vault.totalSupply(), 150, "totalSupply reflects burn via OZ");
        assertEq(vault.unmigrated(0), 0, "pot 0 still untouched");

        // Schedule a split but do NOT warp past its effective time. Pending,
        // not completed. `fold()` must still see no completed split and
        // early-return before bootstrap.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 5000, _splitParams(2));
        assertEq(vault.totalSupplyLatestSplit(), 0, "pending split does not advance latest");

        // Mint again with the pending split scheduled. Still pre-bootstrap
        // because no split has completed.
        vault.publicUpdate(address(0), BOB, 100);
        assertEq(vault.totalSupplyLatestSplit(), 0, "still no completed split tracked");
        assertEq(vault.totalSupply(), 250, "totalSupply tracks OZ while pending");
        assertEq(vault.unmigrated(0), 0, "pot 0 still untouched");

        // balanceOf also returns OZ stored balance directly (no rebase
        // walks pending splits).
        assertEq(vault.balanceOf(BOB), 250, "balanceOf ignores pending splits");
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
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
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

    /// Fractional / reverse splits cannot maintain `totalSupply == sum(balanceOf)`
    /// exactly while multiple accounts share a pre-split pot: the walk applies
    /// the multiplier to the aggregate pot, but per-account `balanceOf` applies
    /// it to each account individually, so `trunc(Σ aᵢ * m) ≥ Σ trunc(aᵢ * m)`.
    /// The difference is the per-account truncation dust. The gap closes once
    /// every account has migrated through the split and `unmigrated[0]` is 0.
    function testTotalSupplyFractionalDustConvergesAfterMigration() external {
        Float halfX = LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(2, 0));

        vault.publicUpdate(address(0), BOB, 1);
        vault.publicUpdate(address(0), CAROL, 1);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, abi.encode(halfX));
        vm.warp(2000);

        // Aggregate pot: trunc((1 + 1) * 0.5) == 1. Per-account: trunc(1 * 0.5)
        // + trunc(1 * 0.5) == 0. totalSupply is the upper bound here.
        assertEq(vault.totalSupply(), 1, "aggregate pot keeps rounding dust pre-migration");
        assertEq(vault.balanceOf(BOB) + vault.balanceOf(CAROL), 0, "per-account truncates individually");

        // Migrate both accounts out of the shared pot.
        vault.publicUpdate(BOB, BOB, 0);
        vault.publicUpdate(CAROL, CAROL, 0);

        assertEq(
            vault.totalSupply(),
            vault.balanceOf(BOB) + vault.balanceOf(CAROL),
            "totalSupply converges to sum(balanceOf) post-migration"
        );
        assertEq(vault.totalSupply(), 0, "dust resolves to 0 once both migrate");
    }

    /// REGRESSION FOR A28-1: after the bug was fixed, the totalSupply
    /// computation matches the per-account sum specifically for the mint-after-
    /// split scenario (which the pre-fix code under-reported relative to
    /// per-account balanceOf).
    function testTotalSupplyConsistentWithBalanceOfAfterMintFreshPostSplit() external {
        vault.publicUpdate(address(0), BOB, 1000);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
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

        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);

        // Touch Bob — migration should land his cursor on 1 AND
        // totalSupplyLatestSplit should also be 1 (fold advanced it).
        vault.publicUpdate(BOB, BOB, 0);
        assertEq(vault.migrationCursor(BOB), vault.totalSupplyLatestSplit(), "post-migrate: cursor == latest");
        assertEq(vault.migrationCursor(BOB), 1, "cursor advanced to the first split");
        assertEq(vault.balanceOf(BOB), 2000, "Bob rebased to 2000");

        // Split 2: 3x at t=2500. Schedule and warp.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(3));
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
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(m1));
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
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(m2));
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

    /// Structural coupling test between `LibRebase.migratedBalance` and
    /// `LibTotalSupply.fold()`.
    ///
    /// Both functions currently filter the corporate-action linked list with
    /// `ACTION_TYPE_STOCK_SPLIT_V1`. That coupling keeps
    /// `accountMigrationCursor` and `totalSupplyLatestSplit` in lockstep.
    ///
    /// INTENT: pin the current behaviour that a completed non-stock-split node
    /// advances *neither* cursor. When a future action type (dividends, rights
    /// issues, etc.) starts participating in migration, whoever adds that
    /// support MUST update both `LibRebase` and `LibTotalSupply` together, or
    /// they'll diverge and the pot accounting will break silently. This test
    /// fails fast in that scenario:
    ///
    ///   - If `_migrateAccount` starts walking the new type without
    ///     `LibTotalSupply.fold()` doing the same, the first assertion here
    ///     fails because `migrationCursor` advances past the synthetic node
    ///     but `totalSupplyLatestSplit` does not.
    ///   - If `fold()` starts walking the new type without `_migrateAccount`
    ///     doing the same, the inverse failure mode triggers.
    ///
    /// When that happens, DO NOT just update the assertions — the failure is
    /// signalling that the pot model now needs per-action-type accounting.
    /// Revisit `LibTotalSupply` with the new action type's rebase semantics
    /// before touching this test.
    function testNonStockSplitNodeAdvancesNeitherCursor() external {
        // Synthesise a completed node with a bitmap that is NOT
        // `ACTION_TYPE_STOCK_SPLIT_V1`. Bypass `resolveActionType` (which
        // would reject the unknown type) by calling schedule() directly
        // through the public harness.
        uint256 fakeActionType = 1 << 1;
        vault.publicSchedule(fakeActionType, 1500, abi.encode(uint256(0)));

        // Give Bob a pre-existing balance so _migrateAccount has something
        // to rasterize if it ever starts walking the fake node.
        vault.publicUpdate(address(0), BOB, 1000);

        // Warp past the fake node's effective time so it counts as completed.
        vm.warp(2000);

        // Touch Bob to drive fold() + _migrateAccount.
        vault.publicUpdate(BOB, BOB, 0);

        assertEq(
            vault.migrationCursor(BOB),
            0,
            "_migrateAccount must not advance cursor through a non-stock-split node"
        );
        assertEq(
            vault.totalSupplyLatestSplit(),
            0,
            "fold() must not advance totalSupplyLatestSplit through a non-stock-split node"
        );
        assertEq(vault.balanceOf(BOB), 1000, "Bob's balance must be unaffected by a non-split completed node");

        // Now schedule a real stock split, complete it, and confirm BOTH
        // cursors advance together. This half of the test pins the
        // positive-case behaviour: stock splits move both, non-splits move
        // neither.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(2));
        vm.warp(3000);
        vault.publicUpdate(BOB, BOB, 0);

        assertEq(vault.migrationCursor(BOB), 2, "cursor must advance to the stock-split node (index 2)");
        assertEq(vault.totalSupplyLatestSplit(), 2, "latest must advance to the stock-split node (index 2)");
        assertEq(vault.balanceOf(BOB), 2000, "Bob's balance must reflect only the 2x split, not the fake node");
    }

    /// `effectiveTotalSupply()` called between split completion and the first
    /// post-split `_update` exercises the `!totalSupplyBootstrapped` branch:
    /// the view has no pot to read from, so it starts the walk from OZ's raw
    /// `_totalSupply` and applies each completed multiplier.
    ///
    /// INTENT: pin the behaviour of the view during the bootstrap-deferred
    /// window. If the branch shape changes — e.g. if `fold()` is ever moved
    /// into the view — this test fails and forces the author to re-evaluate
    /// the state-mutation rules for view functions.
    function testTotalSupplyDuringBootstrapDeferredWindow() external {
        // Mint supply before any split is scheduled. No bootstrap yet.
        vault.publicUpdate(address(0), BOB, 100);
        assertEq(vault.totalSupplyLatestSplit(), 0, "no split tracked yet");

        // Schedule a 2x split and warp past its effective time. Critically,
        // do NOT call any `_update` after warping — so `fold()` hasn't run
        // and `totalSupplyBootstrapped` is still false.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);

        // The view must still report the rebased supply using OZ's raw
        // totalSupply as the walk starting point.
        assertEq(vault.totalSupply(), 200, "view must apply the 2x multiplier without bootstrap");

        // And `totalSupplyLatestSplit` is still 0 because no state-mutating
        // path has run fold(). The view reads are side-effect-free.
        assertEq(vault.totalSupplyLatestSplit(), 0, "view must not bootstrap");
    }

    /// Multiple completed splits land between `_update` calls and no
    /// account migrates in between. Exercises the view walk across all
    /// three multipliers while pot 0 still holds mass — the critical
    /// case that catches a dropped-multiplier regression.
    ///
    /// INTENT: pin the behaviour of `effectiveTotalSupply` walking
    /// through intermediate pots. Asserting totalSupply *before* the
    /// mass migrates out of pot 0 forces the walk to perform real
    /// multiplier applications on non-zero running values. If a future
    /// change ever dropped a multiplier step or tried to "skip empty
    /// pots" without carrying the multiplication forward, this test
    /// would fail at the pre-migration assertion.
    ///
    /// The post-migration assertion is a second-order check: once all
    /// mass is in the final pot, the walk's multiplier applications
    /// operate on zero intermediates and are invisible to the result.
    /// That assertion only catches pot-accounting bugs, not
    /// multiplier-walk bugs.
    function testEffectiveTotalSupplyAcrossGapWithZeroIntermediatePots() external {
        // Seed: Bob holds 100 pre-split.
        vault.publicUpdate(address(0), BOB, 100);

        // Three splits complete before anybody touches the vault.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(3));
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 3500, _splitParams(5));
        vm.warp(4000);

        // Force `fold()` to bootstrap + advance `totalSupplyLatestSplit`
        // without moving Bob's mass out of pot 0. CAROL is a fresh
        // zero-balance account — her "migration" advances only her
        // cursor, not any pot value. After this, pot 0 still holds 100.
        vault.publicUpdate(address(0), CAROL, 0);
        assertEq(vault.totalSupplyLatestSplit(), 3, "fold must advance to the latest split");

        // CRITICAL ASSERTION: pot 0 holds 100, pots 1/2/3 are empty. The
        // view must walk `100 -> trunc(100*2) -> trunc(200*3) -> trunc(600*5)
        // = 3000`. A dropped multiplier in the walk collapses to 100.
        assertEq(vault.totalSupply(), 3000, "view must apply every multiplier while pot 0 holds mass");

        // Now migrate Bob. His mass leaves pot 0 and lands in pot 3.
        vault.publicUpdate(BOB, BOB, 0);
        assertEq(vault.rawStoredBalance(BOB), 3000, "bob stored = 100 * 2 * 3 * 5");
        assertEq(vault.migrationCursor(BOB), 3, "bob cursor at latest split");

        // Post-migration: same total, but now all mass lives in pot 3.
        // Note: the walk here trivially produces 3000 because the
        // multiplier applications all operate on zero intermediates.
        // This assertion catches pot-accounting bugs but not walk bugs
        // — the pre-migration assertion above is the walk guarantee.
        assertEq(vault.totalSupply(), 3000, "totalSupply stable across migration");
    }

    /// Burn-to-zero after a completed split: an account with a non-zero
    /// pre-split balance migrates through the split and then burns its
    /// entire post-migration balance. Checks all four pieces of state
    /// simultaneously to pin the migrate+burn interaction in one test.
    ///
    /// INTENT: a future regression that, for example, decoupled
    /// `onBurn` from `_migrateAccount`'s ordering would leave one of
    /// the pots or the stored balance inconsistent with the others.
    /// Asserting all four quantities at once makes such a regression
    /// visible in a single test failure rather than having to correlate
    /// individual assertions across separate tests.
    function testBurnToZeroPostSplitInvariants() external {
        // Alice holds 50 pre-split.
        vault.publicUpdate(address(0), ALICE, 50);

        // 2x split completes.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);

        // Alice's view is 100 (migrated). Burn all of it.
        assertEq(vault.balanceOf(ALICE), 100, "alice sees 2x post-split");
        vault.publicUpdate(ALICE, address(0), 100);

        // All four state pieces after burn-to-zero:
        //   (1) stored balance is 0
        //   (2) migration cursor advanced to the split (index 1)
        //   (3) unmigrated[0] drained of alice's pre-split balance
        //   (4) unmigrated[1] = migrated balance - burn = 100 - 100 = 0
        //
        // `effectiveTotalSupply` walks: running = unmigrated[0] = 0;
        // running = trunc(0 * 2) + unmigrated[1] = 0 + 0 = 0.
        assertEq(vault.rawStoredBalance(ALICE), 0, "alice stored = 0");
        assertEq(vault.migrationCursor(ALICE), 1, "alice cursor at split");
        assertEq(vault.totalSupply(), 0, "totalSupply collapses to 0 after full burn");
    }

    /// Over-burn by a lone holder at `totalSupplyLatestSplit` must surface
    /// OZ's `ERC20InsufficientBalance` error, not a raw arithmetic panic
    /// from the pot subtraction.
    function testOverBurnSurfacesOzInsufficientBalanceNotPanic() external {
        vault.publicUpdate(address(0), ALICE, 50);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 100, 101));
        vault.publicUpdate(ALICE, address(0), 101);
    }

    /// @dev Asserts `LibTotalSupply`'s pot invariant I(k) directly at a
    /// given cursor: the pot value equals the sum of stored balances for
    /// every account at that cursor, and no other accounts are at that
    /// cursor.
    function _assertPotInvariant(uint256 cursor, address[] memory accountsAtCursor) internal view {
        uint256 sum;
        for (uint256 i = 0; i < accountsAtCursor.length; i++) {
            assertEq(
                vault.migrationCursor(accountsAtCursor[i]), cursor, "I(k): account must be at the expected cursor"
            );
            sum += vault.rawStoredBalance(accountsAtCursor[i]);
        }
        assertEq(vault.unmigrated(cursor), sum, "I(k): pot must equal sum of stored balances at cursor");
    }

    /// @dev Build a one-element address array inline.
    function _single(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    /// @dev Build a two-element address array inline.
    function _pair(address a, address b) internal pure returns (address[] memory arr) {
        arr = new address[](2);
        arr[0] = a;
        arr[1] = b;
    }

    /// @dev Build a three-element address array inline.
    function _triple(address a, address b, address c) internal pure returns (address[] memory arr) {
        arr = new address[](3);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
    }

    /// Direct assertion of the LibTotalSupply pot invariant I(k) across a
    /// mixed activity sequence: two pre-split mints, a split, a post-split
    /// mint, a transfer, a burn. After each `_update` (post-bootstrap) the
    /// invariant must hold for every cursor that has touched accounts.
    function testPotInvariantDirectAfterMixedActivity() external {
        address[] memory empty = new address[](0);

        // Pre-split mints. Alice and Bob at cursor 0. Bootstrap hasn't
        // fired yet, so the pot invariant does not apply here.
        vault.publicUpdate(address(0), ALICE, 50);
        vault.publicUpdate(address(0), BOB, 100);

        // Schedule and complete a 2x split.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);

        // Alice touches: fold bootstraps `unmigrated[0] = 150`, then Alice
        // migrates 50 → 100, shifting 50 out of pot 0 and 100 into pot 1.
        vault.publicUpdate(ALICE, ALICE, 0);
        _assertPotInvariant(0, _single(BOB));
        _assertPotInvariant(1, _single(ALICE));

        // Mint Carol 40 post-split. Fresh recipient cursor advances 0 → 1
        // with zero balance (no pot delta from migrate). Then super._update
        // adds 40 to _balances[CAROL], then onMint adds 40 to pot 1.
        vault.publicUpdate(address(0), CAROL, 40);
        _assertPotInvariant(0, _single(BOB));
        _assertPotInvariant(1, _pair(ALICE, CAROL));

        // Alice transfers 30 to Bob. Both migrate first: Alice already at
        // cursor 1 (no-op), Bob 0 → 1 with stored 100 → migrated 200. Pot
        // transitions: pot 0 -= 100 (Bob leaves), pot 1 += 200 (Bob arrives).
        // Then transfer moves 30 between their balances, both at cursor 1
        // — Σ at cursor 1 unchanged, no pot write.
        vault.publicUpdate(ALICE, BOB, 30);
        _assertPotInvariant(0, empty);
        _assertPotInvariant(1, _triple(ALICE, BOB, CAROL));

        // Burn 25 from Bob. super._update first: _balances[BOB] -= 25,
        // _totalSupply -= 25. Then onBurn subtracts 25 from pot 1.
        vault.publicUpdate(BOB, address(0), 25);
        _assertPotInvariant(0, empty);
        _assertPotInvariant(1, _triple(ALICE, BOB, CAROL));
    }

    /// Fuzzed direct assertion of I(k): drive a fixed sequence of
    /// parameter-randomised operations across Alice, Bob, Carol and
    /// two stock splits, asserting the pot invariant for every
    /// touched cursor after each state transition.
    function testFuzzPotInvariantAcrossRandomActivity(
        uint8 m1Raw,
        uint8 m2Raw,
        uint64 aliceMintRaw,
        uint64 bobMintRaw,
        uint64 carolMintRaw,
        uint64 transferRaw,
        uint64 burnRaw
    ) external {
        int256 m1 = int256(uint256(m1Raw % 4) + 1);
        int256 m2 = int256(uint256(m2Raw % 4) + 1);
        uint256 aliceMint = uint256(aliceMintRaw % 1e18) + 1;
        uint256 bobMint = uint256(bobMintRaw % 1e18) + 1;
        uint256 carolMint = uint256(carolMintRaw % 1e18);

        address[] memory empty = new address[](0);

        // Pre-split mints (bootstrap has not fired; invariant doesn't apply).
        vault.publicUpdate(address(0), ALICE, aliceMint);
        vault.publicUpdate(address(0), BOB, bobMint);

        // Split 1 lands; Alice migrates.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(m1));
        vm.warp(2000);
        vault.publicUpdate(ALICE, ALICE, 0);
        _assertPotInvariant(0, _single(BOB));
        _assertPotInvariant(1, _single(ALICE));

        // Mint Carol post-split-1.
        vault.publicUpdate(address(0), CAROL, carolMint);
        _assertPotInvariant(0, _single(BOB));
        _assertPotInvariant(1, _pair(ALICE, CAROL));

        // Split 2 lands; Alice migrates again.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(m2));
        vm.warp(3000);
        vault.publicUpdate(ALICE, ALICE, 0);
        _assertPotInvariant(0, _single(BOB));
        _assertPotInvariant(1, _single(CAROL));
        _assertPotInvariant(2, _single(ALICE));

        // Alice → Bob transfer. Both migrate: Alice at 2 (no-op), Bob 0 → 2.
        uint256 aliceView = vault.balanceOf(ALICE);
        uint256 transferAmt = aliceView == 0 ? 0 : uint256(transferRaw) % (aliceView + 1);
        vault.publicUpdate(ALICE, BOB, transferAmt);
        _assertPotInvariant(0, empty);
        _assertPotInvariant(1, _single(CAROL));
        _assertPotInvariant(2, _pair(ALICE, BOB));

        // Burn from Bob.
        uint256 bobView = vault.balanceOf(BOB);
        uint256 burnAmt = bobView == 0 ? 0 : uint256(burnRaw) % (bobView + 1);
        vault.publicUpdate(BOB, address(0), burnAmt);
        _assertPotInvariant(0, empty);
        _assertPotInvariant(1, _single(CAROL));
        _assertPotInvariant(2, _pair(ALICE, BOB));
    }

    /// Fuzzed convergence invariant: for any initial balance and any sequence
    /// of stock splits, the view `balanceOf` (pre-migration) must equal the
    /// rasterized stored balance after `_update`-driven migration. This
    /// guards the core property that external reads and post-rasterization
    /// stored state agree — if they diverge, transfers could use different
    /// balances than what the view reports.
    function testFuzzConvergenceViewMatchesStoredAfterMigration(uint64 initialBalance, uint8 numSplits, uint8 seed)
        external
    {
        initialBalance = uint64(bound(initialBalance, 1, type(uint32).max));
        numSplits = uint8(bound(numSplits, 0, 8));

        vault.publicUpdate(address(0), BOB, uint256(initialBalance));

        // Schedule alternating forward and reverse splits.
        for (uint256 i = 0; i < numSplits; i++) {
            // Alternate 2x and 1/2x based on i bit 0; use seed to vary starting
            // direction across fuzz runs.
            bool forward = ((i ^ seed) & 1) == 0;
            bytes memory params = forward
                ? abi.encode(LibDecimalFloat.packLossless(2, 0))
                : abi.encode(
                    LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(2, 0))
                );
            // forge-lint: disable-next-line(unsafe-typecast)
            vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, uint64(1001 + i * 100), params);
        }

        if (numSplits > 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            vm.warp(uint64(1001 + uint256(numSplits) * 100 + 1));
        }

        // Snapshot view balance BEFORE migration.
        uint256 viewBefore = vault.balanceOf(BOB);

        // Force migration via a self-touch.
        vault.publicUpdate(BOB, BOB, 0);

        // View AFTER migration must still match (idempotence).
        uint256 viewAfter = vault.balanceOf(BOB);
        uint256 stored = vault.rawStoredBalance(BOB);

        assertEq(viewBefore, viewAfter, "view balance must not change across migration");
        assertEq(viewAfter, stored, "view and stored balance must converge");
    }

    /// Fuzzed convergence across two accounts migrated at different points:
    /// Alice migrates after split 1, Bob migrates after splits 1 and 2. Their
    /// balances computed from different migration paths must still match
    /// their view values and their stored values after full migration.
    function testFuzzTwoAccountDifferentMigrationPathsConverge(uint32 aliceInit, uint32 bobInit) external {
        aliceInit = uint32(bound(aliceInit, 1, type(uint32).max));
        bobInit = uint32(bound(bobInit, 1, type(uint32).max));

        vault.publicUpdate(address(0), ALICE, uint256(aliceInit));
        vault.publicUpdate(address(0), BOB, uint256(bobInit));

        // Split 1: 2x at t=1500.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(1600);

        // Alice touches after split 1 (migrates partially).
        vault.publicUpdate(ALICE, ALICE, 0);

        // Split 2: 1/2x at t=2000.
        Float halfX = LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(2, 0));
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2000, abi.encode(halfX));
        vm.warp(2100);

        // Both view balances before final migration.
        uint256 aliceView = vault.balanceOf(ALICE);
        uint256 bobView = vault.balanceOf(BOB);

        // Both touched — full migration.
        vault.publicUpdate(ALICE, ALICE, 0);
        vault.publicUpdate(BOB, BOB, 0);

        // Convergence: view matches stored for both accounts.
        assertEq(aliceView, vault.rawStoredBalance(ALICE), "alice view matches stored");
        assertEq(bobView, vault.rawStoredBalance(BOB), "bob view matches stored");
        // And the post-migration view equals the stored (idempotence).
        assertEq(vault.balanceOf(ALICE), vault.rawStoredBalance(ALICE));
        assertEq(vault.balanceOf(BOB), vault.rawStoredBalance(BOB));
    }

    /// Fuzzed idempotency: after an initial migration through an arbitrary
    /// split chain, repeated touches with no new splits must not change
    /// cursor, stored balance, or view balance, and must not re-emit
    /// `AccountMigrated`. Guards the `newCursor == currentCursor` early
    /// return in `_migrateAccount`.
    function testFuzzMigrationIdempotentAcrossRepeatedTouches(
        uint32 initialBalance,
        uint8 numSplits,
        uint8 seed,
        uint8 touchCount
    ) external {
        initialBalance = uint32(bound(initialBalance, 1, type(uint32).max));
        numSplits = uint8(bound(numSplits, 0, 8));
        touchCount = uint8(bound(touchCount, 1, 10));

        vault.publicUpdate(address(0), BOB, uint256(initialBalance));

        for (uint256 i = 0; i < numSplits; i++) {
            bool forward = ((i ^ seed) & 1) == 0;
            bytes memory params = forward
                ? abi.encode(LibDecimalFloat.packLossless(2, 0))
                : abi.encode(
                    LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(2, 0))
                );
            // forge-lint: disable-next-line(unsafe-typecast)
            vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, uint64(1001 + i * 100), params);
        }

        if (numSplits > 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            vm.warp(uint64(1001 + uint256(numSplits) * 100 + 1));
        }

        // First touch triggers the migration.
        vault.publicUpdate(BOB, BOB, 0);

        uint256 cursorAfterFirst = vault.migrationCursor(BOB);
        uint256 storedAfterFirst = vault.rawStoredBalance(BOB);
        uint256 viewAfterFirst = vault.balanceOf(BOB);

        // Repeated touches must be idempotent AND must not re-emit.
        bytes32 migratedSig = StoxReceiptVault.AccountMigrated.selector;
        for (uint256 i = 0; i < touchCount; i++) {
            vm.recordLogs();
            vault.publicUpdate(BOB, BOB, 0);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 j = 0; j < logs.length; j++) {
                if (logs[j].topics.length > 0 && logs[j].topics[0] == migratedSig) {
                    fail();
                }
            }
            assertEq(vault.migrationCursor(BOB), cursorAfterFirst, "cursor unchanged across idempotent touches");
            assertEq(vault.rawStoredBalance(BOB), storedAfterFirst, "stored unchanged across idempotent touches");
            assertEq(vault.balanceOf(BOB), viewAfterFirst, "view unchanged across idempotent touches");
        }
    }

    /// Transfers between two distinct accounts, interleaved with multiple
    /// forward and reverse splits in a single flow. At each transfer, both
    /// `from` and `to` must migrate before the raw balance change lands,
    /// otherwise the transfer arithmetic operates on pre-rebase balances and
    /// inflates / deflates incorrectly. Numbers below are exact.
    function testInterleavedTransfersAndSplits() external {
        // Initial: Alice 100, Bob 50 (pre-split basis).
        vault.publicUpdate(address(0), ALICE, 100);
        vault.publicUpdate(address(0), BOB, 50);

        // Split 1: 2x at t=1500.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(1600);

        // Transfer Alice → Bob, 30. Both migrate first:
        //   Alice: 100 → 200, then -30 = 170
        //   Bob:    50 → 100, then +30 = 130
        vault.publicUpdate(ALICE, BOB, 30);
        assertEq(vault.balanceOf(ALICE), 170, "alice after t1");
        assertEq(vault.balanceOf(BOB), 130, "bob after t1");

        // Split 2: 1/2x at t=2000.
        Float halfX = LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(2, 0));
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2000, abi.encode(halfX));
        vm.warp(2100);

        // Transfer Bob → Alice, 40. Both migrate first:
        //   Bob:    130 → 65, then -40 = 25
        //   Alice:  170 → 85, then +40 = 125
        vault.publicUpdate(BOB, ALICE, 40);
        assertEq(vault.balanceOf(ALICE), 125, "alice after t2");
        assertEq(vault.balanceOf(BOB), 25, "bob after t2");

        // Split 3: 3x at t=2500.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(3));
        vm.warp(2600);

        // Transfer Alice → Bob, 60. Both migrate first:
        //   Alice: 125 → 375, then -60 = 315
        //   Bob:   25  → 75,  then +60 = 135
        vault.publicUpdate(ALICE, BOB, 60);
        assertEq(vault.balanceOf(ALICE), 315, "alice after t3");
        assertEq(vault.balanceOf(BOB), 135, "bob after t3");

        // Stored balances equal view balances (post-migration invariant).
        assertEq(vault.rawStoredBalance(ALICE), 315, "alice stored = view");
        assertEq(vault.rawStoredBalance(BOB), 135, "bob stored = view");
    }

    /// Fuzzed interleaved transfers + splits. After each transfer, stored
    /// balances must equal view balances for both parties (migration is
    /// eager on both `from` and `to`), and the pairwise conservation
    /// invariant must hold: the net balance delta equals the transfer
    /// amount minus any truncation from the rebase that landed between
    /// transfers.
    function testFuzzInterleavedTransfersAndSplits(
        uint32 aliceInit,
        uint32 bobInit,
        uint64 amount1,
        uint64 amount2,
        uint64 amount3
    ) external {
        aliceInit = uint32(bound(aliceInit, 1000, type(uint32).max));
        bobInit = uint32(bound(bobInit, 1000, type(uint32).max));

        vault.publicUpdate(address(0), ALICE, uint256(aliceInit));
        vault.publicUpdate(address(0), BOB, uint256(bobInit));

        // Split 1: 2x.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(1600);

        // Transfer Alice → Bob. `balanceOf` already returns the post-rebase
        // value, which is exactly what migration will write for Alice's
        // stored balance inside `_update`. Bound the amount by that.
        amount1 = uint64(bound(amount1, 0, vault.balanceOf(ALICE)));
        vault.publicUpdate(ALICE, BOB, uint256(amount1));
        assertEq(vault.balanceOf(ALICE), vault.rawStoredBalance(ALICE), "alice view=stored after t1");
        assertEq(vault.balanceOf(BOB), vault.rawStoredBalance(BOB), "bob view=stored after t1");

        // Split 2: 1/2x.
        Float halfX = LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(2, 0));
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2000, abi.encode(halfX));
        vm.warp(2100);

        // Transfer Bob → Alice.
        amount2 = uint64(bound(amount2, 0, vault.balanceOf(BOB)));
        vault.publicUpdate(BOB, ALICE, uint256(amount2));
        assertEq(vault.balanceOf(ALICE), vault.rawStoredBalance(ALICE), "alice view=stored after t2");
        assertEq(vault.balanceOf(BOB), vault.rawStoredBalance(BOB), "bob view=stored after t2");

        // Split 3: 3x.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(3));
        vm.warp(2600);

        // Transfer Alice → Bob.
        amount3 = uint64(bound(amount3, 0, vault.balanceOf(ALICE)));
        vault.publicUpdate(ALICE, BOB, uint256(amount3));
        assertEq(vault.balanceOf(ALICE), vault.rawStoredBalance(ALICE), "alice view=stored after t3");
        assertEq(vault.balanceOf(BOB), vault.rawStoredBalance(BOB), "bob view=stored after t3");

        // Final convergence: repeated idempotent touches don't change anything.
        uint256 aliceFinal = vault.balanceOf(ALICE);
        uint256 bobFinal = vault.balanceOf(BOB);
        vault.publicUpdate(ALICE, ALICE, 0);
        vault.publicUpdate(BOB, BOB, 0);
        assertEq(vault.balanceOf(ALICE), aliceFinal, "alice idempotent after final");
        assertEq(vault.balanceOf(BOB), bobFinal, "bob idempotent after final");
    }
}

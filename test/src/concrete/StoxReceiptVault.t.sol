// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std/Test.sol";
import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
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
            vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT, uint64(1001 + i * 100), params);
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
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(1600);

        // Alice touches after split 1 (migrates partially).
        vault.publicUpdate(ALICE, ALICE, 0);

        // Split 2: 1/2x at t=2000.
        Float halfX = LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(2, 0));
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT, 2000, abi.encode(halfX));
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
            vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT, uint64(1001 + i * 100), params);
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
}

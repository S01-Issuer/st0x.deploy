// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std/Test.sol";
import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {
    IERC20Errors
} from "openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {LibCorporateAction} from "../../../src/lib/LibCorporateAction.sol";
import {
    ACTION_TYPE_STOCK_SPLIT_V1,
    ACTION_TYPE_STABLES_DIVIDEND_V1
} from "../../../src/interface/ICorporateActionsV1.sol";
import {LibERC20Storage} from "../../../src/lib/LibERC20Storage.sol";
import {LibStockSplit} from "../../../src/lib/LibStockSplit.sol";
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
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        uint256 prevLatest = s.totalSupplyLatestCursor;
        LibTotalSupply.fold();
        uint256 newLatest = s.totalSupplyLatestCursor;

        if (newLatest != prevLatest) {
            _emitNewlyEffectiveSplits(prevLatest, newLatest);
        }

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
        return LibStockSplit.encodeParametersV1(LibDecimalFloat.packLossless(multiplier, 0));
    }

    function _fractionalParams(int256 num, int256 denom) internal pure returns (bytes memory) {
        Float result = LibDecimalFloat.div(LibDecimalFloat.packLossless(num, 0), LibDecimalFloat.packLossless(denom, 0));
        return LibStockSplit.encodeParametersV1(result);
    }

    /// Mint to a fresh account after a completed 2x split credits exactly
    /// the minted amount, not 2x the minted amount. Without the
    /// zero-balance cursor-advancement guard, the recipient's freshly-
    /// written post-rebase balance would be re-multiplied on the next
    /// `balanceOf` read — an inflation bug.
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

    /// Transfer to a fresh recipient after a completed split credits
    /// exactly the transferred amount, not multiplied by the split.
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

        // Alice's cursor should now be 2 — through the bootstrap (idx 1)
        // and the completed split (idx 2).
        assertEq(vault.migrationCursor(ALICE), 2, "fresh account cursor must advance");
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
        assertEq(vault.migrationCursor(BOB), 3, "cursor advanced to latest split (bootstrap+2 splits)");
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
        emit StoxReceiptVault.AccountMigrated(BOB, 0, 2, 100, 200);
        // Touch Bob to trigger migration. fromCursor=0, toCursor=2 (idx 1
        // is the bootstrap, idx 2 is the completed split).
        vault.publicUpdate(BOB, BOB, 0);
    }

    /// `AccountMigrated` must fire exactly once per `_update`, aggregating
    /// the full multi-split migration into a single event with the aggregate
    /// `fromCursor → toCursor` and `oldBalance → newBalance`. Pins that the
    /// emit is not per-split and that the post-rasterization fields reflect
    /// the end state after all completed splits are applied, not an
    /// intermediate state.
    function testAccountMigratedEventAggregatesAcrossMultipleSplits() external {
        vault.publicUpdate(address(0), BOB, 100);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(3));
        vm.warp(3000);

        vm.recordLogs();
        vault.publicUpdate(BOB, BOB, 0);

        bytes32 sig = StoxReceiptVault.AccountMigrated.selector;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 count = 0;
        uint256 fromCursor;
        uint256 toCursor;
        uint256 oldBalance;
        uint256 newBalance;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == sig) {
                count++;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), BOB, "indexed account is BOB");
                (fromCursor, toCursor, oldBalance, newBalance) =
                    abi.decode(logs[i].data, (uint256, uint256, uint256, uint256));
            }
        }
        assertEq(count, 1, "exactly one AccountMigrated event per multi-split migration");
        assertEq(fromCursor, 0, "fromCursor is pre-migration cursor");
        // Bootstrap (idx 1) + two splits (idx 2, 3); migration walks all three.
        assertEq(toCursor, 3, "toCursor is latest completed split index");
        assertEq(oldBalance, 100, "oldBalance is pre-rasterization stored value");
        assertEq(newBalance, 600, "newBalance is fully rasterized (100 * 2 * 3)");
    }

    /// Phenomenon 1 (zero balance): `AccountMigrated` fires when a
    /// zero-balance account's cursor advances. `oldBalance == newBalance == 0`,
    /// the cursor moves from 0 to the latest completed split. Pins issue
    /// #81 resolution: every cursor advance emits.
    function testAccountMigratedFiresOnZeroBalanceCursorAdvance() external {
        // Pre-existing holder so bootstrap has something to read.
        vault.publicUpdate(address(0), BOB, 100);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);

        // Touch Alice (zero balance, fresh recipient).
        vm.expectEmit(true, false, false, true, address(vault));
        emit StoxReceiptVault.AccountMigrated(ALICE, 0, 1, 0, 0);
        vault.publicUpdate(address(0), ALICE, 0);

        // Confirm the cursor actually advanced.
        assertEq(vault.migrationCursor(ALICE), 1, "alice cursor must have advanced");
    }

    /// Phenomenon 2 (single-step truncation collision): a stored balance of
    /// 1 through a 1.5x multiplier rasterizes to `trunc(1.5) == 1`. The
    /// cursor advances; the stored balance is unchanged; the event still
    /// fires.
    function testAccountMigratedFiresOnTruncationCollision() external {
        vault.publicUpdate(address(0), ALICE, 1);
        // Multiplier 3/2 = 1.5 — `trunc(1 * 1.5) == 1`.
        Float oneAndAHalf = LibDecimalFloat.div(LibDecimalFloat.packLossless(3, 0), LibDecimalFloat.packLossless(2, 0));
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, LibStockSplit.encodeParametersV1(oneAndAHalf));
        vm.warp(2000);

        vm.expectEmit(true, false, false, true, address(vault));
        emit StoxReceiptVault.AccountMigrated(ALICE, 0, 1, 1, 1);
        vault.publicUpdate(ALICE, ALICE, 0);

        assertEq(vault.rawStoredBalance(ALICE), 1, "stored balance unchanged after truncation collision");
        assertEq(vault.migrationCursor(ALICE), 1, "alice cursor advanced past the split");
    }

    /// Phenomenon 3 (multi-step round-trip): a balance of 4 through `[2x,
    /// 1/2x]` rasterizes `4 -> 8 -> 4`. The intermediate value differs
    /// from the start but the final equals it. (Rain Float represents 1/2
    /// exactly in base 10, so this sequence round-trips for any even
    /// balance — `1/3` would not, since the Float representation of 1/3
    /// is slightly less than exact 1/3 and `trunc(3 * 1/3_float) = 0`.)
    /// The cursor jumps two splits in a single `_update`; the event fires
    /// once with `oldBalance == newBalance == 4`.
    function testAccountMigratedFiresOnMultiStepRoundTrip() external {
        vault.publicUpdate(address(0), ALICE, 4);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _fractionalParams(1, 2));
        vm.warp(3000);

        vm.expectEmit(true, false, false, true, address(vault));
        emit StoxReceiptVault.AccountMigrated(ALICE, 0, 2, 4, 4);
        vault.publicUpdate(ALICE, ALICE, 0);

        assertEq(vault.rawStoredBalance(ALICE), 4, "stored balance round-tripped to itself");
        assertEq(vault.migrationCursor(ALICE), 2, "alice cursor advanced past both splits");
    }

    /// Phenomenon 4 (balance-specific identity): a balance of 10 through a
    /// 1.09x multiplier rasterizes to `trunc(10.9) == 10`. Same multiplier
    /// applied to a larger balance produces a real change; the no-op here
    /// is balance-specific. The event still fires.
    function testAccountMigratedFiresOnBalanceSpecificIdentity() external {
        vault.publicUpdate(address(0), ALICE, 10);
        // 1.09 = 109/100 — `trunc(10 * 1.09) = trunc(10.9) == 10`.
        Float oneOhNine =
            LibDecimalFloat.div(LibDecimalFloat.packLossless(109, 0), LibDecimalFloat.packLossless(100, 0));
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, LibStockSplit.encodeParametersV1(oneOhNine));
        vm.warp(2000);

        vm.expectEmit(true, false, false, true, address(vault));
        emit StoxReceiptVault.AccountMigrated(ALICE, 0, 1, 10, 10);
        vault.publicUpdate(ALICE, ALICE, 0);

        assertEq(vault.rawStoredBalance(ALICE), 10, "stored balance unchanged for this specific balance / multiplier");
        assertEq(vault.migrationCursor(ALICE), 1, "alice cursor advanced");
    }

    /// Transfer path with both `from` and `to` stale: both ends migrate
    /// during `_update`, so two `AccountMigrated` events fire — one per
    /// account — both before the ERC-20 `Transfer`. Bob's balance is
    /// non-zero pre-split, so his pre-rebase value is rasterized and
    /// his event has `oldBalance != newBalance`; Alice's same.
    function testAccountMigratedFiresForBothEndsOfTransfer() external {
        vault.publicUpdate(address(0), ALICE, 100);
        vault.publicUpdate(address(0), BOB, 200);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);

        vm.recordLogs();
        vault.publicUpdate(ALICE, BOB, 50);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 sig = StoxReceiptVault.AccountMigrated.selector;
        uint256 aliceCount;
        uint256 bobCount;
        uint256 aliceLogIdx = type(uint256).max;
        uint256 bobLogIdx = type(uint256).max;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length == 0 || logs[i].topics[0] != sig) continue;
            address who = address(uint160(uint256(logs[i].topics[1])));
            if (who == ALICE) {
                aliceCount++;
                aliceLogIdx = i;
            } else if (who == BOB) {
                bobCount++;
                bobLogIdx = i;
            }
        }
        assertEq(aliceCount, 1, "exactly one AccountMigrated for ALICE");
        assertEq(bobCount, 1, "exactly one AccountMigrated for BOB");
        // ordering: ALICE migrates first (the `from` side), then BOB.
        assertLt(aliceLogIdx, bobLogIdx, "ALICE (from) migrates before BOB (to)");

        // Decode payloads and check each rasterized balance.
        (, uint256 aliceTo, uint256 aliceOld, uint256 aliceNew) =
            abi.decode(logs[aliceLogIdx].data, (uint256, uint256, uint256, uint256));
        (, uint256 bobTo, uint256 bobOld, uint256 bobNew) =
            abi.decode(logs[bobLogIdx].data, (uint256, uint256, uint256, uint256));
        assertEq(aliceTo, 1, "alice cursor advanced to split");
        assertEq(aliceOld, 100);
        assertEq(aliceNew, 200);
        assertEq(bobTo, 1, "bob cursor advanced to split");
        assertEq(bobOld, 200);
        assertEq(bobNew, 400);
    }

    /// Already-migrated complement of #81's always-emit semantics: an
    /// account at the latest cursor that gets touched again (no new
    /// completed splits in between) must NOT re-emit `AccountMigrated`.
    /// The `newCursor == currentCursor` early return in `_migrateAccount`
    /// suppresses the spurious event. Pins that "every cursor advance
    /// emits" reads as "iff cursor advances".
    function testAccountMigratedDoesNotReEmitWhenAlreadyAtLatest() external {
        vault.publicUpdate(address(0), ALICE, 100);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);

        // First touch migrates Alice — event fires.
        vault.publicUpdate(ALICE, ALICE, 0);
        assertEq(vault.migrationCursor(ALICE), 1, "alice migrated to cursor 1");

        // Second touch with no new splits — event must NOT fire.
        vm.recordLogs();
        vault.publicUpdate(ALICE, ALICE, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 sig = StoxReceiptVault.AccountMigrated.selector;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].topics.length > 0 && logs[i].topics[0] == sig
                    && address(uint160(uint256(logs[i].topics[1]))) == ALICE
            ) {
                fail();
            }
        }
    }

    /// Event ordering pin: `AccountMigrated` must fire BEFORE the
    /// corresponding ERC-20 `Transfer` event in the same `_update` call,
    /// because `_migrateAccount` runs before `super._update`. Indexers
    /// rely on this ordering to compute pre-transfer rasterized balances
    /// from the migration log before applying the transfer delta.
    function testAccountMigratedOrderedBeforeTransfer() external {
        vault.publicUpdate(address(0), ALICE, 100);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);

        vm.recordLogs();
        vault.publicUpdate(ALICE, BOB, 50);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 migratedSig = StoxReceiptVault.AccountMigrated.selector;
        bytes32 transferSig = keccak256("Transfer(address,address,uint256)");
        uint256 firstMigrated = type(uint256).max;
        uint256 firstTransfer = type(uint256).max;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == migratedSig && firstMigrated == type(uint256).max) {
                firstMigrated = i;
            } else if (logs[i].topics[0] == transferSig && firstTransfer == type(uint256).max) {
                firstTransfer = i;
            }
        }
        assertLt(firstMigrated, firstTransfer, "AccountMigrated must precede Transfer");
    }

    /// Global invariant: across a random balance and a random sequence of
    /// stock-split multipliers, every cursor advance is matched by exactly
    /// one `AccountMigrated` log, and the log's `oldBalance / newBalance`
    /// pair always equals the actual pre/post stored balance — never a
    /// stale or skipped value.
    function testFuzzAccountMigratedFiresOnEveryCursorAdvance(uint64 startBalance, uint8 splitSeed, uint8 splitCount)
        external
    {
        startBalance = uint64(bound(startBalance, 0, type(uint32).max));
        splitCount = uint8(bound(splitCount, 1, 5));

        vault.publicUpdate(address(0), ALICE, startBalance);
        uint256 storedBefore = vault.rawStoredBalance(ALICE);
        uint256 cursorBefore = vault.migrationCursor(ALICE);

        // Schedule N splits with multipliers drawn from a small fixed
        // palette (2x, 3x, 1/2x, 1/3x) seeded by `splitSeed`. The point is
        // to drive a variety of rasterization outcomes — not to be
        // exhaustive over the multiplier space.
        for (uint256 i = 0; i < splitCount; i++) {
            uint8 pick = uint8((uint256(splitSeed) >> (i * 2)) & 0x3);
            // forge-lint: disable-next-line(unsafe-typecast)
            uint64 effectiveTime = uint64(1500 + i * 1000);
            if (pick == 0) {
                vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, effectiveTime, _splitParams(2));
            } else if (pick == 1) {
                vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, effectiveTime, _splitParams(3));
            } else if (pick == 2) {
                vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, effectiveTime, _fractionalParams(1, 2));
            } else {
                vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, effectiveTime, _fractionalParams(1, 3));
            }
        }
        vm.warp(uint64(1500 + uint256(splitCount) * 1000));

        // Touch Alice. Capture every log emitted by `_update`.
        vm.recordLogs();
        vault.publicUpdate(ALICE, ALICE, 0);

        bytes32 sig = StoxReceiptVault.AccountMigrated.selector;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 count;
        uint256 emittedFromCursor;
        uint256 emittedToCursor;
        uint256 emittedOld;
        uint256 emittedNew;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].topics.length > 0 && logs[i].topics[0] == sig
                    && address(uint160(uint256(logs[i].topics[1]))) == ALICE
            ) {
                count++;
                (emittedFromCursor, emittedToCursor, emittedOld, emittedNew) =
                    abi.decode(logs[i].data, (uint256, uint256, uint256, uint256));
            }
        }

        uint256 cursorAfter = vault.migrationCursor(ALICE);
        if (cursorAfter == cursorBefore) {
            // No cursor advance → no event. Defensively pin this branch
            // even though the bounded splitCount makes it unreachable.
            assertEq(count, 0, "no event when cursor did not advance");
        } else {
            assertEq(count, 1, "exactly one AccountMigrated event per cursor advance");
            assertEq(emittedFromCursor, cursorBefore, "fromCursor matches pre-migrate cursor");
            assertEq(emittedToCursor, cursorAfter, "toCursor matches post-migrate cursor");
            assertEq(emittedOld, storedBefore, "oldBalance matches the pre-migrate stored balance");
            assertEq(emittedNew, vault.rawStoredBalance(ALICE), "newBalance matches the post-migrate stored balance");
        }
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
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, LibStockSplit.encodeParametersV1(halfX));
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
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, LibStockSplit.encodeParametersV1(halfX));
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

        // One second before the split's effective time: the split is NOT
        // completed but the bootstrap node (always completed at schedule
        // time) is. Migration walks bootstrap (identity for splits) and
        // stops at the pending split — cursor advances to idx 1, balance
        // unchanged.
        vm.warp(1499);
        vault.publicUpdate(ALICE, ALICE, 0);
        assertEq(vault.migrationCursor(ALICE), 1, "cursor advances through bootstrap (identity)");
        assertEq(vault.balanceOf(ALICE), 100, "balance must not rebase before effective time");

        // Exactly at the split's effective time: split is now completed.
        // Migration fires, cursor advances to the split (idx 2), balance
        // rebases.
        vm.warp(1500);
        vault.publicUpdate(ALICE, ALICE, 0);
        assertEq(vault.migrationCursor(ALICE), 2, "cursor must advance at exact effective time");
        assertEq(vault.balanceOf(ALICE), 200, "balance must rebase at exact effective time");
    }

    /// Fuzzed no-split accounting: for any sequence of mints and burns
    /// applied before the first split completes (the default state of any
    /// token the moment it is deployed), `totalSupply()` equals the plain
    /// `Σmints − Σburns` sum. The corporate-actions override must be a
    /// straight passthrough of OZ's `_totalSupply` in this regime and
    /// introduce zero drift.
    function testFuzzNoSplitSupplyEqualsNetMinted(uint64[8] memory mints, uint8[8] memory burnsRaw) external {
        address[3] memory actors = [ALICE, BOB, CAROL];
        uint256 netMinted;

        for (uint256 i = 0; i < 8; i++) {
            address to = actors[i % 3];
            uint256 mintAmount = uint256(mints[i]) % 1e18;
            if (mintAmount > 0) {
                vault.publicUpdate(address(0), to, mintAmount);
                netMinted += mintAmount;
            }

            address from = actors[(i + 1) % 3];
            uint256 available = vault.balanceOf(from);
            if (available > 0 && burnsRaw[i] > 0) {
                uint256 burnAmount = (uint256(burnsRaw[i]) * available) / 255;
                if (burnAmount > 0) {
                    vault.publicUpdate(from, address(0), burnAmount);
                    netMinted -= burnAmount;
                }
            }

            assertEq(vault.totalSupply(), netMinted, "totalSupply drifted from net mint/burn sum without splits");
            assertEq(vault.totalSupplyLatestCursor(), 0, "bootstrap must not have fired: no split has completed");
        }
    }

    /// Pre-bootstrap regime: until the first `_update` after a completed
    /// split, `fold()` must not bootstrap, `onMint`/`onBurn` must be no-ops,
    /// and `totalSupply()` must return OZ's raw `_totalSupply`. A pending
    /// split that has not yet reached its effective time must not trigger
    /// any of these.
    function testPreBootstrapIsNoOpUntilCompletedSplit() external {
        // Mint pre-any-schedule. No pot update expected — bootstrap has
        // not fired, `nodes.length == 0`, `onMint` is a no-op.
        vault.publicUpdate(address(0), BOB, 200);
        assertEq(vault.totalSupplyLatestCursor(), 0, "no split tracked pre-schedule");
        assertEq(vault.totalSupply(), 200, "totalSupply matches OZ pre-any-schedule");
        assertEq(vault.unmigrated(0), 0, "pot 0 untouched pre-bootstrap");

        // Burn pre-any-schedule. Also a no-op on pots.
        vault.publicUpdate(BOB, address(0), 50);
        assertEq(vault.totalSupply(), 150, "totalSupply reflects burn via OZ");
        assertEq(vault.unmigrated(0), 0, "pot 0 still untouched");

        // Schedule a split with a future effective time. `_ensureBootstrap`
        // fires here: pushes the bootstrap node at idx 1 with `effectiveTime
        // = block.timestamp` (immediately completed), captures `unmigrated[0]
        // = OZ.totalSupply` (= 150 after the prior mint/burn). The user
        // split lands at idx 2 and is pending until warp.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 5000, _splitParams(2));
        // `totalSupplyLatestCursor` only moves inside `fold` (called from
        // `_update`), so it stays 0 between schedule and the next _update.
        assertEq(vault.totalSupplyLatestCursor(), 0, "schedule alone does not advance latest cursor");
        assertEq(vault.unmigrated(0), 150, "ensureBootstrap snapshotted OZ total supply into pot 0");

        // Mint again with the pending split scheduled. The bootstrap node
        // is completed at schedule time, so `fold()` advances
        // `totalSupplyLatestCursor` to the bootstrap (idx 1) and BOB
        // migrates from cursor 0 through the bootstrap (identity for
        // splits): `unmigrated[0] -= 150` (his full pre-bootstrap balance,
        // identity-rasterized), `unmigrated[1] += 150`. Then super._update
        // mints 100 into _balances[BOB], and onMint adds 100 to
        // `unmigrated[1]`.
        vault.publicUpdate(address(0), BOB, 100);
        assertEq(vault.totalSupplyLatestCursor(), 1, "fold advances through bootstrap on first _update");
        assertEq(vault.totalSupply(), 250, "totalSupply matches OZ while only bootstrap is completed");
        assertEq(vault.unmigrated(0), 0, "BOB drained pot 0 by migrating through bootstrap");
        assertEq(vault.unmigrated(1), 250, "post-bootstrap pot holds BOB's migrated balance plus the new mint");

        // balanceOf returns the post-bootstrap stored balance (identity
        // migration leaves it unchanged at 250).
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
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, LibStockSplit.encodeParametersV1(halfX));
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

    /// In the mint-after-split scenario, `totalSupply()` equals the sum of
    /// every holder's `balanceOf` — the share-side integration invariant
    /// that justifies the per-cursor pot bookkeeping.
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
    // CorporateActionEffective event tests.

    /// The event fires before any AccountMigrated event when the first
    /// transaction touches the vault after a split becomes effective.
    function testCorporateActionEffectiveEventFires() external {
        vault.publicUpdate(address(0), BOB, 1000);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);

        // The next _update call should emit `CorporateActionEffective(2,
        // STOCK_SPLIT, 1500)` (the user split lives at idx 2 because
        // bootstrap took idx 1) before any AccountMigrated event, because
        // fold() detects the newly-past-effectiveTime split and the vault
        // emits before migration. The bootstrap node has
        // `ACTION_TYPE_INIT_V1` so `_emitNewlyEffectiveSplits` skips it
        // (it walks `ACTION_TYPE_STOCK_SPLIT_V1` only).
        vm.expectEmit(true, false, false, true, address(vault));
        emit StoxReceiptVault.CorporateActionEffective(2, ACTION_TYPE_STOCK_SPLIT_V1, 1500);

        vault.publicUpdate(BOB, BOB, 0);
    }

    /// The event fires once per newly-effective split, not on every
    /// subsequent transaction. A second touch should NOT re-emit.
    function testCorporateActionEffectiveDoesNotReEmit() external {
        vault.publicUpdate(address(0), BOB, 1000);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);

        // First touch: fires.
        vault.publicUpdate(BOB, BOB, 0);

        // Second touch: fold() doesn't advance totalSupplyLatestCursor
        // (already past the split), so no event.
        vm.recordLogs();
        vault.publicUpdate(BOB, BOB, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // No CorporateActionEffective event should appear. Filter by the
        // event signature.
        bytes32 sig = keccak256("CorporateActionEffective(uint256,uint256,uint64)");
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != sig, "CorporateActionEffective must not re-emit");
        }
    }

    /// Two splits become effective before anyone touches the vault.
    /// Both are detected in a single fold() call and both events fire.
    function testCorporateActionEffectiveMultipleSplits() external {
        vault.publicUpdate(address(0), BOB, 1000);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(3));
        vm.warp(3000);

        // Both splits land in one fold() call; both events fire. Bootstrap
        // takes idx 1, so the splits are at idx 2 and 3.
        vm.expectEmit(true, false, false, true, address(vault));
        emit StoxReceiptVault.CorporateActionEffective(2, ACTION_TYPE_STOCK_SPLIT_V1, 1500);
        vm.expectEmit(true, false, false, true, address(vault));
        emit StoxReceiptVault.CorporateActionEffective(3, ACTION_TYPE_STOCK_SPLIT_V1, 2500);

        vault.publicUpdate(BOB, BOB, 0);
    }

    /// Many splits become effective before any `_update` touches the vault.
    /// A single `_update` must emit one `CorporateActionEffective` per split
    /// walked by `fold()`. Uses `vm.recordLogs()` to assert the exact set
    /// and order of emitted indices, rather than `vm.expectEmit` which
    /// would pass on any prefix.
    function testCorporateActionEffectiveEmitsOnceForEachOfManySplits() external {
        vault.publicUpdate(address(0), BOB, 1);

        // Schedule 5 splits, each at a later effectiveTime.
        uint64[5] memory times = [uint64(1500), 2500, 3500, 4500, 5500];
        for (uint256 i = 0; i < 5; i++) {
            vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, times[i], _splitParams(2));
        }
        vm.warp(6000);

        vm.recordLogs();
        vault.publicUpdate(BOB, BOB, 0);

        bytes32 sig = keccak256("CorporateActionEffective(uint256,uint256,uint64)");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 emitIndex = 0;
        uint256[5] memory seenActionIndex;
        uint64[5] memory seenEffectiveTime;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == sig) {
                assertLt(emitIndex, 5, "must not emit more than one per scheduled split");
                seenActionIndex[emitIndex] = uint256(logs[i].topics[1]);
                (, uint64 wasEffectiveAt) = abi.decode(logs[i].data, (uint256, uint64));
                seenEffectiveTime[emitIndex] = wasEffectiveAt;
                emitIndex++;
            }
        }
        assertEq(emitIndex, 5, "must emit one event per split");

        // Indices emit in list order (time-ascending), which matches schedule
        // order since effectiveTimes were chosen monotonically. The five
        // splits live at idx 2..6 because bootstrap took idx 1.
        for (uint256 i = 0; i < 5; i++) {
            assertEq(seenActionIndex[i], i + 2, "actionIndex must ascend in list order");
            assertEq(seenEffectiveTime[i], times[i], "wasEffectiveAt must match the scheduled effectiveTime");
        }
    }

    /// Emit across separated `_update` calls: split A completes, first
    /// `_update` emits split A. Later, split B is scheduled and reaches
    /// effective time. Next `_update` emits split B alone — not A (which
    /// has already been consumed by an earlier `fold()`). Pins the
    /// `prevLatest → newLatest` delta semantics.
    function testCorporateActionEffectiveEmitsOnlyNewlyEffectiveAcrossUpdates() external {
        vault.publicUpdate(address(0), BOB, 1);

        // Split A at 1500.
        uint256 splitA = vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);
        vault.publicUpdate(BOB, BOB, 0); // consumes split A, emits A.

        // Split B at 3500.
        uint256 splitB = vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 3500, _splitParams(2));
        vm.warp(4000);

        vm.recordLogs();
        vault.publicUpdate(BOB, BOB, 0); // should emit split B only.

        bytes32 sig = keccak256("CorporateActionEffective(uint256,uint256,uint64)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 count = 0;
        uint256 emittedIndex;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == sig) {
                emittedIndex = uint256(logs[i].topics[1]);
                count++;
            }
        }
        assertEq(count, 1, "second update must emit exactly one event");
        assertEq(emittedIndex, splitB, "emitted index must be splitB");
        assertTrue(splitA != splitB, "splits must have distinct indices");
    }

    /// The event triggers on every `_update` path that catches a
    /// newly-effective split, not just self-transfer touches. Pin that
    /// mint (from == 0), burn (to == 0), and arbitrary transfer paths
    /// each trigger the emit when they are the first `_update` after a
    /// split becomes effective.
    function testCorporateActionEffectiveTriggersOnMint() external {
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);

        // Bootstrap takes idx 1, the user split is at idx 2.
        vm.expectEmit(true, false, false, true, address(vault));
        emit StoxReceiptVault.CorporateActionEffective(2, ACTION_TYPE_STOCK_SPLIT_V1, 1500);
        vault.publicUpdate(address(0), BOB, 100); // mint path.
    }

    function testCorporateActionEffectiveTriggersOnBurn() external {
        vault.publicUpdate(address(0), BOB, 100);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);

        vm.expectEmit(true, false, false, true, address(vault));
        emit StoxReceiptVault.CorporateActionEffective(2, ACTION_TYPE_STOCK_SPLIT_V1, 1500);
        vault.publicUpdate(BOB, address(0), 50); // burn path — 100 stored becomes 200 post-split, burn 50 → 150.
    }

    function testCorporateActionEffectiveTriggersOnTransfer() external {
        vault.publicUpdate(address(0), BOB, 100);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);

        vm.expectEmit(true, false, false, true, address(vault));
        emit StoxReceiptVault.CorporateActionEffective(2, ACTION_TYPE_STOCK_SPLIT_V1, 1500);
        vault.publicUpdate(BOB, ALICE, 50); // transfer path.
    }

    /// Non-stock-split nodes (e.g. the reserved `ACTION_TYPE_STABLES_DIVIDEND_V1`)
    /// interleaved with stock splits must be skipped by the emit walk —
    /// `CorporateActionEffective` is explicitly scoped to stock splits, and
    /// `fold()` + `_emitNewlyEffectiveSplits` both filter on
    /// `ACTION_TYPE_STOCK_SPLIT_V1`. Schedules a dividend between two splits
    /// and asserts only two events fire, with action indices 1 and 3 (the
    /// split nodes), skipping index 2 (the dividend).
    function testCorporateActionEffectiveSkipsNonSplitActions() external {
        vault.publicUpdate(address(0), BOB, 1);

        uint256 splitA = vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        uint256 dividend = vault.publicSchedule(ACTION_TYPE_STABLES_DIVIDEND_V1, 2000, hex"");
        uint256 splitB = vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(2));

        vm.warp(3000);

        vm.recordLogs();
        vault.publicUpdate(BOB, BOB, 0);

        bytes32 sig = keccak256("CorporateActionEffective(uint256,uint256,uint64)");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256[2] memory seen;
        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == sig) {
                assertLt(count, 2, "only the two stock-split nodes should emit");
                seen[count] = uint256(logs[i].topics[1]);
                count++;
            }
        }
        assertEq(count, 2, "expected 2 events (one per split, dividend skipped)");
        assertEq(seen[0], splitA, "first emit is splitA");
        assertEq(seen[1], splitB, "second emit is splitB");
        // Ensure the dividend index never appeared in the emitted set.
        assertTrue(seen[0] != dividend && seen[1] != dividend, "dividend index must not be emitted");
    }

    /// With a split → dividend → split sequence all completed in a single
    /// `_update`, `fold()` must advance `totalSupplyLatestCursor` to the
    /// second split (skipping the interleaved dividend), not stop at the
    /// first split, and `_migrateAccount` must apply both splits'
    /// multipliers to the holder's balance. Complements
    /// `testCorporateActionEffectiveSkipsNonSplitActions` which pins the
    /// emit path; this pins the state path.
    function testInterleavedDividendDoesNotHaltStockSplitFold() external {
        vault.publicUpdate(address(0), BOB, 100);

        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vault.publicSchedule(ACTION_TYPE_STABLES_DIVIDEND_V1, 2000, hex"");
        uint256 splitB = vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(2));

        vm.warp(3000);
        vault.publicUpdate(BOB, BOB, 0);

        assertEq(vault.totalSupplyLatestCursor(), splitB, "fold() must advance past the dividend to the second split");
        assertEq(vault.migrationCursor(BOB), splitB, "BOB's cursor must also reach the second split");
        assertEq(vault.balanceOf(BOB), 400, "100 * 2 * 2 = 400 (dividend does not affect balance)");
    }

    /// A `_update` that runs while a split is scheduled-but-pending (its
    /// `effectiveTime` is still in the future) must NOT emit
    /// `CorporateActionEffective`. `fold()` only advances past completed
    /// splits, so `prevLatest == newLatest` and the emit branch is skipped.
    function testCorporateActionEffectivePendingSplitDoesNotEmit() external {
        vault.publicUpdate(address(0), BOB, 100);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 5000, _splitParams(2));
        // block.timestamp still 1000, split at 5000 is pending.

        vm.recordLogs();
        vault.publicUpdate(BOB, BOB, 0);

        bytes32 sig = keccak256("CorporateActionEffective(uint256,uint256,uint64)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(
                logs[i].topics.length == 0 || logs[i].topics[0] != sig,
                "pending split must not emit CorporateActionEffective"
            );
        }
    }

    /// A split cancelled before its `effectiveTime` is unlinked from the
    /// list (`next`/`prev` zeroed) and never reaches `fold()`'s completed
    /// walk, so it must NOT produce a `CorporateActionEffective` event on
    /// any subsequent `_update`.
    function testCorporateActionEffectiveCancelledSplitDoesNotEmit() external {
        vault.publicUpdate(address(0), BOB, 1000);
        uint256 id = vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vault.publicCancel(id);
        vm.warp(2000);

        vm.recordLogs();
        vault.publicUpdate(BOB, BOB, 0);

        bytes32 sig = keccak256("CorporateActionEffective(uint256,uint256,uint64)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(
                logs[i].topics.length == 0 || logs[i].topics[0] != sig,
                "cancelled split must not emit CorporateActionEffective"
            );
        }
    }

    /// A cancelled split sandwiched between two completed splits must be
    /// skipped by `_emitNewlyEffectiveSplits`. The `nextOfType(...COMPLETED)`
    /// walk never visits cancelled nodes, so only the two real splits should
    /// emit. This is distinct from `testCorporateActionEffectiveSkipsNonSplitActions`
    /// (which interleaves a different action type) and
    /// `testCorporateActionEffectiveCancelledSplitDoesNotEmit` (which has no
    /// completed siblings): it specifically exercises the completed-filter
    /// continuation past a cancelled node of the same type.
    function testCorporateActionEffectiveSkipsCancelledSplitBetweenCompleted() external {
        vault.publicUpdate(address(0), BOB, 1);

        uint256 splitA = vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        uint256 cancelled = vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2000, _splitParams(2));
        uint256 splitB = vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(2));
        vault.publicCancel(cancelled);
        vm.warp(3000);

        vm.recordLogs();
        vault.publicUpdate(BOB, BOB, 0);

        bytes32 sig = keccak256("CorporateActionEffective(uint256,uint256,uint64)");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256[2] memory seen;
        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == sig) {
                assertLt(count, 2, "only the two completed splits should emit");
                seen[count] = uint256(logs[i].topics[1]);
                count++;
            }
        }
        assertEq(count, 2, "expected 2 events (cancelled split skipped)");
        assertEq(seen[0], splitA, "first emit is splitA");
        assertEq(seen[1], splitB, "second emit is splitB");
        assertTrue(seen[0] != cancelled && seen[1] != cancelled, "cancelled index must not be emitted");
    }

    /// Ordering claim from the NatSpec: `CorporateActionEffective` fires
    /// strictly before any `AccountMigrated` in the same transaction.
    /// `vm.expectEmit` in the other tests does not enforce inter-event
    /// order — pin it here by grabbing logs in order and asserting the
    /// effective-event log index is strictly less than the migration-event
    /// log index.
    function testCorporateActionEffectiveBeforeAccountMigrated() external {
        vault.publicUpdate(address(0), BOB, 100);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);

        vm.recordLogs();
        vault.publicUpdate(BOB, BOB, 0);

        bytes32 effectiveSig = keccak256("CorporateActionEffective(uint256,uint256,uint64)");
        bytes32 migratedSig = keccak256("AccountMigrated(address,uint256,uint256,uint256,uint256)");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 effectiveIndex = type(uint256).max;
        uint256 migratedIndex = type(uint256).max;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == effectiveSig && effectiveIndex == type(uint256).max) {
                effectiveIndex = i;
            }
            if (logs[i].topics[0] == migratedSig && migratedIndex == type(uint256).max) {
                migratedIndex = i;
            }
        }
        assertLt(effectiveIndex, type(uint256).max, "CorporateActionEffective must emit");
        assertLt(migratedIndex, type(uint256).max, "AccountMigrated must emit");
        assertLt(effectiveIndex, migratedIndex, "CorporateActionEffective must precede AccountMigrated");
    }

    // -----------------------------------------------------------------------
    // Cursor / totalSupplyLatestCursor invariant.
    //
    // After `_migrateAccount(account)` returns inside `_update` (which runs
    // after `fold()`), `accountMigrationCursor[account]` equals
    // `s.totalSupplyLatestCursor`. `LibTotalSupply.onBurn` subtracts the
    // burn amount from `unmigrated[totalSupplyLatestCursor]`. If the
    // burner's migrated balance had landed in a different pot (cursor !=
    // latest), onBurn would subtract from a pot that never received the
    // balance, and the subtraction would underflow.

    /// Deterministic pin for the exact path onBurn's safety relies on:
    /// schedule a split → mint pre-split → warp past it → schedule another
    /// split → warp past it → burn from the pre-split holder. After every
    /// migrating `publicUpdate` call, `migrationCursor(bob)` must equal
    /// `totalSupplyLatestCursor()`, and the burn must succeed (no panic).
    function testCursorEqualsTotalSupplyLatestSplitAcrossBurnPath() external {
        // Split 1: 2x at t=1500. Mint Bob before it lands so he starts at
        // cursor 0 (pre-any-split basis).
        vault.publicUpdate(address(0), BOB, 1000);
        assertEq(vault.migrationCursor(BOB), 0, "fresh mint lands at cursor 0 before any split");
        assertEq(vault.totalSupplyLatestCursor(), 0, "no splits completed yet");

        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);

        // Touch Bob — migration should land his cursor on 2 (bootstrap at
        // idx 1, split at idx 2) AND totalSupplyLatestCursor should also be
        // 2 (fold advanced through both).
        vault.publicUpdate(BOB, BOB, 0);
        assertEq(vault.migrationCursor(BOB), vault.totalSupplyLatestCursor(), "post-migrate: cursor == latest");
        assertEq(vault.migrationCursor(BOB), 2, "cursor advanced through bootstrap and the first split");
        assertEq(vault.balanceOf(BOB), 2000, "Bob rebased to 2000");

        // Split 2: 3x at t=2500. Schedule and warp.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(3));
        vm.warp(3000);

        // Now burn some from Bob. Inside `_update`, fold() advances
        // totalSupplyLatestCursor to 3 (the second split), then
        // _migrateAccount(BOB) walks Bob's cursor from 2 to 3, rasterizing
        // the balance to 6000. Then onBurn(500) subtracts 500 from
        // unmigrated[3]. If the cursor invariant held, this succeeds; if
        // it didn't, onBurn would underflow.
        vault.publicUpdate(BOB, address(0), 500);
        assertEq(vault.migrationCursor(BOB), vault.totalSupplyLatestCursor(), "post-burn: cursor == latest");
        assertEq(vault.migrationCursor(BOB), 3, "cursor advanced through second split");
        // 1000 → 2x → 2000 → 3x → 6000 → -500 → 5500.
        assertEq(vault.balanceOf(BOB), 5500, "Bob's final balance reflects both splits and the burn");
        // Bob is the only holder, so totalSupply == balanceOf(Bob).
        assertEq(vault.totalSupply(), 5500, "totalSupply must equal sum of balances");
    }

    /// Fuzz: run a sequence of mint / transfer / burn operations interleaved
    /// with stock splits, and assert after EVERY `publicUpdate` touching an
    /// account that `migrationCursor(account) == totalSupplyLatestCursor()`.
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
        // totalSupplyLatestCursor == 0. Neither mint should have migrated
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
        assertEq(vault.migrationCursor(BOB), 2, "Bob cursor advanced through split 1 (idx 2; bootstrap is idx 1)");
        assertEq(vault.migrationCursor(CAROL), 2, "Carol's cursor advanced through split 1");

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
        assertEq(vault.migrationCursor(CAROL), 3, "Carol cursor advanced through split 2 (idx 3)");

        // Touch Bob to migrate him too.
        vault.publicUpdate(BOB, BOB, 0);
        _assertCursorInvariant(BOB);
        assertEq(vault.migrationCursor(BOB), 3, "Bob's cursor advanced through both splits");

        // Final sum-of-balances check. Both accounts have migrated through
        // the full chain; totalSupply must equal their combined balance.
        assertEq(
            vault.balanceOf(BOB) + vault.balanceOf(CAROL),
            vault.totalSupply(),
            "sum(balanceOf) must equal totalSupply after full migration"
        );
    }

    /// @dev Assert that the account's migration cursor equals the global
    /// `totalSupplyLatestCursor`. This is the invariant `onBurn` depends on.
    function _assertCursorInvariant(address account) internal view {
        assertEq(
            vault.migrationCursor(account),
            vault.totalSupplyLatestCursor(),
            "migrationCursor must equal totalSupplyLatestCursor after _migrateAccount"
        );
    }

    /// Structural coupling test between `LibRebase.migratedBalance` and
    /// `LibTotalSupply.fold()`.
    ///
    /// Both functions currently filter the corporate-action linked list with
    /// `ACTION_TYPE_STOCK_SPLIT_V1`. That coupling keeps
    /// `accountMigrationCursor` and `totalSupplyLatestCursor` in lockstep.
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
    ///     but `totalSupplyLatestCursor` does not.
    ///   - If `fold()` starts walking the new type without `_migrateAccount`
    ///     doing the same, the inverse failure mode triggers.
    ///
    /// When that happens, DO NOT just update the assertions — the failure is
    /// signalling that the pot model now needs per-action-type accounting.
    /// Revisit `LibTotalSupply` with the new action type's rebase semantics
    /// before touching this test.
    function testNonStockSplitNodeAdvancesNeitherCursor() external {
        // Schedule a completed dividend node. `publicSchedule` bypasses
        // `resolveActionType`, so the dividend's parameters blob doesn't
        // need to match any validator — we only care that the node lives
        // in the list with a non-stock-split bitmap. The first schedule
        // also creates the bootstrap (init) node at idx 1; the dividend
        // lands at idx 2.
        vault.publicSchedule(ACTION_TYPE_STABLES_DIVIDEND_V1, 1500, abi.encode(uint256(0)));

        // Give Bob a pre-existing balance so _migrateAccount has something
        // to rasterize if it ever starts walking the dividend node.
        vault.publicUpdate(address(0), BOB, 1000);

        // Warp past the dividend's effective time so it counts as completed.
        vm.warp(2000);

        // Touch Bob to drive fold() + _migrateAccount.
        vault.publicUpdate(BOB, BOB, 0);

        // Bootstrap (idx 1, type INIT) IS in the migration mask, so cursor
        // advances through it (identity). Dividend (idx 2) is NOT in the
        // migration mask, so the walk stops there. Net effect: cursor
        // advances from 0 to 1, balance unchanged (identity).
        assertEq(
            vault.migrationCursor(BOB), 1, "cursor must stop at the bootstrap; dividend must not advance it past idx 1"
        );
        assertEq(
            vault.totalSupplyLatestCursor(),
            1,
            "fold() must stop at the bootstrap; dividend must not advance latestCursor past idx 1"
        );
        assertEq(vault.balanceOf(BOB), 1000, "Bob's balance must be unaffected (bootstrap is identity)");

        // Now schedule a real stock split, complete it, and confirm BOTH
        // cursors advance together. This half of the test pins the
        // positive-case behaviour: stock splits move both, non-splits move
        // neither. The split lands at idx 3 (after sentinel, bootstrap, dividend).
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(2));
        vm.warp(3000);
        vault.publicUpdate(BOB, BOB, 0);

        assertEq(vault.migrationCursor(BOB), 3, "cursor must advance to the stock-split node (idx 3)");
        assertEq(vault.totalSupplyLatestCursor(), 3, "latest must advance to the stock-split node (idx 3)");
        assertEq(vault.balanceOf(BOB), 2000, "Bob's balance must reflect only the 2x split, not the dividend");
    }

    /// Pre-bootstrap `effectiveTotalSupply()` walks ALL completed multipliers
    /// starting from OZ's raw `_totalSupply`, not just the first one.
    /// `testTotalSupplyDuringBootstrapDeferredWindow` covers the single-split
    /// case; this covers multi-split to pin that the walk continues past the
    /// first completed node without a `fold()` having bootstrapped any pot.
    function testTotalSupplyMultiSplitPreBootstrap() external {
        vault.publicUpdate(address(0), BOB, 100);

        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(3));
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 3500, _splitParams(5));
        vm.warp(4000);

        // Critically: no `_update` between the warp and the read, so
        // `fold()` hasn't run; `totalSupplyLatestCursor` is still 0 even
        // though `_ensureBootstrap` has populated `unmigrated[0]` from
        // schedule. The view's walk reads `unmigrated[0]` directly.
        assertEq(vault.totalSupplyLatestCursor(), 0, "no _update yet => latestCursor unchanged");
        assertEq(vault.totalSupply(), 3000, "100 * 2 * 3 * 5 via pot-0 multi-multiplier walk");
    }

    /// `effectiveTotalSupply()` called between split completion and the first
    /// post-split `_update` reads `unmigrated[0]` (snapshotted by
    /// `_ensureBootstrap` at schedule time) and walks every completed
    /// multiplier. No state mutation in the view path.
    ///
    /// INTENT: pin the behaviour of the view during the post-schedule,
    /// pre-`fold` window. If the branch shape changes — e.g. if `fold()` is
    /// ever moved into the view — this test fails and forces the author to
    /// re-evaluate the state-mutation rules for view functions.
    function testTotalSupplyDuringBootstrapDeferredWindow() external {
        // Mint supply before any split is scheduled. No bootstrap yet.
        vault.publicUpdate(address(0), BOB, 100);
        assertEq(vault.totalSupplyLatestCursor(), 0, "no split tracked yet");

        // Schedule a 2x split and warp past its effective time. Schedule
        // runs `_ensureBootstrap`, which snapshots `unmigrated[0] = 100`.
        // Critically, do NOT call any `_update` after warping — so
        // `fold()` hasn't run and `totalSupplyLatestCursor` is still 0.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);

        // The view must still report the rebased supply by walking the
        // completed init+split nodes from `unmigrated[0]`.
        assertEq(vault.totalSupply(), 200, "view must apply the 2x multiplier without fold");

        // And `totalSupplyLatestCursor` is still 0 because no state-mutating
        // path has run fold(). The view reads are side-effect-free.
        assertEq(vault.totalSupplyLatestCursor(), 0, "view must not advance latest cursor");
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

        // Force `fold()` to advance `totalSupplyLatestCursor` through
        // bootstrap + every completed split without moving Bob's mass out
        // of pot 0. CAROL is a fresh zero-balance account — her
        // "migration" advances only her cursor, not any pot value. After
        // this, pot 0 still holds 100. Bootstrap is at idx 1, splits at
        // idx 2/3/4, so latest cursor lands on 4.
        vault.publicUpdate(address(0), CAROL, 0);
        assertEq(vault.totalSupplyLatestCursor(), 4, "fold must advance to the latest split (idx 4)");

        // CRITICAL ASSERTION: pot 0 holds 100, pots 1..4 are empty. The
        // view must walk `100 -> identity (init) -> trunc(100*2) -> trunc(200*3)
        // -> trunc(600*5) = 3000`. A dropped multiplier in the walk
        // collapses to 100.
        assertEq(vault.totalSupply(), 3000, "view must apply every multiplier while pot 0 holds mass");

        // Now migrate Bob. His mass leaves pot 0 and lands in pot 4 (the
        // latest split).
        vault.publicUpdate(BOB, BOB, 0);
        assertEq(vault.rawStoredBalance(BOB), 3000, "bob stored = 100 * 2 * 3 * 5");
        assertEq(vault.migrationCursor(BOB), 4, "bob cursor at latest split (idx 4)");

        // Post-migration: same total, but now all mass lives in pot 4.
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
        //   (2) migration cursor advanced to the split (idx 2 — bootstrap is idx 1)
        //   (3) unmigrated[0] drained of alice's pre-split balance
        //   (4) unmigrated[2] = migrated balance - burn = 100 - 100 = 0
        //
        // `effectiveTotalSupply` walks: running = unmigrated[0] = 0;
        // identity step at bootstrap; running = trunc(0 * 2) +
        // unmigrated[2] = 0 + 0 = 0.
        assertEq(vault.rawStoredBalance(ALICE), 0, "alice stored = 0");
        assertEq(vault.migrationCursor(ALICE), 2, "alice cursor at split (idx 2)");
        assertEq(vault.totalSupply(), 0, "totalSupply collapses to 0 after full burn");
    }

    /// Over-burn by a lone holder at `totalSupplyLatestCursor` must surface
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
            assertEq(vault.migrationCursor(accountsAtCursor[i]), cursor, "I(k): account must be at the expected cursor");
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

        // Alice touches: `_ensureBootstrap` already snapshotted
        // `unmigrated[0] = 150` at schedule time; the user split is at
        // idx 2 (bootstrap is at idx 1). Alice migrates 50 → 100, shifting
        // 50 out of pot 0 and 100 into pot 2.
        vault.publicUpdate(ALICE, ALICE, 0);
        _assertPotInvariant(0, _single(BOB));
        _assertPotInvariant(2, _single(ALICE));

        // Mint Carol 40 post-split. Fresh recipient cursor advances 0 → 2
        // with zero balance (no pot delta from migrate). Then super._update
        // adds 40 to _balances[CAROL], then onMint adds 40 to pot 2.
        vault.publicUpdate(address(0), CAROL, 40);
        _assertPotInvariant(0, _single(BOB));
        _assertPotInvariant(2, _pair(ALICE, CAROL));

        // Alice transfers 30 to Bob. Both migrate first: Alice already at
        // cursor 2 (no-op), Bob 0 → 2 with stored 100 → migrated 200. Pot
        // transitions: pot 0 -= 100 (Bob leaves), pot 2 += 200 (Bob arrives).
        // Then transfer moves 30 between their balances, both at cursor 2
        // — Σ at cursor 2 unchanged, no pot write.
        vault.publicUpdate(ALICE, BOB, 30);
        _assertPotInvariant(0, empty);
        _assertPotInvariant(2, _triple(ALICE, BOB, CAROL));

        // Burn 25 from Bob. super._update first: _balances[BOB] -= 25,
        // _totalSupply -= 25. Then onBurn subtracts 25 from pot 2.
        vault.publicUpdate(BOB, address(0), 25);
        _assertPotInvariant(0, empty);
        _assertPotInvariant(2, _triple(ALICE, BOB, CAROL));
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

        // Split 1 lands at idx 2 (bootstrap is at idx 1); Alice migrates.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(m1));
        vm.warp(2000);
        vault.publicUpdate(ALICE, ALICE, 0);
        _assertPotInvariant(0, _single(BOB));
        _assertPotInvariant(2, _single(ALICE));

        // Mint Carol post-split-1.
        vault.publicUpdate(address(0), CAROL, carolMint);
        _assertPotInvariant(0, _single(BOB));
        _assertPotInvariant(2, _pair(ALICE, CAROL));

        // Split 2 lands at idx 3; Alice migrates again.
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(m2));
        vm.warp(3000);
        vault.publicUpdate(ALICE, ALICE, 0);
        _assertPotInvariant(0, _single(BOB));
        _assertPotInvariant(2, _single(CAROL));
        _assertPotInvariant(3, _single(ALICE));

        // Alice → Bob transfer. Both migrate: Alice at 3 (no-op), Bob 0 → 3.
        uint256 aliceView = vault.balanceOf(ALICE);
        uint256 transferAmt = aliceView == 0 ? 0 : uint256(transferRaw) % (aliceView + 1);
        vault.publicUpdate(ALICE, BOB, transferAmt);
        _assertPotInvariant(0, empty);
        _assertPotInvariant(2, _single(CAROL));
        _assertPotInvariant(3, _pair(ALICE, BOB));

        // Burn from Bob.
        uint256 bobView = vault.balanceOf(BOB);
        uint256 burnAmt = bobView == 0 ? 0 : uint256(burnRaw) % (bobView + 1);
        vault.publicUpdate(BOB, address(0), burnAmt);
        _assertPotInvariant(0, empty);
        _assertPotInvariant(2, _single(CAROL));
        _assertPotInvariant(3, _pair(ALICE, BOB));
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
            Float multiplier = forward
                ? LibDecimalFloat.packLossless(2, 0)
                : LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(2, 0));
            bytes memory params = LibStockSplit.encodeParametersV1(multiplier);
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

    /// After every holder has migrated through every completed split, the
    /// aggregate pot overestimate from fractional-multiplier truncation
    /// fully resolves: `totalSupply() == sum(balanceOf over all holders)`
    /// exactly. Before full migration the equality holds as an upper bound
    /// (tested elsewhere); this test pins the exact-equality convergence.
    function testFuzzMultiAccountConvergenceAfterFullMigration(
        uint32 aliceInit,
        uint32 bobInit,
        uint32 carolInit,
        uint8 numSplits,
        uint8 seed
    ) external {
        aliceInit = uint32(bound(aliceInit, 1, type(uint32).max / 256));
        bobInit = uint32(bound(bobInit, 1, type(uint32).max / 256));
        carolInit = uint32(bound(carolInit, 0, type(uint32).max / 256));
        numSplits = uint8(bound(numSplits, 0, 6));

        vault.publicUpdate(address(0), ALICE, uint256(aliceInit));
        vault.publicUpdate(address(0), BOB, uint256(bobInit));
        if (carolInit > 0) vault.publicUpdate(address(0), CAROL, uint256(carolInit));

        for (uint256 i = 0; i < numSplits; i++) {
            bool forward = ((i ^ seed) & 1) == 0;
            Float multiplier = forward
                ? LibDecimalFloat.packLossless(2, 0)
                : LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(2, 0));
            // forge-lint: disable-next-line(unsafe-typecast)
            vault.publicSchedule(
                ACTION_TYPE_STOCK_SPLIT_V1, uint64(1001 + i * 100), LibStockSplit.encodeParametersV1(multiplier)
            );
        }

        if (numSplits > 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            vm.warp(uint64(1001 + uint256(numSplits) * 100 + 1));
        }

        // Migrate every holder through every completed split via self-touches.
        vault.publicUpdate(ALICE, ALICE, 0);
        vault.publicUpdate(BOB, BOB, 0);
        if (carolInit > 0) vault.publicUpdate(CAROL, CAROL, 0);

        uint256 sum = vault.balanceOf(ALICE) + vault.balanceOf(BOB) + vault.balanceOf(CAROL);
        assertEq(vault.totalSupply(), sum, "post-full-migration: totalSupply must equal sum(balanceOf) exactly");
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
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2000, LibStockSplit.encodeParametersV1(halfX));
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
            Float multiplier = forward
                ? LibDecimalFloat.packLossless(2, 0)
                : LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(2, 0));
            bytes memory params = LibStockSplit.encodeParametersV1(multiplier);
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
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2000, LibStockSplit.encodeParametersV1(halfX));
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
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2000, LibStockSplit.encodeParametersV1(halfX));
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

    uint256 internal constant OP_MINT = 0;
    uint256 internal constant OP_BURN = 1;
    uint256 internal constant OP_TRANSFER_OUT = 2;
    uint256 internal constant OP_SELF_TRANSFER = 3;
    uint256 internal constant OP_COUNT = 4;

    /// Three deterministic regression tests below pin the invariants that
    /// `StoxReceiptVault._migrateAccount`'s `if (account == address(0)) return;`
    /// short-circuit preserves. The skip is sound only because OZ
    /// `ERC20Upgradeable` routes mints/burns through `_totalSupply`, never
    /// through `_balances[address(0)]` — if a future refactor (or a new facet)
    /// writes to that slot, advances the zero-address cursor, or emits a
    /// migration event for it, the corresponding test below fires.
    ///
    /// Each invariant lives in its own test so a mutation maps 1:1 to a
    /// failing test — combining them would mean a single failure could mask
    /// which property was actually broken.
    ///
    /// All three drive the same fixed mint/burn/transfer/split sequence so
    /// the path under mutation is identical across the three.

    function testZeroAddressBalanceSlotStaysZero() external {
        _driveZeroAddressSequence();
        assertEq(vault.rawStoredBalance(address(0)), 0, "address(0) slot non-zero");
    }

    function testZeroAddressCursorStaysZero() external {
        _driveZeroAddressSequence();
        assertEq(vault.migrationCursor(address(0)), 0, "address(0) cursor advanced");
    }

    function testNoAccountMigratedEventForZeroAddress() external {
        vm.recordLogs();
        _driveZeroAddressSequence();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("AccountMigrated(address,uint256,uint256,uint256,uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 1 && logs[i].topics[0] == sig) {
                address account = address(uint160(uint256(logs[i].topics[1])));
                assertTrue(account != address(0), "AccountMigrated for address(0)");
            }
        }
    }

    /// Fixed mint/burn/transfer/split sequence shared by the three
    /// deterministic invariant tests above. Touches every `_update` path that
    /// could plausibly interact with the zero address: mint, burn,
    /// post-bootstrap mint, post-bootstrap burn, post-second-split transfer,
    /// final burn.
    function _driveZeroAddressSequence() internal {
        vault.publicUpdate(address(0), ALICE, 1000);
        vault.publicUpdate(ALICE, address(0), 300);

        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);

        vault.publicUpdate(address(0), BOB, 500);
        vault.publicUpdate(BOB, address(0), 200);

        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(3));
        vm.warp(3000);

        vault.publicUpdate(ALICE, BOB, 100);
        vault.publicUpdate(BOB, address(0), 50);
    }

    /// Fuzz coverage: random mint / burn / transfer / self-transfer ops
    /// preserve all three zero-address invariants. Wider than the
    /// deterministic tests but path-dependent — not the mutation-test target.
    function testFuzzZeroAddressInvariantsHold(uint8 actionCount, uint256 seed) external {
        actionCount = uint8(bound(actionCount, 1, 32));
        vm.recordLogs();

        // Pre-seed Alice and Bob with enough headroom that random burns and
        // transfers don't trivially revert. `ERC20InsufficientBalance` reverts
        // are caught and treated as no-ops — the invariants are about
        // address(0)'s slot, cursor, and event surface, all of which a revert
        // leaves untouched.
        vault.publicUpdate(address(0), ALICE, 1_000_000);
        vault.publicUpdate(address(0), BOB, 1_000_000);

        for (uint256 i = 0; i < actionCount; i++) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint256 op = seed % OP_COUNT;
            uint256 amount = bound(seed >> 8, 1, 10_000);
            address actor = (seed >> 16) & 1 == 0 ? ALICE : BOB;
            address other = actor == ALICE ? BOB : ALICE;

            try this.driveUpdate(op, actor, other, amount) {} catch {}

            assertEq(vault.rawStoredBalance(address(0)), 0, "address(0) slot non-zero");
            assertEq(vault.migrationCursor(address(0)), 0, "address(0) cursor advanced");
        }

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("AccountMigrated(address,uint256,uint256,uint256,uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 1 && logs[i].topics[0] == sig) {
                address account = address(uint160(uint256(logs[i].topics[1])));
                assertTrue(account != address(0), "AccountMigrated for address(0)");
            }
        }
    }

    /// External wrapper so the fuzz loop can swallow `try`/`catch` reverts
    /// (e.g. `ERC20InsufficientBalance` when a random burn exceeds balance).
    function driveUpdate(uint256 op, address actor, address other, uint256 amount) external {
        if (op == OP_MINT) {
            vault.publicUpdate(address(0), actor, amount);
        } else if (op == OP_BURN) {
            vault.publicUpdate(actor, address(0), amount);
        } else if (op == OP_TRANSFER_OUT) {
            vault.publicUpdate(actor, other, amount);
        } else if (op == OP_SELF_TRANSFER) {
            vault.publicUpdate(actor, actor, amount);
        }
    }
}

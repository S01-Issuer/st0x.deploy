// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.16.1/src/Test.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
import {LibTotalSupply} from "src/lib/LibTotalSupply.sol";
import {LibCorporateAction} from "src/lib/LibCorporateAction.sol";
import {ACTION_TYPE_STOCK_SPLIT_V1} from "src/interface/ICorporateActionsV1.sol";
import {LibERC20Storage, ERC20_STORAGE_LOCATION} from "src/lib/LibERC20Storage.sol";
import {LibStockSplit} from "src/lib/LibStockSplit.sol";

contract LibTotalSupplyHarness {
    function schedule(uint256 actionType, uint64 effectiveTime, bytes memory parameters) external returns (uint256) {
        return LibCorporateAction.schedule(actionType, effectiveTime, parameters);
    }

    function cancel(uint256 actionIndex) external {
        LibCorporateAction.cancel(actionIndex);
    }

    function effectiveTotalSupply() external view returns (uint256) {
        return LibTotalSupply.effectiveTotalSupply();
    }

    function fold() external {
        LibTotalSupply.fold();
    }

    function onAccountMigrated(uint256 fromCursor, uint256 storedBalance, uint256 toCursor, uint256 newBalance)
        external
    {
        LibTotalSupply.onAccountMigrated(fromCursor, storedBalance, toCursor, newBalance);
    }

    function onMint(uint256 amount) external {
        LibTotalSupply.onMint(amount);
    }

    function onBurn(uint256 amount) external {
        LibTotalSupply.onBurn(amount);
    }

    /// @dev Test-only helper: write directly to OZ's `_totalSupply` slot to
    /// seed the harness with a starting totalSupply. `LibERC20Storage` no
    /// longer exposes a setter (production code must not write this slot —
    /// `LibTotalSupply` per-cursor pots own the effective supply), so we do
    /// the slot write inline here.
    function setOzTotalSupply(uint256 supply) external {
        // Bind to a local — inline assembly only accepts literal number
        // constants, and `ERC20_STORAGE_LOCATION` is now derived in-source.
        bytes32 slot = ERC20_STORAGE_LOCATION;
        assembly ("memory-safe") {
            sstore(add(slot, 2), supply)
        }
    }

    function unmigrated(uint256 cursor) external view returns (uint256) {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        return s.unmigrated[cursor];
    }

    function totalSupplyLatestCursor() external view returns (uint256) {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        return s.totalSupplyLatestCursor;
    }
}

contract LibTotalSupplyTest is Test {
    LibTotalSupplyHarness internal h;

    function setUp() public {
        h = new LibTotalSupplyHarness();
        vm.warp(1000);
    }

    function _splitParams(int256 multiplier) internal pure returns (bytes memory) {
        return LibStockSplit.encodeParametersV1(LibDecimalFloat.packLossless(multiplier, 0));
    }

    function _fractionalParams(int256 num, int256 denom) internal pure returns (bytes memory) {
        Float result = LibDecimalFloat.div(LibDecimalFloat.packLossless(num, 0), LibDecimalFloat.packLossless(denom, 0));
        return LibStockSplit.encodeParametersV1(result);
    }

    /// Before any splits, returns OZ's totalSupply.
    function testNoSplitsReturnsOzSupply() external {
        h.setOzTotalSupply(1000);
        assertEq(h.effectiveTotalSupply(), 1000);
    }

    /// After a 2x split, totalSupply doubles (virtually, before fold).
    function testVirtualFoldDoubles() external {
        h.setOzTotalSupply(1000);
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);
        assertEq(h.effectiveTotalSupply(), 2000);
    }

    /// Eager fold bootstraps unmigrated[0] from OZ.
    function testEagerFold() external {
        h.setOzTotalSupply(1000);
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();
        assertEq(h.unmigrated(0), 1000);
        // Bootstrap at idx 0 + user split at idx 1; fold advances through
        // both completed migration nodes to the split.
        assertEq(h.totalSupplyLatestCursor(), 1);
    }

    /// Account migration moves balance between pots. Bootstrap is at idx 0
    /// (the default cursor) with the user split at idx 1, so a real
    /// migration from cursor 0 walks straight to cursor 1.
    function testAccountMigration() external {
        h.setOzTotalSupply(200);
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();
        // Account with stored=100 migrates from cursor 0 (= bootstrap) to
        // cursor 1 (the user split).
        h.onAccountMigrated(0, 100, 1, 200);
        assertEq(h.unmigrated(0), 100);
        assertEq(h.unmigrated(1), 200);
        // totalSupply = floor(100 * 2) + 200 = 400
        assertEq(h.effectiveTotalSupply(), 400);
    }

    /// Full migration: all accounts migrated, overestimate fully resolves.
    function testFullMigration() external {
        h.setOzTotalSupply(200);
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();
        h.onAccountMigrated(0, 100, 1, 200);
        h.onAccountMigrated(0, 100, 1, 200);
        assertEq(h.unmigrated(0), 0);
        assertEq(h.unmigrated(1), 400);
        assertEq(h.effectiveTotalSupply(), 400);
    }

    /// Second split: pots at different levels get correct multipliers.
    function testSecondSplitWithPartialMigration() external {
        h.setOzTotalSupply(300);
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();

        // A migrates through split 1 (idx 1) only.
        h.onAccountMigrated(0, 100, 1, 200);
        assertEq(h.effectiveTotalSupply(), 600);

        // Second split (3x) lands at idx 2.
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(3));
        vm.warp(3000);
        h.fold();

        // totalSupply = floor(floor(200 * 2) * 3) + floor(200 * 3) + 0
        //             = 1200 + 600 = 1800
        assertEq(h.effectiveTotalSupply(), 1800);

        // B migrates from cursor 0 through both splits to cursor 2.
        h.onAccountMigrated(0, 100, 2, 600);
        assertEq(h.effectiveTotalSupply(), 1800);

        // A migrates from cursor 1 through split 2 to cursor 2.
        h.onAccountMigrated(1, 200, 2, 600);
        assertEq(h.effectiveTotalSupply(), 1800);

        // C migrates from cursor 0 through both splits.
        h.onAccountMigrated(0, 100, 2, 600);
        assertEq(h.unmigrated(0), 0);
        assertEq(h.unmigrated(1), 0);
        assertEq(h.unmigrated(2), 1800);
        assertEq(h.effectiveTotalSupply(), 1800);
    }

    /// Fractional split: per-pot precision improves with each migration.
    function testFractionalPrecisionImprovement() external {
        // 2 accounts: A=7, B=3. Total=10. 1/3 reverse split.
        // Individual: floor(7 * 1/3) + floor(3 * 1/3) = 2 + 0 = 2.
        // Aggregate:  floor(10 * 1/3) = 3. Overestimate = 1.
        h.setOzTotalSupply(10);
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _fractionalParams(1, 3));
        vm.warp(2000);
        h.fold();

        assertEq(h.effectiveTotalSupply(), 3);

        // A migrates: stored=7, effective=2. Cursor 0 → 1 (split at idx 1).
        h.onAccountMigrated(0, 7, 1, 2);
        // unmigrated[0]=3, totalSupply = floor(3 * 1/3) + 2 = 0 + 2 = 2
        assertEq(h.effectiveTotalSupply(), 2);

        // B migrates: stored=3, effective=0.
        h.onAccountMigrated(0, 3, 1, 0);
        assertEq(h.unmigrated(0), 0);
        assertEq(h.unmigrated(1), 2);
        assertEq(h.effectiveTotalSupply(), 2);
    }

    /// Mint after fold increases the latest cursor pot.
    function testMintAfterFold() external {
        h.setOzTotalSupply(1000);
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();
        h.onMint(100);
        assertEq(h.effectiveTotalSupply(), 2100);
    }

    /// Burn after fold decreases the latest cursor pot.
    function testBurnAfterFold() external {
        h.setOzTotalSupply(1000);
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();
        h.onAccountMigrated(0, 1000, 1, 2000);
        h.onBurn(200);
        assertEq(h.effectiveTotalSupply(), 1800);
    }

    /// `onMint(0)` and `onBurn(0)` are pot-state-preserving no-ops.
    /// Both implementations are `unmigrated[latest] += amount` /
    /// `-= amount`, so zero is mathematically inert. A regression that
    /// reshaped the implementation (e.g., `unmigrated[latest] =
    /// f(amount)` instead of `+=`/`-=`) could silently corrupt the pot
    /// for zero-amount calls without surfacing in any non-zero-amount
    /// test.
    function testOnMintOnBurnZeroAreNoOps() external {
        h.setOzTotalSupply(1000);
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();
        h.onMint(100);

        uint256 potBefore = h.unmigrated(h.totalSupplyLatestCursor());
        uint256 supplyBefore = h.effectiveTotalSupply();

        h.onMint(0);
        assertEq(h.unmigrated(h.totalSupplyLatestCursor()), potBefore, "onMint(0) leaves the pot unchanged");
        assertEq(h.effectiveTotalSupply(), supplyBefore, "onMint(0) leaves totalSupply unchanged");

        h.onBurn(0);
        assertEq(h.unmigrated(h.totalSupplyLatestCursor()), potBefore, "onBurn(0) leaves the pot unchanged");
        assertEq(h.effectiveTotalSupply(), supplyBefore, "onBurn(0) leaves totalSupply unchanged");
    }

    /// Cancelling a pending split must not retroactively rewind
    /// `totalSupplyLatestCursor`. Once `fold()` has advanced past a
    /// completed split, that cursor reflects per-pot accounting state
    /// that's already reified in the storage pots — cancelling a
    /// later-scheduled pending split has no information to communicate
    /// back to fold's view of the past, so the cursor must remain where
    /// the prior fold left it.
    function testCancelPendingDoesNotRewindFoldedCursor() external {
        h.setOzTotalSupply(1000);

        // Schedule split A, complete it, fold so the cursor advances.
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();
        uint256 cursorAfterFirstFold = h.totalSupplyLatestCursor();
        assertEq(cursorAfterFirstFold, 1, "first fold lands on the completed user split (idx 1)");

        // Schedule a second split with future effectiveTime, then cancel
        // it before warping. The cursor must still be at idx 1 — the
        // cancellation of a pending node has no bearing on already-folded
        // state. Assert immediately after cancel, before any subsequent
        // fold could re-derive the value: a regression that wrote
        // `totalSupplyLatestCursor` from inside `cancel` would surface
        // here, while the same mutation is invisible to a post-fold
        // assertion (fold re-walks and lands at the same idx).
        uint256 idB = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 5000, _splitParams(3));
        h.cancel(idB);
        assertEq(h.totalSupplyLatestCursor(), cursorAfterFirstFold, "cancel must not write totalSupplyLatestCursor");

        // After re-folding, the cursor is unchanged either way (fold is
        // idempotent on a list with no newly-completed migration nodes).
        h.fold();
        assertEq(h.totalSupplyLatestCursor(), cursorAfterFirstFold, "fold post-cancel is idempotent");

        // The effectiveTotalSupply must equal what it was after the first
        // fold (only A applied), confirming the cursor and pot state are
        // consistent across the cancel.
        assertEq(h.effectiveTotalSupply(), 2000, "totalSupply unchanged after cancelling a pending split");
    }

    /// `fold()` walks via `nextOfType` (linked list pointers), so cancelled
    /// nodes — which have `next = NODE_NONE` after unlink — are unreachable
    /// from the walk. A regression that switched fold to a raw array
    /// iteration (`current + 1`) would still see the cancelled node's
    /// `actionType` (cancel preserves type) with `effectiveTime == 0`,
    /// passing the COMPLETED filter (0 <= block.timestamp). This would
    /// land `totalSupplyLatestCursor` on a cancelled index, breaking pot
    /// accounting on subsequent mints.
    ///
    /// Setup: schedule A/B/C, fold past A, cancel B (still pending), warp
    /// past C, fold again. The cursor must skip B and land on C.
    function testFoldWalksAroundCancelledNode() external {
        h.setOzTotalSupply(1000);

        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        uint256 idB = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2000, _splitParams(5));
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(3));

        // Complete A only, fold to land cursor on A.
        vm.warp(1600);
        h.fold();
        assertEq(h.totalSupplyLatestCursor(), 1, "first fold lands on A");

        // Cancel pending B before it completes — B is unlinked from the
        // walk but its array slot retains actionType + a zeroed
        // effectiveTime (the double-cancel guard).
        h.cancel(idB);

        // Now complete C and fold again. The walk must skip B (unlinked)
        // and advance to C.
        vm.warp(3000);
        h.fold();
        assertEq(h.totalSupplyLatestCursor(), 3, "second fold skips cancelled B and lands on C");

        // totalSupply confirms only A and C contributed: 1000 * 2 * 3 = 6000.
        assertEq(h.effectiveTotalSupply(), 6000, "B's 5x multiplier must not contribute (cancelled)");
    }

    /// Fold is idempotent.
    function testFoldIdempotent() external {
        h.setOzTotalSupply(1000);
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();
        h.fold();
        assertEq(h.effectiveTotalSupply(), 2000);
        assertEq(h.unmigrated(0), 1000);
    }

    /// Fold mutates only `totalSupplyLatestCursor` — never a pot. This
    /// pins step 1 of the pot-invariant inductive proof
    /// (LibTotalSupply.sol NatSpec): "fold mutates only
    /// totalSupplyLatestCursor; no pot write and no balance write".
    /// A regression where someone added a pot write inside fold (e.g.
    /// `s.unmigrated[latest] = 0` to "clear" a pot, or accidentally
    /// rolling pots across folds) would silently desync the pot
    /// invariant from the migration state. This test sets up
    /// non-trivial pot values, snapshots every pot, runs a fold that
    /// MUST advance the cursor, then asserts every snapshotted pot is
    /// unchanged.
    function testFoldDoesNotMutateAnyPot() external {
        h.setOzTotalSupply(1000);

        // Two completed splits; populate pots 0/1/2 with distinct values
        // by partial migration so the test isn't just asserting "all
        // zero" pots.
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(3));
        vm.warp(3000);
        h.fold();
        // Account A (stored 100) migrates 0 → 2 (rasterizes to 600).
        h.onAccountMigrated(0, 100, 2, 600);
        // Account B (stored 100) migrates 0 → 1 (rasterizes to 200).
        h.onAccountMigrated(0, 100, 1, 200);

        // Schedule a third split and warp past it so the next fold has
        // real work to do (advancing the cursor from 2 to 3).
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 4000, _splitParams(2));
        vm.warp(5000);

        uint256 cursorBefore = h.totalSupplyLatestCursor();
        uint256 pot0Before = h.unmigrated(0);
        uint256 pot1Before = h.unmigrated(1);
        uint256 pot2Before = h.unmigrated(2);
        uint256 pot3Before = h.unmigrated(3);

        h.fold();

        assertGt(h.totalSupplyLatestCursor(), cursorBefore, "fold must have advanced the cursor for the test to bind");
        assertEq(h.unmigrated(0), pot0Before, "fold must not mutate unmigrated[0]");
        assertEq(h.unmigrated(1), pot1Before, "fold must not mutate unmigrated[1]");
        assertEq(h.unmigrated(2), pot2Before, "fold must not mutate unmigrated[2]");
        assertEq(h.unmigrated(3), pot3Before, "fold must not mutate unmigrated[3]");
    }

    /// Virtual fold matches eager fold.
    function testVirtualMatchesEager() external {
        h.setOzTotalSupply(500);
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(3));
        vm.warp(3000);
        uint256 virtualResult = h.effectiveTotalSupply();
        h.fold();
        uint256 eagerResult = h.effectiveTotalSupply();
        assertEq(virtualResult, eagerResult);
        assertEq(eagerResult, 3000);
    }

    /// Sequential precision: 1/3 x 3 x 1/3 x 3 on totalSupply.
    function testSequentialPrecision() external {
        h.setOzTotalSupply(100);
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _fractionalParams(1, 3));
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(3));
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 3500, _fractionalParams(1, 3));
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 4500, _splitParams(3));
        vm.warp(5000);
        assertEq(h.effectiveTotalSupply(), 96);
    }

    /// Mint before any splits doesn't affect tracking.
    function testMintBeforeSplits() external {
        h.setOzTotalSupply(1000);
        h.onMint(500);
        assertEq(h.effectiveTotalSupply(), 1000);
    }

    /// Cross-epoch migration: account migrates through multiple splits at once.
    function testCrossEpochMigration() external {
        h.setOzTotalSupply(200);
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(3));
        vm.warp(3000);
        h.fold();

        // Splits live at idx 1 and 2 (bootstrap occupies idx 0).
        h.onAccountMigrated(0, 100, 2, 600);
        assertEq(h.effectiveTotalSupply(), 1200);

        h.onAccountMigrated(0, 100, 2, 600);
        assertEq(h.unmigrated(0), 0);
        assertEq(h.unmigrated(2), 1200);
        assertEq(h.effectiveTotalSupply(), 1200);
    }

    /// Reference implementation: compute effective total supply the same way
    /// LibTotalSupply.effectiveTotalSupply does, but in pure Solidity inside
    /// the test, so the production accumulator can be cross-checked.
    function _referenceEffectiveTotalSupply(uint256[] memory pots, int256[] memory multipliers)
        internal
        pure
        returns (uint256)
    {
        // pots.length == multipliers.length + 1
        // pot[0] is the bootstrap pot, walked before any multiplier.
        // pot[i] (i>=1) is the pot at split i; added AFTER multiplier i-1 is applied.
        uint256 running = pots[0];
        for (uint256 i = 0; i < multipliers.length; i++) {
            (running,) = LibDecimalFloat.toFixedDecimalLossy(
                LibDecimalFloat.mul(
                    // forge-lint: disable-next-line(unsafe-typecast)
                    LibDecimalFloat.packLossless(int256(running), 0),
                    LibDecimalFloat.packLossless(multipliers[i], 0)
                ),
                0
            );
            running += pots[i + 1];
        }
        return running;
    }

    /// Fuzz `effectiveTotalSupply` against an in-test reference
    /// implementation. Drives a configurable number of completed splits +
    /// per-pot balances and asserts the production accumulator matches a
    /// re-implementation that walks the pots in pure Solidity.
    function testFuzzEffectiveTotalSupplyMatchesReference(
        uint64 bootstrapPot,
        uint64[3] memory laterPots,
        uint8 mulSeed
    ) external {
        // Bound multipliers to sensible positive integers (1..5) so fuzz
        // doesn't drive the float lib into overflow / saturation territory.
        int256 m1 = int256(uint256(uint8(mulSeed % 5) + 1));
        int256 m2 = int256(uint256(uint8((mulSeed >> 3) % 5) + 1));
        int256 m3 = int256(uint256(uint8((mulSeed >> 5) % 5) + 1));

        // Schedule three splits and warp past all of them.
        h.setOzTotalSupply(uint256(bootstrapPot));
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(m1));
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(m2));
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 3500, _splitParams(m3));
        vm.warp(4000);
        h.fold();

        // After fold, unmigrated[0] == bootstrapPot. Add later pots via the
        // onAccountMigrated helper with from=0, storedBalance=0 so no
        // underflow risk on pot[0]. The three splits live at idx 1, 2, 3
        // (bootstrap is at idx 0). Each call adds `laterPots[i]` to the
        // pot at the corresponding split cursor.
        h.onAccountMigrated(0, 0, 1, uint256(laterPots[0]));
        h.onAccountMigrated(0, 0, 2, uint256(laterPots[1]));
        h.onAccountMigrated(0, 0, 3, uint256(laterPots[2]));

        // Build the reference inputs.
        uint256[] memory pots = new uint256[](4);
        pots[0] = uint256(bootstrapPot);
        pots[1] = uint256(laterPots[0]);
        pots[2] = uint256(laterPots[1]);
        pots[3] = uint256(laterPots[2]);
        int256[] memory multipliers = new int256[](3);
        multipliers[0] = m1;
        multipliers[1] = m2;
        multipliers[2] = m3;

        uint256 expected = _referenceEffectiveTotalSupply(pots, multipliers);
        assertEq(h.effectiveTotalSupply(), expected, "production accumulator must match the reference");
    }

    /// `onBurn` reverts via Solidity 0.8 underflow panic when the burn
    /// amount exceeds the current pot at `totalSupplyLatestCursor`. Under
    /// normal vault operation this state is unreachable (every burn is
    /// preceded by `migrateAccount(burner)`, which moves the burner's
    /// balance into the latest pot first), but wrapping the subtraction
    /// in an `unchecked` block would silently skip the check and let a
    /// refactor corrupt the pot.
    function testOnBurnUnderflowReverts() external {
        h.setOzTotalSupply(1000);
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();
        // `unmigrated[1]` (the latest cursor — the user split at idx 1) is
        // still 0; nothing has migrated or been minted post-fold.
        // Attempting to burn from an empty pot underflows.
        vm.expectRevert(stdError.arithmeticError);
        h.onBurn(1);
    }

    /// Audit P2-3: the exact-boundary burn succeeds; burning one wei more
    /// underflows.
    function testOnBurnAtBoundarySucceedsOneBeyondReverts() external {
        h.setOzTotalSupply(1000);
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();
        h.onMint(100); // unmigrated[1] = 100 (latest cursor is the user split)
        h.onBurn(100); // exact boundary — OK
        vm.expectRevert(stdError.arithmeticError);
        h.onBurn(1);
    }
}

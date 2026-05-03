// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std/Test.sol";
import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
import {LibTotalSupply} from "src/lib/LibTotalSupply.sol";
import {LibCorporateAction} from "src/lib/LibCorporateAction.sol";
import {ACTION_TYPE_STOCK_SPLIT_V1} from "src/interface/ICorporateActionsV1.sol";
import {LibERC20Storage, ERC20_STORAGE_LOCATION} from "src/lib/LibERC20Storage.sol";
import {LibStockSplit} from "src/lib/LibStockSplit.sol";

contract LibTotalSupplyHarness {
    function schedule(uint256 actionType, uint64 effectiveTime, bytes memory parameters) external returns (uint256) {
        return LibCorporateAction.schedule(actionType, effectiveTime, parameters);
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
    /// preceded by `_migrateAccount(burner)`, which moves the burner's
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

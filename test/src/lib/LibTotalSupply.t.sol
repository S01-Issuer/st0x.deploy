// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
import {LibTotalSupply} from "src/lib/LibTotalSupply.sol";
import {LibCorporateAction, ACTION_TYPE_STOCK_SPLIT} from "src/lib/LibCorporateAction.sol";
import {LibERC20Storage} from "src/lib/LibERC20Storage.sol";

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

    function setOzTotalSupply(uint256 supply) external {
        LibERC20Storage.setTotalSupply(supply);
    }

    function unmigrated(uint256 cursor) external view returns (uint256) {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        return s.unmigrated[cursor];
    }

    function totalSupplyLatestSplit() external view returns (uint256) {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        return s.totalSupplyLatestSplit;
    }

    function totalSupplyBootstrapped() external view returns (bool) {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        return s.totalSupplyBootstrapped;
    }
}

contract LibTotalSupplyTest is Test {
    LibTotalSupplyHarness internal h;

    function setUp() public {
        h = new LibTotalSupplyHarness();
        vm.warp(1000);
    }

    function _splitParams(int256 multiplier) internal pure returns (bytes memory) {
        return abi.encode(LibDecimalFloat.packLossless(multiplier, 0));
    }

    function _fractionalParams(int256 num, int256 denom) internal pure returns (bytes memory) {
        Float result = LibDecimalFloat.div(LibDecimalFloat.packLossless(num, 0), LibDecimalFloat.packLossless(denom, 0));
        return abi.encode(result);
    }

    /// Before any splits, returns OZ's totalSupply.
    function testNoSplitsReturnsOzSupply() external {
        h.setOzTotalSupply(1000);
        assertEq(h.effectiveTotalSupply(), 1000);
    }

    /// After a 2x split, totalSupply doubles (virtually, before fold).
    function testVirtualFoldDoubles() external {
        h.setOzTotalSupply(1000);
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);
        assertEq(h.effectiveTotalSupply(), 2000);
    }

    /// Eager fold bootstraps unmigrated[0] from OZ.
    function testEagerFold() external {
        h.setOzTotalSupply(1000);
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();
        assertEq(h.unmigrated(0), 1000);
        assertEq(h.totalSupplyBootstrapped(), true);
        assertEq(h.totalSupplyLatestSplit(), 1);
    }

    /// Account migration moves balance between pots.
    function testAccountMigration() external {
        h.setOzTotalSupply(200);
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();
        // Account with stored=100 migrates from cursor 0 to cursor 1.
        h.onAccountMigrated(0, 100, 1, 200);
        assertEq(h.unmigrated(0), 100);
        assertEq(h.unmigrated(1), 200);
        // totalSupply = floor(100 * 2) + 200 = 400
        assertEq(h.effectiveTotalSupply(), 400);
    }

    /// Full migration: all accounts migrated, overestimate fully resolves.
    function testFullMigration() external {
        h.setOzTotalSupply(200);
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
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
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();

        // A migrates through split 1.
        h.onAccountMigrated(0, 100, 1, 200);
        assertEq(h.effectiveTotalSupply(), 600);

        // Second split (3x).
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 2500, _splitParams(3));
        vm.warp(3000);
        h.fold();

        // totalSupply = floor(floor(200 * 2) * 3) + floor(200 * 3) + 0
        //             = 1200 + 600 = 1800
        assertEq(h.effectiveTotalSupply(), 1800);

        // B migrates from cursor 0 through both splits.
        h.onAccountMigrated(0, 100, 2, 600);
        assertEq(h.effectiveTotalSupply(), 1800);

        // A migrates from cursor 1 through split 2.
        h.onAccountMigrated(1, 200, 2, 600);
        assertEq(h.effectiveTotalSupply(), 1800);

        // C migrates from cursor 0.
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
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _fractionalParams(1, 3));
        vm.warp(2000);
        h.fold();

        assertEq(h.effectiveTotalSupply(), 3);

        // A migrates: stored=7, effective=2.
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
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();
        h.onMint(100);
        assertEq(h.effectiveTotalSupply(), 2100);
    }

    /// Burn after fold decreases the latest cursor pot.
    function testBurnAfterFold() external {
        h.setOzTotalSupply(1000);
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();
        h.onAccountMigrated(0, 1000, 1, 2000);
        h.onBurn(200);
        assertEq(h.effectiveTotalSupply(), 1800);
    }

    /// Fold is idempotent.
    function testFoldIdempotent() external {
        h.setOzTotalSupply(1000);
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();
        h.fold();
        assertEq(h.effectiveTotalSupply(), 2000);
        assertEq(h.unmigrated(0), 1000);
    }

    /// Virtual fold matches eager fold.
    function testVirtualMatchesEager() external {
        h.setOzTotalSupply(500);
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 2500, _splitParams(3));
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
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _fractionalParams(1, 3));
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 2500, _splitParams(3));
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 3500, _fractionalParams(1, 3));
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 4500, _splitParams(3));
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
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 2500, _splitParams(3));
        vm.warp(3000);
        h.fold();

        h.onAccountMigrated(0, 100, 2, 600);
        assertEq(h.effectiveTotalSupply(), 1200);

        h.onAccountMigrated(0, 100, 2, 600);
        assertEq(h.unmigrated(0), 0);
        assertEq(h.unmigrated(2), 1200);
        assertEq(h.effectiveTotalSupply(), 1200);
    }
}

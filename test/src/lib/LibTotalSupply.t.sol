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

    function onAccountMigrated(uint256 effectiveBalance) external {
        LibTotalSupply.onAccountMigrated(effectiveBalance);
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

    function ozTotalSupply() external view returns (uint256) {
        return LibERC20Storage.getTotalSupply();
    }

    function storageState() external view returns (uint256 unmigrated, uint256 migrated, uint256 cursor) {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        return (s.totalUnmigrated, s.totalMigrated, s.totalSupplyCursor);
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

    /// Eager fold writes to storage.
    function testEagerFold() external {
        h.setOzTotalSupply(1000);
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();
        (uint256 unmigrated, uint256 migrated, uint256 cursor) = h.storageState();
        assertEq(unmigrated, 2000);
        assertEq(migrated, 0);
        assertEq(cursor, 1);
    }

    /// Account migration moves balance from unmigrated to migrated.
    function testAccountMigration() external {
        h.setOzTotalSupply(200);
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();
        h.onAccountMigrated(200);
        (uint256 unmigrated, uint256 migrated,) = h.storageState();
        assertEq(unmigrated, 200);
        assertEq(migrated, 200);
        assertEq(h.effectiveTotalSupply(), 400);
    }

    /// Full migration: all accounts migrated, unmigrated goes to 0.
    function testFullMigration() external {
        h.setOzTotalSupply(200);
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();
        h.onAccountMigrated(200);
        h.onAccountMigrated(200);
        (uint256 unmigrated, uint256 migrated,) = h.storageState();
        assertEq(unmigrated, 0);
        assertEq(migrated, 400);
        assertEq(h.effectiveTotalSupply(), 400);
    }

    /// Fold on second split resets migrated to 0.
    function testSecondSplitFoldsBack() external {
        h.setOzTotalSupply(200);
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();
        h.onAccountMigrated(200);

        h.schedule(ACTION_TYPE_STOCK_SPLIT, 2500, _splitParams(3));
        vm.warp(3000);
        h.fold();
        (uint256 unmigrated, uint256 migrated, uint256 cursor) = h.storageState();
        assertEq(unmigrated, 1200);
        assertEq(migrated, 0);
        assertEq(cursor, 2);
        assertEq(h.effectiveTotalSupply(), 1200);
    }

    /// Mint after fold increases totalMigrated.
    function testMintAfterFold() external {
        h.setOzTotalSupply(1000);
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();
        h.onMint(100);
        assertEq(h.effectiveTotalSupply(), 2100);
    }

    /// Burn after fold decreases totalMigrated.
    function testBurnAfterFold() external {
        h.setOzTotalSupply(1000);
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);
        h.fold();
        h.onAccountMigrated(1000);
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

    /// Mint before any splits doesn't affect tracking (uses OZ directly).
    function testMintBeforeSplits() external {
        h.setOzTotalSupply(1000);
        h.onMint(500);
        assertEq(h.effectiveTotalSupply(), 1000);
    }
}

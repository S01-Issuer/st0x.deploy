// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
import {LibRebase} from "src/lib/LibRebase.sol";
import {LibCorporateAction, ACTION_TYPE_STOCK_SPLIT} from "src/lib/LibCorporateAction.sol";

contract LibRebaseHarness {
    function schedule(uint256 actionType, uint64 effectiveTime, bytes memory parameters) external returns (uint256) {
        return LibCorporateAction.schedule(actionType, effectiveTime, parameters);
    }

    function migratedBalance(uint256 storedBalance, uint256 cursor)
        external
        view
        returns (uint256 balance, uint256 newCursor)
    {
        return LibRebase.migratedBalance(storedBalance, cursor);
    }
}

contract LibRebaseTest is Test {
    LibRebaseHarness internal h;

    function setUp() public {
        h = new LibRebaseHarness();
        vm.warp(1000);
    }

    function _splitParams(int256 multiplier) internal pure returns (bytes memory) {
        return abi.encode(LibDecimalFloat.packLossless(multiplier, 0));
    }

    function _fractionalParams(int256 num, int256 denom) internal pure returns (bytes memory) {
        Float result = LibDecimalFloat.div(LibDecimalFloat.packLossless(num, 0), LibDecimalFloat.packLossless(denom, 0));
        return abi.encode(result);
    }

    /// Zero balance stays zero, but the cursor advances to the latest completed
    /// split. Otherwise a subsequent mint or transfer-in to this account would
    /// land at a stale cursor and the next read of `balanceOf` would re-apply
    /// the split multipliers, silently inflating the recipient's balance.
    /// See audit/2026-04-07-01/pass1/StoxReceiptVault.md::A03-1.
    function testZeroBalanceAdvancesCursor() external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);
        (uint256 balance, uint256 cursor) = h.migratedBalance(0, 0);
        assertEq(balance, 0);
        assertEq(cursor, 1);
    }

    /// Zero balance, multiple completed splits — cursor advances to the latest.
    function testZeroBalanceAdvancesCursorAcrossMultipleCompletedSplits() external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 2500, _splitParams(3));
        vm.warp(3000);
        (uint256 balance, uint256 cursor) = h.migratedBalance(0, 0);
        assertEq(balance, 0);
        assertEq(cursor, 2);
    }

    /// Zero balance with only pending (not yet effective) splits — cursor stays
    /// where it was, because we only walk completed nodes.
    function testZeroBalancePendingSplitDoesNotAdvanceCursor() external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 5000, _splitParams(2));
        (uint256 balance, uint256 cursor) = h.migratedBalance(0, 0);
        assertEq(balance, 0);
        assertEq(cursor, 0);
    }

    /// Zero balance with no splits scheduled at all — no-op.
    function testZeroBalanceNoSplits() external view {
        (uint256 balance, uint256 cursor) = h.migratedBalance(0, 0);
        assertEq(balance, 0);
        assertEq(cursor, 0);
    }

    /// No completed splits returns stored balance unchanged.
    function testNoCompletedSplits() external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 5000, _splitParams(2));
        (uint256 balance, uint256 cursor) = h.migratedBalance(100, 0);
        assertEq(balance, 100);
        assertEq(cursor, 0);
    }

    /// Simple 2x split doubles the balance.
    function testSimpleTwoXSplit() external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);
        (uint256 balance, uint256 cursor) = h.migratedBalance(100, 0);
        assertEq(balance, 200);
        assertEq(cursor, 1);
    }

    /// Simple 1/3 reverse split.
    function testOneThirdReverseSplit() external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _fractionalParams(1, 3));
        vm.warp(2000);
        (uint256 balance, uint256 cursor) = h.migratedBalance(100, 0);
        assertEq(balance, 33);
        assertEq(cursor, 1);
    }

    /// Sequential precision test: 1/3 x 3 x 1/3 x 3 applied to 100.
    function testSequentialPrecision() external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _fractionalParams(1, 3));
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 2500, _splitParams(3));
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 3500, _fractionalParams(1, 3));
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 4500, _splitParams(3));

        vm.warp(5000);
        (uint256 balance,) = h.migratedBalance(100, 0);
        assertEq(balance, 96);
    }

    /// Multiple splits applied in sequence.
    function testMultipleSplitsSequential() external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 2500, _splitParams(3));
        vm.warp(3000);
        (uint256 balance,) = h.migratedBalance(50, 0);
        assertEq(balance, 300);
    }

    /// Partial migration: cursor skips already-applied splits.
    function testPartialMigration() external {
        uint256 id1 = h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 2500, _splitParams(3));
        vm.warp(3000);
        (uint256 balance, uint256 cursor) = h.migratedBalance(100, id1);
        assertEq(balance, 300);
        assertEq(cursor, 2);
    }

    /// Cursor already at latest completed node returns balance unchanged.
    function testAlreadyMigrated() external {
        uint256 id = h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);
        (uint256 balance, uint256 cursor) = h.migratedBalance(100, id);
        assertEq(balance, 100);
        assertEq(cursor, id);
    }

    /// Fuzz: 2x split always doubles.
    function testFuzzTwoXSplit(uint128 balance) external {
        vm.assume(balance > 0);
        h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
        vm.warp(2000);
        (uint256 result,) = h.migratedBalance(uint256(balance), 0);
        assertEq(result, uint256(balance) * 2);
    }

    /// Fuzz: sequential 2x splits.
    function testFuzzSequentialTwoX(uint64 balance, uint8 splitCount) external {
        vm.assume(balance > 0 && balance < type(uint64).max / 4);
        splitCount = uint8(bound(splitCount, 1, 5));

        for (uint256 i = 0; i < splitCount; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            h.schedule(ACTION_TYPE_STOCK_SPLIT, uint64(1500 + i * 1000), _splitParams(2));
        }

        vm.warp(1500 + uint256(splitCount) * 1000);
        (uint256 result,) = h.migratedBalance(uint256(balance), 0);
        assertEq(result, uint256(balance) * (2 ** splitCount));
    }
}

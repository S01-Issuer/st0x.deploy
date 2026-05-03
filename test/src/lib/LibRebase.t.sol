// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
import {LibRebase} from "src/lib/LibRebase.sol";
import {LibCorporateAction} from "src/lib/LibCorporateAction.sol";
import {ACTION_TYPE_STOCK_SPLIT_V1} from "src/interface/ICorporateActionsV1.sol";
import {LibStockSplit} from "src/lib/LibStockSplit.sol";

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
        return LibStockSplit.encodeParametersV1(LibDecimalFloat.packLossless(multiplier, 0));
    }

    function _fractionalParams(int256 num, int256 denom) internal pure returns (bytes memory) {
        Float result = LibDecimalFloat.div(LibDecimalFloat.packLossless(num, 0), LibDecimalFloat.packLossless(denom, 0));
        return LibStockSplit.encodeParametersV1(result);
    }

    /// Zero balance stays zero, but the cursor advances to the latest completed
    /// split. Otherwise a subsequent mint or transfer-in to this account would
    /// land at a stale cursor and the next read of `balanceOf` would re-apply
    /// the split multipliers, silently inflating the recipient's balance.
    function testZeroBalanceAdvancesCursor() external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);
        (uint256 balance, uint256 cursor) = h.migratedBalance(0, 0);
        assertEq(balance, 0);
        // Bootstrap is at idx 1, the user-scheduled split at idx 2; the
        // walk advances through both completed migration nodes.
        assertEq(cursor, 2);
    }

    /// Zero balance, multiple completed splits — cursor advances to the latest.
    function testZeroBalanceAdvancesCursorAcrossMultipleCompletedSplits() external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(3));
        vm.warp(3000);
        (uint256 balance, uint256 cursor) = h.migratedBalance(0, 0);
        assertEq(balance, 0);
        // Bootstrap at idx 1, two splits at idx 2 and 3.
        assertEq(cursor, 3);
    }

    /// Zero balance with only pending (not yet effective) splits — the
    /// bootstrap node is always completed at schedule time, so the cursor
    /// still advances past it. No further completed splits → walk stops at
    /// the bootstrap.
    function testZeroBalancePendingSplitDoesNotAdvanceCursor() external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 5000, _splitParams(2));
        (uint256 balance, uint256 cursor) = h.migratedBalance(0, 0);
        assertEq(balance, 0);
        // Bootstrap (idx 1) is completed at schedule time; pending split
        // (idx 2) is not.
        assertEq(cursor, 1);
    }

    /// Zero balance with no splits scheduled at all — no-op (bootstrap has
    /// not fired because no schedule call has run).
    function testZeroBalanceNoSplits() external view {
        (uint256 balance, uint256 cursor) = h.migratedBalance(0, 0);
        assertEq(balance, 0);
        assertEq(cursor, 0);
    }

    /// No completed splits returns stored balance unchanged. The bootstrap
    /// node (idx 1) is completed at schedule time, so the cursor still
    /// advances past it via identity migration.
    function testNoCompletedSplits() external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 5000, _splitParams(2));
        (uint256 balance, uint256 cursor) = h.migratedBalance(100, 0);
        assertEq(balance, 100);
        assertEq(cursor, 1);
    }

    /// Simple 2x split doubles the balance.
    function testSimpleTwoXSplit() external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);
        (uint256 balance, uint256 cursor) = h.migratedBalance(100, 0);
        assertEq(balance, 200);
        // Bootstrap at idx 1 (identity), split at idx 2.
        assertEq(cursor, 2);
    }

    /// Simple 1/3 reverse split.
    function testOneThirdReverseSplit() external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _fractionalParams(1, 3));
        vm.warp(2000);
        (uint256 balance, uint256 cursor) = h.migratedBalance(100, 0);
        assertEq(balance, 33);
        assertEq(cursor, 2);
    }

    /// Sequential precision test: 1/3 x 3 x 1/3 x 3 applied to 100.
    function testSequentialPrecision() external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _fractionalParams(1, 3));
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(3));
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 3500, _fractionalParams(1, 3));
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 4500, _splitParams(3));

        vm.warp(5000);
        (uint256 balance,) = h.migratedBalance(100, 0);
        assertEq(balance, 96);
    }

    /// Multiple splits applied in sequence.
    function testMultipleSplitsSequential() external {
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(3));
        vm.warp(3000);
        (uint256 balance,) = h.migratedBalance(50, 0);
        assertEq(balance, 300);
    }

    /// Partial migration: cursor skips already-applied splits.
    function testPartialMigration() external {
        uint256 id1 = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        uint256 id2 = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _splitParams(3));
        vm.warp(3000);
        (uint256 balance, uint256 cursor) = h.migratedBalance(100, id1);
        assertEq(balance, 300);
        assertEq(cursor, id2);
    }

    /// Cursor already at latest completed node returns balance unchanged.
    function testAlreadyMigrated() external {
        uint256 id = h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);
        (uint256 balance, uint256 cursor) = h.migratedBalance(100, id);
        assertEq(balance, 100);
        assertEq(cursor, id);
    }

    /// Fuzz: 2x split always doubles.
    function testFuzzTwoXSplit(uint128 balance) external {
        vm.assume(balance > 0);
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
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
            h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, uint64(1500 + i * 1000), _splitParams(2));
        }

        vm.warp(1500 + uint256(splitCount) * 1000);
        (uint256 result,) = h.migratedBalance(uint256(balance), 0);
        assertEq(result, uint256(balance) * (2 ** splitCount));
    }

    /// Fuzz: randomized fractional multiplier (num/denom). Verifies that a
    /// single fractional split produces the same result as the reference
    /// computation: `trunc(balance * num / denom)` using Rain Float arithmetic.
    /// This catches regressions where the Float representation of a fraction
    /// diverges from the expected integer-truncation behavior.
    function testFuzzFractionalMultiplier(uint64 balance, uint8 numSeed, uint8 denomSeed) external {
        vm.assume(balance > 0 && balance < 1e15);
        // Bound numerator to [1, 20] and denominator to [1, 20] to stay within
        // the multiplier validation bounds while covering a wide range of
        // fractional values.
        int256 num = int256(uint256(bound(numSeed, 1, 20)));
        int256 denom = int256(uint256(bound(denomSeed, 1, 20)));

        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _fractionalParams(num, denom));
        vm.warp(2000);

        (uint256 result,) = h.migratedBalance(uint256(balance), 0);

        // Reference: apply the same Float multiplication manually.
        Float multiplier =
            LibDecimalFloat.div(LibDecimalFloat.packLossless(num, 0), LibDecimalFloat.packLossless(denom, 0));
        // forge-lint: disable-next-line(unsafe-typecast)
        (uint256 expected,) = LibDecimalFloat.toFixedDecimalLossy(
            LibDecimalFloat.mul(LibDecimalFloat.packLossless(int256(uint256(balance)), 0), multiplier), 0
        );

        assertEq(result, expected, "fractional multiplier must match reference Float computation");
    }

    /// Fuzz: two sequential fractional multipliers. Verifies the "no cumulative
    /// product" invariant — the sequential result (rasterize after each step)
    /// must match applying each multiplier independently with truncation between
    /// steps. This would FAIL if the implementation collapsed multipliers into a
    /// single product.
    function testFuzzSequentialFractionalNoCumulativeProduct(uint64 balance, uint8 n1, uint8 d1, uint8 n2, uint8 d2)
        external
    {
        vm.assume(balance > 100 && balance < 1e12);
        int256 num1 = int256(uint256(bound(n1, 1, 10)));
        int256 denom1 = int256(uint256(bound(d1, 1, 10)));
        int256 num2 = int256(uint256(bound(n2, 1, 10)));
        int256 denom2 = int256(uint256(bound(d2, 1, 10)));

        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _fractionalParams(num1, denom1));
        h.schedule(ACTION_TYPE_STOCK_SPLIT_V1, 2500, _fractionalParams(num2, denom2));
        vm.warp(3000);

        (uint256 result,) = h.migratedBalance(uint256(balance), 0);

        // Reference: apply each multiplier sequentially with truncation between.
        Float m1 = LibDecimalFloat.div(LibDecimalFloat.packLossless(num1, 0), LibDecimalFloat.packLossless(denom1, 0));
        Float m2 = LibDecimalFloat.div(LibDecimalFloat.packLossless(num2, 0), LibDecimalFloat.packLossless(denom2, 0));

        // Step 1: apply m1, truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        (uint256 afterFirst,) = LibDecimalFloat.toFixedDecimalLossy(
            LibDecimalFloat.mul(LibDecimalFloat.packLossless(int256(uint256(balance)), 0), m1), 0
        );
        // Step 2: apply m2, truncate. afterFirst is fuzzer-bounded to
        // stay well within Float coefficient limits.
        (uint256 expected,) = LibDecimalFloat.toFixedDecimalLossy(
            // forge-lint: disable-next-line(unsafe-typecast)
            LibDecimalFloat.mul(LibDecimalFloat.packLossless(int256(afterFirst), 0), m2),
            0
        );

        assertEq(result, expected, "sequential rasterization must match step-by-step reference");
    }
}

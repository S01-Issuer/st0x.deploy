// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
import {LibReceiptRebase} from "src/lib/LibReceiptRebase.sol";
import {ICorporateActionsV1} from "src/interface/ICorporateActionsV1.sol";
import {MockCorporateActionsVault} from "./MockCorporateActionsVault.sol";

/// @dev Test suite for `LibReceiptRebase.migratedBalance`. Mirrors
/// `LibRebase.t.sol` structure so the two sides stay in lockstep.
contract LibReceiptRebaseTest is Test {
    MockCorporateActionsVault internal vault;

    function setUp() public {
        vault = new MockCorporateActionsVault();
    }

    function _integerSplit(int256 multiplier) internal {
        vault.addSplit(LibDecimalFloat.packLossless(multiplier, 0));
    }

    function _fractionalSplit(int256 num, int256 denom) internal {
        Float frac = LibDecimalFloat.div(LibDecimalFloat.packLossless(num, 0), LibDecimalFloat.packLossless(denom, 0));
        vault.addSplit(frac);
    }

    /// Empty list, any starting cursor — no-op.
    function testNoSplitsReturnsUnchanged() external view {
        (uint256 balance, uint256 cursor) =
            LibReceiptRebase.migratedBalance(100, 0, ICorporateActionsV1(address(vault)));
        assertEq(balance, 100);
        assertEq(cursor, 0);
    }

    /// Single 2x split — balance doubles.
    function testSimpleTwoXSplit() external {
        _integerSplit(2);
        (uint256 balance, uint256 cursor) =
            LibReceiptRebase.migratedBalance(100, 0, ICorporateActionsV1(address(vault)));
        assertEq(balance, 200);
        assertEq(cursor, 1);
    }

    /// Already-migrated cursor on the only completed split — no-op, cursor
    /// unchanged.
    function testAlreadyAtCursorIsNoOp() external {
        _integerSplit(2);
        (uint256 balance, uint256 cursor) =
            LibReceiptRebase.migratedBalance(200, 1, ICorporateActionsV1(address(vault)));
        assertEq(balance, 200);
        assertEq(cursor, 1);
    }

    /// Multiple splits applied sequentially — 2x then 3x → 6x.
    function testMultipleSplitsSequential() external {
        _integerSplit(2);
        _integerSplit(3);
        (uint256 balance, uint256 cursor) = LibReceiptRebase.migratedBalance(50, 0, ICorporateActionsV1(address(vault)));
        assertEq(balance, 300);
        assertEq(cursor, 2);
    }

    /// Partial migration: cursor already past the first split, only the
    /// second is applied.
    function testPartialMigration() external {
        _integerSplit(2);
        _integerSplit(3);
        (uint256 balance, uint256 cursor) =
            LibReceiptRebase.migratedBalance(100, 1, ICorporateActionsV1(address(vault)));
        assertEq(balance, 300);
        assertEq(cursor, 2);
    }

    /// Zero balance still advances the cursor so a subsequent write to
    /// this (holder, id) lands at the latest cursor instead of a stale
    /// one, preventing the next `balanceOf` read from re-applying every
    /// completed multiplier to an already-rebased balance.
    function testZeroBalanceAdvancesCursor() external {
        _integerSplit(2);
        (uint256 balance, uint256 cursor) = LibReceiptRebase.migratedBalance(0, 0, ICorporateActionsV1(address(vault)));
        assertEq(balance, 0);
        assertEq(cursor, 1);
    }

    /// Zero balance advances cursor across multiple completed splits.
    function testZeroBalanceAdvancesCursorAcrossMultipleCompletedSplits() external {
        _integerSplit(2);
        _integerSplit(3);
        _integerSplit(2);
        (uint256 balance, uint256 cursor) = LibReceiptRebase.migratedBalance(0, 0, ICorporateActionsV1(address(vault)));
        assertEq(balance, 0);
        assertEq(cursor, 3, "cursor must advance all the way to the last completed split");
    }

    /// Zero balance with no splits is a pure no-op.
    function testZeroBalanceNoSplits() external view {
        (uint256 balance, uint256 cursor) = LibReceiptRebase.migratedBalance(0, 0, ICorporateActionsV1(address(vault)));
        assertEq(balance, 0);
        assertEq(cursor, 0);
    }

    /// Sequential application of 1/3 * 3 * 1/3 * 3 to a stored 100
    /// produces 96, not 100. Float's 1/3 is slightly less than exact 1/3,
    /// so 99 * 1/3_float rounds down to 32 rather than 33, which then
    /// multiplies by 3 to 96. The receipt side must produce the same
    /// sequence as the share side — both use `LibRebaseMath.applyMultiplier`
    /// — so any drift here breaks share↔receipt proportionality.
    function testSequentialPrecision() external {
        _fractionalSplit(1, 3);
        _integerSplit(3);
        _fractionalSplit(1, 3);
        _integerSplit(3);

        (uint256 balance, uint256 cursor) =
            LibReceiptRebase.migratedBalance(100, 0, ICorporateActionsV1(address(vault)));
        assertEq(balance, 96, "receipt-side sequential precision must match share side exactly");
        assertEq(cursor, 4);
    }

    /// Fuzz: a range of integer multipliers applied in sequence gives the
    /// same answer as a direct Solidity multiplication, confirming no
    /// surprises in the cross-contract walk.
    function testFuzzIntegerMultipliersMatchDirectProduct(uint64 initial, uint8 mulSeed) external {
        vm.assume(initial > 0 && initial < 1e12);
        // Both bucket seeds are in [1, 5]; safe to cast to int256/uint256
        // without any width concerns.
        uint256 m1 = uint256(mulSeed % 5) + 1;
        uint256 m2 = uint256((mulSeed >> 3) % 5) + 1;

        // forge-lint: disable-next-line(unsafe-typecast)
        _integerSplit(int256(m1));
        // forge-lint: disable-next-line(unsafe-typecast)
        _integerSplit(int256(m2));

        (uint256 balance,) = LibReceiptRebase.migratedBalance(initial, 0, ICorporateActionsV1(address(vault)));

        uint256 expected = uint256(initial) * m1 * m2;
        assertEq(balance, expected, "integer-multiplier walk must equal direct product");
    }
}

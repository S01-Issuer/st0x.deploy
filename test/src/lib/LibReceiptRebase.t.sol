// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
import {LibReceiptRebase} from "src/lib/LibReceiptRebase.sol";
import {ICorporateActionsV1, ACTION_TYPE_STOCK_SPLIT_V1} from "src/interface/ICorporateActionsV1.sol";
import {CompletionFilter} from "src/lib/LibCorporateActionNode.sol";

/// @dev Mock vault exposing only the subset of `ICorporateActionsV1` that
/// `LibReceiptRebase` consumes (`nextOfType` + `getActionParameters`). Tests
/// preload the mock with a list of completed stock split multipliers, and
/// the receipt rebase walks it exactly as if it were a real vault.
///
/// The mock assigns sequential 1-based cursor indices to the preloaded
/// multipliers, mirroring the vault's storage layout: index 0 is the
/// sentinel (no node), indices 1..n are the stock splits in effective-time
/// order. `nextOfType` returns the next index; `getActionParameters` returns
/// the stored bytes.
contract MockCorporateActionsVault is ICorporateActionsV1 {
    bytes[] internal splits; // splits[i-1] is the parameters blob for cursor i

    function addSplit(Float multiplier) external {
        splits.push(abi.encode(multiplier));
    }

    function addSplitRaw(bytes memory parameters) external {
        splits.push(parameters);
    }

    function splitCount() external view returns (uint256) {
        return splits.length;
    }

    // -----------------------------------------------------------------------
    // ICorporateActionsV1 — only the bits LibReceiptRebase calls

    function nextOfType(uint256 cursor, uint256 mask, CompletionFilter filter)
        external
        view
        override
        returns (uint256 nextCursor, uint256 actionType, uint64 effectiveTime)
    {
        // Only the mask == ACTION_TYPE_STOCK_SPLIT_V1, filter == COMPLETED path
        // is tested here; assert any other request so misuse fails loud.
        require(mask == ACTION_TYPE_STOCK_SPLIT_V1, "mock: unexpected mask");
        require(filter == CompletionFilter.COMPLETED, "mock: unexpected filter");

        // Cursor is the 1-based index of the last visited split. Next is
        // cursor + 1 if it exists, else 0.
        uint256 candidate = cursor + 1;
        if (candidate > splits.length) {
            return (0, 0, 0);
        }
        return (candidate, ACTION_TYPE_STOCK_SPLIT_V1, 1);
    }

    function getActionParameters(uint256 cursor) external view override returns (bytes memory parameters) {
        require(cursor >= 1 && cursor <= splits.length, "mock: cursor out of range");
        return splits[cursor - 1];
    }

    // Unused ICorporateActionsV1 surface — revert to surface misuse.
    function scheduleCorporateAction(bytes32, uint64, bytes calldata) external pure override returns (uint256) {
        revert("mock: not implemented");
    }

    function cancelCorporateAction(uint256) external pure override {
        revert("mock: not implemented");
    }

    function completedActionCount() external view override returns (uint256) {
        return splits.length;
    }

    function latestActionOfType(uint256, CompletionFilter) external pure override returns (uint256, uint256, uint64) {
        revert("mock: not implemented");
    }

    function earliestActionOfType(uint256, CompletionFilter) external pure override returns (uint256, uint256, uint64) {
        revert("mock: not implemented");
    }

    function prevOfType(uint256, uint256, CompletionFilter) external pure override returns (uint256, uint256, uint64) {
        revert("mock: not implemented");
    }
}

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

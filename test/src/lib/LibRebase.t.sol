// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
import {LibRebase} from "src/lib/LibRebase.sol";
import {LibCorporateAction} from "src/lib/LibCorporateAction.sol";

/// @dev Harness to expose LibRebase internal functions.
contract LibRebaseHarness {
    /// @dev Set a multiplier at a given rebase ID for testing.
    function setMultiplier(uint256 rebaseId, Float multiplier) external {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        s.multipliers[rebaseId] = multiplier;
        if (rebaseId > s.rebaseCount) {
            s.rebaseCount = rebaseId;
        }
    }

    function effectiveBalance(uint256 storedBalance, uint256 fromRebaseId, uint256 toRebaseId)
        external
        view
        returns (uint256)
    {
        return LibRebase.effectiveBalance(storedBalance, fromRebaseId, toRebaseId);
    }

    function rebaseCount() external view returns (uint256) {
        return LibCorporateAction.getStorage().rebaseCount;
    }
}

contract LibRebaseTest is Test {
    LibRebaseHarness harness;

    function setUp() external {
        harness = new LibRebaseHarness();
    }

    /// Zero balance stays zero regardless of multipliers.
    function testZeroBalanceUnchanged() external {
        Float twoX = LibDecimalFloat.packLossless(2, 0);
        harness.setMultiplier(1, twoX);
        assertEq(harness.effectiveBalance(0, 0, 1), 0);
    }

    /// No rebases pending returns stored balance unchanged.
    function testNoRebasesPending() external view {
        assertEq(harness.effectiveBalance(100, 0, 0), 100);
    }

    /// Simple 2x split doubles the balance.
    function testSimpleTwoXSplit() external {
        Float twoX = LibDecimalFloat.packLossless(2, 0);
        harness.setMultiplier(1, twoX);
        assertEq(harness.effectiveBalance(100, 0, 1), 200);
    }

    /// Simple 1/3 reverse split.
    function testOneThirdReverseSplit() external {
        Float oneThird = LibDecimalFloat.packLossless(1, 0);
        oneThird = LibDecimalFloat.div(oneThird, LibDecimalFloat.packLossless(3, 0));
        harness.setMultiplier(1, oneThird);
        assertEq(harness.effectiveBalance(100, 0, 1), 33);
    }

    /// Sequential precision test: 1/3 × 3 × 1/3 × 3 applied to 100.
    /// Must yield 99 (not 100) due to accumulated rounding.
    function testSequentialPrecision() external {
        Float oneThird = LibDecimalFloat.div(
            LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(3, 0)
        );
        Float threeX = LibDecimalFloat.packLossless(3, 0);
        harness.setMultiplier(1, oneThird);
        harness.setMultiplier(2, threeX);
        harness.setMultiplier(3, oneThird);
        harness.setMultiplier(4, threeX);

        uint256 result = harness.effectiveBalance(100, 0, 4);
        // Sequential: 100 * 1/3 = 33, * 3 = 99, * 1/3 = 33, * 3 = 99
        assertEq(result, 99);
    }

    /// Multiple splits applied in sequence.
    function testMultipleSplitsSequential() external {
        Float twoX = LibDecimalFloat.packLossless(2, 0);
        Float threeX = LibDecimalFloat.packLossless(3, 0);
        harness.setMultiplier(1, twoX);
        harness.setMultiplier(2, threeX);
        // 50 * 2 = 100, * 3 = 300
        assertEq(harness.effectiveBalance(50, 0, 2), 300);
    }

    /// Partial migration: only applies multipliers from the account's version.
    function testPartialMigration() external {
        Float twoX = LibDecimalFloat.packLossless(2, 0);
        Float threeX = LibDecimalFloat.packLossless(3, 0);
        harness.setMultiplier(1, twoX);
        harness.setMultiplier(2, threeX);
        // Account already at version 1, only applies 3x.
        assertEq(harness.effectiveBalance(100, 1, 2), 300);
    }

    /// fromRebaseId >= toRebaseId returns stored balance unchanged.
    function testAlreadyMigrated() external view {
        assertEq(harness.effectiveBalance(100, 2, 2), 100);
        assertEq(harness.effectiveBalance(100, 3, 2), 100);
    }

    /// Fuzz: effective balance with a single 2x multiplier always doubles.
    function testFuzzTwoXSplit(uint128 balance) external {
        vm.assume(balance > 0);
        Float twoX = LibDecimalFloat.packLossless(2, 0);
        harness.setMultiplier(1, twoX);
        uint256 result = harness.effectiveBalance(uint256(balance), 0, 1);
        assertEq(result, uint256(balance) * 2);
    }

    /// Fuzz: sequential precision — result should always match step-by-step.
    function testFuzzSequentialApplication(uint64 balance, uint8 splitCount) external {
        vm.assume(balance > 0 && balance < type(uint64).max / 4);
        splitCount = uint8(bound(splitCount, 1, 5));

        Float twoX = LibDecimalFloat.packLossless(2, 0);
        for (uint256 i = 1; i <= splitCount; i++) {
            harness.setMultiplier(i, twoX);
        }

        uint256 result = harness.effectiveBalance(uint256(balance), 0, splitCount);
        assertEq(result, uint256(balance) * (2 ** splitCount));
    }
}

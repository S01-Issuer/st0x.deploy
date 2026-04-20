// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
import {LibRebaseMath} from "src/lib/LibRebaseMath.sol";
import {BalanceExceedsInt256Max} from "src/error/ErrRebase.sol";

contract LibRebaseMathHarness {
    function applyMultiplier(uint256 balance, Float multiplier) external pure returns (uint256) {
        return LibRebaseMath.applyMultiplier(balance, multiplier);
    }
}

contract LibRebaseMathTest is Test {
    LibRebaseMathHarness internal h;

    function setUp() public {
        h = new LibRebaseMathHarness();
    }

    /// Apply 2x to a normal balance.
    function testApplyTwoXSplit() external view {
        Float twoX = LibDecimalFloat.packLossless(2, 0);
        assertEq(h.applyMultiplier(100, twoX), 200);
    }

    /// Apply 1/3 to 99 gives 32 (not 33) because Rain Float's 1/3 is slightly
    /// less than exact 1/3, and rasterization truncates toward zero. This is
    /// the same sequential-precision behavior documented in LibRebase.
    function testApplyOneThirdTruncates() external view {
        Float oneThird = LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(3, 0));
        assertEq(h.applyMultiplier(99, oneThird), 32);
    }

    /// Zero balance returns zero.
    function testApplyToZero() external view {
        Float twoX = LibDecimalFloat.packLossless(2, 0);
        assertEq(h.applyMultiplier(0, twoX), 0);
    }

    /// Balance above type(int256).max reverts with BalanceExceedsInt256Max
    /// before the silent int256 wraparound would occur.
    function testApplyAboveInt256MaxReverts() external {
        Float one = LibDecimalFloat.packLossless(1, 0);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 tooLarge = uint256(type(int256).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(BalanceExceedsInt256Max.selector, tooLarge));
        h.applyMultiplier(tooLarge, one);
    }

    /// Max uint256 reverts with BalanceExceedsInt256Max.
    function testApplyMaxUint256Reverts() external {
        Float one = LibDecimalFloat.packLossless(1, 0);
        vm.expectRevert(abi.encodeWithSelector(BalanceExceedsInt256Max.selector, type(uint256).max));
        h.applyMultiplier(type(uint256).max, one);
    }

    /// Fuzz: any balance within the Float coefficient range (type(int224).max)
    /// with a 1x multiplier is idempotent.
    function testFuzzIdentityMultiplier(uint256 balance) external view {
        // forge-lint: disable-next-line(unsafe-typecast)
        balance = bound(balance, 0, uint256(uint224(type(int224).max)));
        Float one = LibDecimalFloat.packLossless(1, 0);
        assertEq(h.applyMultiplier(balance, one), balance);
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {Math} from "@openzeppelin-contracts-5.6.1/utils/math/Math.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
import {LibMintCapUnits} from "../../../src/lib/LibMintCapUnits.sol";
import {AmountNotRepresentableAsFloat, NonPositiveDenomination} from "../../../src/error/ErrMintCapUnits.sol";
import {MintCapUnitsHarness} from "../../concrete/MintCapUnitsHarness.sol";

/// Both directions are asserted against integer arithmetic built from
/// `Math.mulDiv`, never against the `Float` path under test: with
/// denominations written as `n / 1e6`, redenominating is `amount × to / from`,
/// expressible in `uint256` without touching `LibDecimalFloat`.
contract LibMintCapUnitsTest is Test {
    uint256 internal constant SCALE = 1e6;

    MintCapUnitsHarness internal harness;

    function setUp() external {
        harness = new MintCapUnitsHarness();
    }

    function denomination(uint256 units) internal pure returns (Float) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return LibDecimalFloat.packLossless(int256(units), -6);
    }

    /// Converting between one denomination and itself is the no-action case,
    /// which every bucket hits on every mint that follows no corporate action.
    /// It has to be exact or a cap drifts while nothing happens.
    function testSameDenominationIsExact(uint256 amount, uint256 units) external pure {
        amount = bound(amount, 0, 1e30);
        units = bound(units, 1, 1e12);
        Float m = denomination(units);
        assertEq(LibMintCapUnits.redenominateUp(amount, m, m), amount, "up");
        assertEq(LibMintCapUnits.redenominateDown(amount, m, m), amount, "down");
    }

    /// A 2:1 forward split doubles balances, so a quantity worth 100 at the old
    /// denomination is worth 200 at the new one.
    function testForwardSplitDoublesTheQuantity() external pure {
        Float before = denomination(1e6);
        Float dAfter = denomination(2e6);
        assertEq(LibMintCapUnits.redenominateUp(100e18, before, dAfter), 200e18);
        assertEq(LibMintCapUnits.redenominateDown(200e18, dAfter, before), 100e18);
    }

    /// A 1-for-10 consolidation shrinks balances tenfold. This is the direction
    /// that loosens a cap when nothing converts.
    function testConsolidationShrinksTheQuantity() external pure {
        Float before = denomination(1e6);
        Float dAfter = denomination(1e5);
        assertEq(LibMintCapUnits.redenominateDown(100e18, before, dAfter), 10e18);
        assertEq(LibMintCapUnits.redenominateUp(10e18, dAfter, before), 100e18);
    }

    /// Wei-scale rounding stated as exact values. Going from a denomination to
    /// one a third its size, the exact quotients are 1/3, 2/3, 1 and 4/3; a
    /// charge is 1, 1, 1, 2. Truncation would charge 0, 0, 1, 1 — the first two
    /// of which are free mints.
    function testUpRoundsUpAtWeiScale() external pure {
        Float from = denomination(3e6);
        Float to = denomination(1e6);
        assertEq(LibMintCapUnits.redenominateUp(1, from, to), 1);
        assertEq(LibMintCapUnits.redenominateUp(2, from, to), 1);
        assertEq(LibMintCapUnits.redenominateUp(3, from, to), 1);
        assertEq(LibMintCapUnits.redenominateUp(4, from, to), 2);
    }

    /// Rounding up must not invent a charge where there is nothing to charge,
    /// or a zero-amount call would consume a unit of every bucket it touches.
    function testZeroConvertsToZero(uint256 from, uint256 to) external pure {
        from = bound(from, 1, 1e12);
        to = bound(to, 1, 1e12);
        assertEq(LibMintCapUnits.redenominateUp(0, denomination(from), denomination(to)), 0);
        assertEq(LibMintCapUnits.redenominateDown(0, denomination(from), denomination(to)), 0);
    }

    function testUpIsCeilingOfAmountTimesToOverFrom(uint256 amount, uint256 from, uint256 to) external pure {
        amount = bound(amount, 0, 1e24);
        from = bound(from, 1, 1e9);
        to = bound(to, 1, 1e9);
        assertEq(
            LibMintCapUnits.redenominateUp(amount, denomination(from), denomination(to)),
            Math.mulDiv(amount, to, from, Math.Rounding.Ceil)
        );
    }

    function testDownIsFloorOfAmountTimesToOverFrom(uint256 amount, uint256 from, uint256 to) external pure {
        amount = bound(amount, 0, 1e24);
        from = bound(from, 1, 1e9);
        to = bound(to, 1, 1e9);
        assertEq(
            LibMintCapUnits.redenominateDown(amount, denomination(from), denomination(to)),
            Math.mulDiv(amount, to, from)
        );
    }

    /// The property the round-up exists for: what a bucket is charged is never
    /// worth less, converted back, than the amount that was minted. A single
    /// wei of slack is a partly-free mint, repeatable as often as the minter
    /// splits its mints.
    function testChargingNeverUndercharges(uint256 amount, uint256 from, uint256 to) external pure {
        amount = bound(amount, 0, 1e24);
        from = bound(from, 1, 1e9);
        to = bound(to, 1, 1e9);
        Float f = denomination(from);
        Float t = denomination(to);
        assertGe(LibMintCapUnits.redenominateDown(LibMintCapUnits.redenominateUp(amount, f, t), t, f), amount);
    }

    /// The property the round-down exists for: the headroom a view reports
    /// still fits the headroom it came from, so `mintHeadroom` never names an
    /// amount the next `mint` refuses.
    function testReportedHeadroomStillFits(uint256 headroom, uint256 from, uint256 to) external pure {
        headroom = bound(headroom, 0, 1e24);
        from = bound(from, 1, 1e9);
        to = bound(to, 1, 1e9);
        Float f = denomination(from);
        Float t = denomination(to);
        assertLe(LibMintCapUnits.redenominateUp(LibMintCapUnits.redenominateDown(headroom, f, t), t, f), headroom);
    }

    /// An amount too wide for the `Float` coefficient is refused rather than
    /// truncated toward zero, which on a charged amount would be a discount
    /// applied before the round-up could correct it.
    function testTooWideAmountIsRefusedNotTruncated() external {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 tooWide = uint256(uint224(type(int224).max)) + 1;
        Float one = denomination(1e6);
        vm.expectRevert(abi.encodeWithSelector(AmountNotRepresentableAsFloat.selector, tooWide));
        harness.redenominateUp(tooWide, one, one);
        vm.expectRevert(abi.encodeWithSelector(AmountNotRepresentableAsFloat.selector, tooWide));
        harness.redenominateDown(tooWide, one, one);
    }

    /// A zero denomination is an unset limit or an unused bucket, never a real
    /// multiplier. Converting against one fails closed rather than dividing by
    /// zero or silently metering at par.
    function testZeroDenominationFailsClosed() external {
        Float zero = LibDecimalFloat.packLossless(0, 0);
        Float one = denomination(1e6);
        vm.expectRevert(abi.encodeWithSelector(NonPositiveDenomination.selector, zero));
        harness.redenominateUp(1e18, zero, one);
        vm.expectRevert(abi.encodeWithSelector(NonPositiveDenomination.selector, zero));
        harness.redenominateUp(1e18, one, zero);
    }
}

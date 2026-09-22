// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {Math} from "@openzeppelin-contracts-5.6.1/utils/math/Math.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
import {LibMintCapUnits} from "../../../src/lib/LibMintCapUnits.sol";
import {AmountNotRepresentableAsFloat} from "../../../src/error/ErrMintCapUnits.sol";
import {MintCapUnitsHarness} from "../../concrete/MintCapUnitsHarness.sol";

/// Both directions are asserted against integer arithmetic built from
/// `Math.mulDiv`, never against the `Float` path under test: a multiplier
/// written as `mUnits / 1e6` makes `toGenesis` a ceiling division and
/// `toCurrent` a floor multiplication, both expressible in `uint256` without
/// touching `LibDecimalFloat`.
contract LibMintCapUnitsTest is Test {
    /// The scale the fuzz multipliers are written at: `m = mUnits / SCALE`.
    uint256 internal constant SCALE = 1e6;

    MintCapUnitsHarness internal harness;

    function setUp() external {
        harness = new MintCapUnitsHarness();
    }

    function multiplier(uint256 mUnits) internal pure returns (Float) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return LibDecimalFloat.packLossless(int256(mUnits), -6);
    }

    /// An identity multiplier is the pre-action state every token starts in,
    /// so it has to be exact in both directions or every cap is wrong before
    /// a single corporate action exists.
    function testIdentityMultiplierIsExactBothWays(uint256 amount) external pure {
        amount = bound(amount, 0, 1e30);
        Float one = LibDecimalFloat.packLossless(1, 0);
        assertEq(LibMintCapUnits.toGenesis(amount, one), amount, "toGenesis identity");
        assertEq(LibMintCapUnits.toCurrent(amount, one), amount, "toCurrent identity");
    }

    /// A 2:1 forward split: balances double, so one current unit is worth half
    /// a genesis unit and 200 current is 100 genesis.
    function testForwardSplitHalvesGenesisValue() external pure {
        Float m = LibDecimalFloat.packLossless(2, 0);
        assertEq(LibMintCapUnits.toGenesis(200e18, m), 100e18);
        assertEq(LibMintCapUnits.toCurrent(100e18, m), 200e18);
    }

    /// A 1-for-10 consolidation: balances shrink tenfold, so 10 current units
    /// are worth 100 genesis. This is the direction that loosens a cap if the
    /// conversion is missing entirely.
    function testConsolidationRaisesGenesisValue() external pure {
        Float m = LibDecimalFloat.packLossless(1, -1);
        assertEq(LibMintCapUnits.toGenesis(10e18, m), 100e18);
        assertEq(LibMintCapUnits.toCurrent(100e18, m), 10e18);
    }

    /// Wei-scale rounding, stated as exact values rather than a property: with
    /// `m = 3` the exact quotients are 1/3, 2/3, 1 and 4/3, so a consumed
    /// amount is charged 1, 1, 1 and 2 genesis units. Truncation would charge
    /// 0, 0, 1, 1 — the first two of which are free mints.
    function testToGenesisRoundsUpAtWeiScale() external pure {
        Float m = LibDecimalFloat.packLossless(3, 0);
        assertEq(LibMintCapUnits.toGenesis(1, m), 1, "1/3 charges 1");
        assertEq(LibMintCapUnits.toGenesis(2, m), 1, "2/3 charges 1");
        assertEq(LibMintCapUnits.toGenesis(3, m), 1, "3/3 charges 1");
        assertEq(LibMintCapUnits.toGenesis(4, m), 2, "4/3 charges 2");
    }

    /// Rounding up must not invent a charge where there is nothing to charge,
    /// or a zero-amount call would consume a unit of every bucket.
    function testZeroConvertsToZero(uint256 mUnits) external pure {
        mUnits = bound(mUnits, 1, 1e12);
        assertEq(LibMintCapUnits.toGenesis(0, multiplier(mUnits)), 0);
        assertEq(LibMintCapUnits.toCurrent(0, multiplier(mUnits)), 0);
    }

    /// The consumed direction equals a ceiling division computed in integers.
    function testToGenesisIsCeilingDivision(uint256 amount, uint256 mUnits) external pure {
        amount = bound(amount, 0, 1e24);
        mUnits = bound(mUnits, 1, 1e12);
        assertEq(
            LibMintCapUnits.toGenesis(amount, multiplier(mUnits)),
            Math.mulDiv(amount, SCALE, mUnits, Math.Rounding.Ceil)
        );
    }

    /// The headroom direction equals a floor multiplication computed in
    /// integers.
    function testToCurrentIsFloorMultiplication(uint256 amount, uint256 mUnits) external pure {
        amount = bound(amount, 0, 1e24);
        mUnits = bound(mUnits, 1, 1e12);
        assertEq(LibMintCapUnits.toCurrent(amount, multiplier(mUnits)), Math.mulDiv(amount, mUnits, SCALE));
    }

    /// The property the round-up exists to guarantee: what a bucket is charged
    /// for an amount is never worth less, back in current units, than the
    /// amount itself. A single wei of slack here is a mint that is partly
    /// free, repeatable as often as the minter cares to split its mints.
    function testChargingNeverUndercharges(uint256 amount, uint256 mUnits) external pure {
        amount = bound(amount, 0, 1e24);
        mUnits = bound(mUnits, 1, 1e12);
        Float m = multiplier(mUnits);
        assertGe(LibMintCapUnits.toCurrent(LibMintCapUnits.toGenesis(amount, m), m), amount);
    }

    /// The property the round-down exists to guarantee: the headroom a view
    /// reports is an amount that still fits the headroom it was derived from,
    /// so `mintHeadroom` never names a figure that the next `mint` refuses.
    function testReportedHeadroomStillFits(uint256 headroom, uint256 mUnits) external pure {
        headroom = bound(headroom, 0, 1e24);
        mUnits = bound(mUnits, 1, 1e12);
        Float m = multiplier(mUnits);
        assertLe(LibMintCapUnits.toGenesis(LibMintCapUnits.toCurrent(headroom, m), m), headroom);
    }

    /// An amount too wide for the `Float` coefficient is refused rather than
    /// silently truncated toward zero, which on a charged amount would be a
    /// discount applied before the round-up could correct it.
    function testTooWideAmountIsRefusedNotTruncated() external {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 tooWide = uint256(uint224(type(int224).max)) + 1;
        Float one = LibDecimalFloat.packLossless(1, 0);
        vm.expectRevert(abi.encodeWithSelector(AmountNotRepresentableAsFloat.selector, tooWide));
        harness.toGenesis(tooWide, one);
        vm.expectRevert(abi.encodeWithSelector(AmountNotRepresentableAsFloat.selector, tooWide));
        harness.toCurrent(tooWide, one);
    }

    /// A zero multiplier is unreachable from a well-formed token, and fails
    /// closed rather than dividing by zero silently.
    function testZeroMultiplierFailsClosed() external {
        Float zero = LibDecimalFloat.packLossless(0, 0);
        vm.expectRevert();
        harness.toGenesis(1e18, zero);
    }
}

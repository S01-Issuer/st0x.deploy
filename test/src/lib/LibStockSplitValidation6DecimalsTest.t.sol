// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
import {MultiplierTooSmall, MultiplierTooLarge} from "../../../src/error/ErrStockSplit.sol";
import {LibTestTofu} from "../../lib/LibTestTofu.sol";
import {StockSplitValidationHarness as ValidationHarness} from "../../concrete/StockSplitValidationHarness.sol";

/// @dev Validation tests with a 6-decimal harness (USDC-like) to verify
/// the bounds scale with the vault's decimals.
contract LibStockSplitValidation6DecimalsTest is Test {
    ValidationHarness internal v;

    function setUp() public {
        LibTestTofu.deployTofu(vm);
        v = new ValidationHarness(6);
    }

    /// Floor for 6 decimals: 1e-6 passes.
    function testFloorBoundaryPasses() external {
        Float boundary = LibDecimalFloat.packLossless(1, -6);
        v.validate(boundary);
    }

    /// Below floor for 6 decimals: 1e-7 reverts.
    function testBelowFloorReverts() external {
        Float tooSmall = LibDecimalFloat.packLossless(1, -7);
        vm.expectRevert(abi.encodeWithSelector(MultiplierTooSmall.selector, tooSmall));
        v.validate(tooSmall);
    }

    /// Ceiling for 6 decimals: 1e6 passes.
    function testCeilingBoundaryPasses() external {
        Float ceiling = LibDecimalFloat.packLossless(1, 6);
        v.validate(ceiling);
    }

    /// Above ceiling for 6 decimals: 1e7 reverts.
    function testAboveCeilingReverts() external {
        Float tooLarge = LibDecimalFloat.packLossless(1, 7);
        vm.expectRevert(abi.encodeWithSelector(MultiplierTooLarge.selector, tooLarge));
        v.validate(tooLarge);
    }

    /// A multiplier that would pass for 18-decimals (1e-18) must revert for
    /// a 6-decimal vault because it's below the per-token floor.
    function testEighteenDecimalFloorRejectedForSixDecimals() external {
        Float eighteenFloor = LibDecimalFloat.packLossless(1, -18);
        vm.expectRevert(abi.encodeWithSelector(MultiplierTooSmall.selector, eighteenFloor));
        v.validate(eighteenFloor);
    }

    /// A realistic 2x split still passes for 6-decimal tokens.
    function testRealisticSplitPasses() external {
        Float twoX = LibDecimalFloat.packLossless(2, 0);
        v.validate(twoX);
    }
}

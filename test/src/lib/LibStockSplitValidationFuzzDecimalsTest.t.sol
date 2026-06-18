// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
import {MultiplierTooSmall, MultiplierTooLarge} from "../../../src/error/ErrStockSplit.sol";
import {LibTestTofu} from "../../lib/LibTestTofu.sol";
import {StockSplitValidationHarness as ValidationHarness} from "../../concrete/StockSplitValidationHarness.sol";

/// @dev Fuzz tests that parameterize over the vault's decimals.
contract LibStockSplitValidationFuzzDecimalsTest is Test {
    function setUp() public {
        LibTestTofu.deployTofu(vm);
    }

    /// For any decimals in a realistic range, the floor boundary
    /// (10^-decimals) passes and just below it (10^-(decimals+1)) reverts.
    function testFuzzFloorBoundary(uint8 decimals) external {
        decimals = uint8(bound(decimals, 1, 36));
        ValidationHarness v = new ValidationHarness(decimals);

        // forge-lint: disable-next-line(unsafe-typecast)
        int256 decimalsSigned = int256(uint256(decimals));

        // Floor boundary passes.
        Float floor = LibDecimalFloat.packLossless(1, -decimalsSigned);
        v.validate(floor);

        // Just below floor reverts.
        Float belowFloor = LibDecimalFloat.packLossless(1, -(decimalsSigned + 1));
        vm.expectRevert(abi.encodeWithSelector(MultiplierTooSmall.selector, belowFloor));
        v.validate(belowFloor);
    }

    /// For any decimals in a realistic range, the ceiling boundary
    /// (10^decimals) passes and just above it (10^(decimals+1)) reverts.
    function testFuzzCeilingBoundary(uint8 decimals) external {
        decimals = uint8(bound(decimals, 1, 36));
        ValidationHarness v = new ValidationHarness(decimals);

        // forge-lint: disable-next-line(unsafe-typecast)
        int256 decimalsSigned = int256(uint256(decimals));

        // Ceiling boundary passes.
        Float ceiling = LibDecimalFloat.packLossless(1, decimalsSigned);
        v.validate(ceiling);

        // Just above ceiling reverts.
        Float aboveCeiling = LibDecimalFloat.packLossless(1, decimalsSigned + 1);
        vm.expectRevert(abi.encodeWithSelector(MultiplierTooLarge.selector, aboveCeiling));
        v.validate(aboveCeiling);
    }

    /// A realistic multiplier (2x) passes for any realistic decimals value.
    function testFuzzRealisticMultiplierPasses(uint8 decimals) external {
        decimals = uint8(bound(decimals, 1, 36));
        ValidationHarness v = new ValidationHarness(decimals);

        Float twoX = LibDecimalFloat.packLossless(2, 0);
        v.validate(twoX);
    }
}

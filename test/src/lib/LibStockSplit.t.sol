// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {
    LibStockSplit,
    ACTION_TYPE_STOCK_SPLIT,
    ZeroSplitComponent,
    LossySplitRatio
} from "../../../src/lib/LibStockSplit.sol";
import {LibDecimalFloat, Float} from "rain.math.float/lib/LibDecimalFloat.sol";

/// @dev Wrapper contract so that library calls are external calls and
/// vm.expectRevert works at the right depth.
contract LibStockSplitWrapper {
    function encodeSplitParameters(uint256 numerator, uint256 denominator) external pure returns (bytes memory, Float) {
        return LibStockSplit.encodeSplitParameters(numerator, denominator);
    }

    function decodeMultiplier(bytes memory parameters) external pure returns (Float) {
        return LibStockSplit.decodeMultiplier(parameters);
    }
}

contract LibStockSplitTest is Test {
    LibStockSplitWrapper wrapper;

    function setUp() external {
        wrapper = new LibStockSplitWrapper();
    }

    /// ACTION_TYPE_STOCK_SPLIT is a deterministic hash.
    function testActionTypeValue() external pure {
        assertEq(ACTION_TYPE_STOCK_SPLIT, keccak256("STOCK_SPLIT"));
    }

    /// A 2-for-1 split encodes a multiplier mathematically equal to 2.
    function testEncode2For1() external view {
        (, Float multiplier) = wrapper.encodeSplitParameters(2, 1);
        Float two = LibDecimalFloat.packLossless(2, 0);
        assertTrue(LibDecimalFloat.eq(multiplier, two));
    }

    /// A 1-for-2 reverse split encodes a multiplier equal to 0.5.
    function testEncode1For2() external view {
        (, Float multiplier) = wrapper.encodeSplitParameters(1, 2);
        Float half = LibDecimalFloat.packLossless(5, -1);
        assertTrue(LibDecimalFloat.eq(multiplier, half));
    }

    /// A 3-for-2 split encodes a multiplier equal to 1.5.
    function testEncode3For2() external view {
        (, Float multiplier) = wrapper.encodeSplitParameters(3, 2);
        Float onePointFive = LibDecimalFloat.packLossless(15, -1);
        assertTrue(LibDecimalFloat.eq(multiplier, onePointFive));
    }

    /// A 1-for-3 reverse split is REJECTED because 1/3 * 3 != 1 in float
    /// arithmetic due to precision loss. This is the correct behaviour — ratios
    /// that don't round-trip cleanly would accumulate errors.
    function testEncode1For3Reverts() external {
        vm.expectRevert(abi.encodeWithSelector(LossySplitRatio.selector, 1, 3));
        wrapper.encodeSplitParameters(1, 3);
    }

    /// A 1-for-1 split (identity) encodes a multiplier equal to 1.
    function testEncode1For1() external view {
        (, Float multiplier) = wrapper.encodeSplitParameters(1, 1);
        assertTrue(LibDecimalFloat.eq(multiplier, LibDecimalFloat.FLOAT_ONE));
    }

    /// Zero numerator reverts.
    function testZeroNumeratorReverts() external {
        vm.expectRevert(ZeroSplitComponent.selector);
        wrapper.encodeSplitParameters(0, 1);
    }

    /// Zero denominator reverts.
    function testZeroDenominatorReverts() external {
        vm.expectRevert(ZeroSplitComponent.selector);
        wrapper.encodeSplitParameters(1, 0);
    }

    /// Both zero reverts.
    function testBothZeroReverts() external {
        vm.expectRevert(ZeroSplitComponent.selector);
        wrapper.encodeSplitParameters(0, 0);
    }

    /// Decode round-trips with encode (mathematical equality).
    function testDecodeRoundTrip() external view {
        (bytes memory params, Float encoded) = wrapper.encodeSplitParameters(3, 2);
        Float decoded = wrapper.decodeMultiplier(params);
        assertTrue(LibDecimalFloat.eq(decoded, encoded));
    }

    /// Fuzz: common clean ratios that are powers of 2 and 5 encode without
    /// revert (these are exactly representable in decimal float).
    function testFuzzPowerOf2And5Ratios(uint8 rawNum, uint8 rawDen) external view {
        // Ratios of small powers of 2 and 5 are exactly representable.
        uint256[6] memory bases = [uint256(1), 2, 4, 5, 8, 10];
        uint256 numerator = bases[bound(rawNum, 0, 5)];
        uint256 denominator = bases[bound(rawDen, 0, 5)];

        (bytes memory params, Float multiplier) = wrapper.encodeSplitParameters(numerator, denominator);
        assertTrue(params.length > 0);

        // Verify decode round-trips.
        Float decoded = wrapper.decodeMultiplier(params);
        assertTrue(LibDecimalFloat.eq(decoded, multiplier));
    }

    /// Known lossy ratios should revert. 1/3, 1/7, 2/3, etc.
    function testLossyRatiosRevert() external {
        vm.expectRevert(abi.encodeWithSelector(LossySplitRatio.selector, 1, 3));
        wrapper.encodeSplitParameters(1, 3);

        vm.expectRevert(abi.encodeWithSelector(LossySplitRatio.selector, 1, 7));
        wrapper.encodeSplitParameters(1, 7);

        vm.expectRevert(abi.encodeWithSelector(LossySplitRatio.selector, 2, 3));
        wrapper.encodeSplitParameters(2, 3);
    }
}

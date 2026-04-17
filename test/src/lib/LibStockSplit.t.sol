// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
import {
    LibCorporateAction,
    ACTION_TYPE_STOCK_SPLIT,
    STOCK_SPLIT_TYPE_HASH,
    UnknownActionType
} from "src/lib/LibCorporateAction.sol";
import {CorporateActionNode, CompletionFilter, LibCorporateActionNode} from "src/lib/LibCorporateActionNode.sol";
import {LibStockSplit, InvalidSplitMultiplier, MultiplierTooSmall, MultiplierTooLarge} from "src/lib/LibStockSplit.sol";

contract StockSplitHarness {
    function resolveAndSchedule(bytes32 typeHash, uint64 effectiveTime, bytes memory parameters)
        external
        returns (uint256)
    {
        uint256 actionType = LibCorporateAction.resolveActionType(typeHash, parameters);
        return LibCorporateAction.schedule(actionType, effectiveTime, parameters);
    }

    function resolveActionType(bytes32 typeHash, bytes memory parameters) external pure returns (uint256) {
        return LibCorporateAction.resolveActionType(typeHash, parameters);
    }

    function nextOfType(uint256 cursor, uint256 mask, CompletionFilter filter) external view returns (uint256) {
        return LibCorporateActionNode.nextOfType(cursor, mask, filter);
    }

    function countCompleted() external view returns (uint256) {
        return LibCorporateAction.countCompleted();
    }

    function getNode(uint256 actionIndex) external view returns (CorporateActionNode memory) {
        return LibCorporateAction.getStorage().nodes[actionIndex];
    }
}

contract ValidationHarness {
    function validate(bytes memory parameters) external pure {
        LibStockSplit.validateParameters(parameters);
    }
}

contract LibStockSplitValidationTest is Test {
    ValidationHarness internal v;

    function setUp() public {
        v = new ValidationHarness();
    }

    /// Valid multiplier passes validation.
    function testValidMultiplier() external view {
        Float twoX = LibDecimalFloat.packLossless(2, 0);
        v.validate(abi.encode(twoX));
    }

    /// Zero multiplier reverts — covers the `coefficient == 0` branch.
    function testZeroMultiplierReverts() external {
        Float zero = LibDecimalFloat.packLossless(0, 0);
        vm.expectRevert(InvalidSplitMultiplier.selector);
        v.validate(abi.encode(zero));
    }

    /// Audit P2-1: negative coefficient reverts — covers the `coefficient < 0`
    /// branch of the `<= 0` check that `testZeroMultiplierReverts` does not hit.
    function testNegativeCoefficientMultiplierReverts() external {
        Float negative = LibDecimalFloat.packLossless(-2, 0);
        vm.expectRevert(InvalidSplitMultiplier.selector);
        v.validate(abi.encode(negative));
    }

    /// Audit P2-1: negative coefficient with non-zero exponent also reverts.
    function testNegativeCoefficientWithExponentReverts() external {
        Float negative = LibDecimalFloat.packLossless(-1, 18);
        vm.expectRevert(InvalidSplitMultiplier.selector);
        v.validate(abi.encode(negative));
    }

    /// Audit P1-1 / P2-2: near-zero multiplier (`1e-30`) must revert.
    /// Floor check: `trunc(1e18 * 1e-30) == 0` → `MultiplierTooSmall`.
    function testNearZeroMultiplierReverts() external {
        Float tooSmall = LibDecimalFloat.packLossless(1, -30);
        vm.expectRevert(abi.encodeWithSelector(MultiplierTooSmall.selector, tooSmall));
        v.validate(abi.encode(tooSmall));
    }

    /// Audit P1-1 / P2-2: the exact floor boundary, `1e-18`, must pass.
    /// `trunc(1e18 * 1e-18) == 1`.
    function testFloorBoundaryMultiplierPasses() external view {
        Float boundary = LibDecimalFloat.packLossless(1, -18);
        v.validate(abi.encode(boundary));
    }

    /// Audit P1-1 / P2-2: near-saturation multiplier (`1e30`) must revert.
    /// Ceiling check: `trunc(1e18 * 1e30) == 1e48 > 1e36` → `MultiplierTooLarge`.
    function testNearSaturationMultiplierReverts() external {
        Float tooLarge = LibDecimalFloat.packLossless(1, 30);
        vm.expectRevert(abi.encodeWithSelector(MultiplierTooLarge.selector, tooLarge));
        v.validate(abi.encode(tooLarge));
    }

    /// Audit P1-1 / P2-2: a large-but-realistic 1000x split must pass.
    function testLargeButRealisticSplitPasses() external view {
        Float thousandX = LibDecimalFloat.packLossless(1000, 0);
        v.validate(abi.encode(thousandX));
    }

    /// Fractional multiplier (1/3 reverse split) is valid.
    function testFractionalMultiplierValid() external view {
        Float oneThird = LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(3, 0));
        v.validate(abi.encode(oneThird));
    }

    /// Decode-after-abi.encode roundtrip preserves the multiplier.
    function testEncodeDecodeRoundtrip() external pure {
        Float threeX = LibDecimalFloat.packLossless(3, 0);
        bytes memory encoded = abi.encode(threeX);
        Float decoded = LibStockSplit.decodeParameters(encoded);
        assertEq(Float.unwrap(decoded), Float.unwrap(threeX));
    }

    /// Exact ceiling boundary: 1e18 multiplier gives trunc(1e18 * 1e18) = 1e36.
    function testExactCeilingBoundaryPasses() external view {
        Float ceiling = LibDecimalFloat.packLossless(1, 18);
        v.validate(abi.encode(ceiling));
    }

    /// Just above ceiling: 1e18 + epsilon must revert.
    function testAboveCeilingReverts() external {
        // 1.000001e18 → trunc(1e18 * 1.000001e18) > 1e36
        Float aboveCeiling = LibDecimalFloat.packLossless(1000001, 12);
        vm.expectRevert(abi.encodeWithSelector(MultiplierTooLarge.selector, aboveCeiling));
        v.validate(abi.encode(aboveCeiling));
    }

    /// Just below floor: 9e-19 must revert (trunc(1e18 * 9e-19) = 0).
    function testBelowFloorReverts() external {
        Float belowFloor = LibDecimalFloat.packLossless(9, -19);
        vm.expectRevert(abi.encodeWithSelector(MultiplierTooSmall.selector, belowFloor));
        v.validate(abi.encode(belowFloor));
    }

    /// Fuzz: any positive multiplier within bounds passes validation.
    function testFuzzValidMultiplier(uint64 coeff, int8 exp) external view {
        vm.assume(coeff > 0);
        exp = int8(bound(exp, -17, 17));
        // forge-lint: disable-next-line(unsafe-typecast)
        Float multiplier = LibDecimalFloat.packLossless(int256(uint256(coeff)), int256(exp));
        // Compute applied value to check bounds.
        // forge-lint: disable-next-line(unsafe-typecast)
        (uint256 applied,) = LibDecimalFloat.toFixedDecimalLossy(
            LibDecimalFloat.mul(LibDecimalFloat.packLossless(int256(1e18), 0), multiplier), 0
        );
        vm.assume(applied >= 1 && applied <= 1e36);
        v.validate(abi.encode(multiplier));
    }

    /// Constants have expected values.
    function testConstantValues() external pure {
        assertEq(ACTION_TYPE_STOCK_SPLIT, 1);
        assertEq(STOCK_SPLIT_TYPE_HASH, keccak256("st0x.corporate-actions.stock-split"));
    }

    /// ACTION_TYPE_STOCK_SPLIT has exactly one bit set.
    function testActionTypeSingleBit() external pure {
        assertEq(ACTION_TYPE_STOCK_SPLIT & (ACTION_TYPE_STOCK_SPLIT - 1), 0);
        assertTrue(ACTION_TYPE_STOCK_SPLIT != 0);
    }

    /// Fuzz: encode/decode roundtrip preserves arbitrary valid multipliers.
    function testFuzzDecodeRoundtrip(uint64 coeff, int8 exp) external pure {
        vm.assume(coeff > 0);
        exp = int8(bound(exp, -17, 17));
        // forge-lint: disable-next-line(unsafe-typecast)
        Float multiplier = LibDecimalFloat.packLossless(int256(uint256(coeff)), int256(exp));
        bytes memory encoded = abi.encode(multiplier);
        Float decoded = LibStockSplit.decodeParameters(encoded);
        assertEq(Float.unwrap(decoded), Float.unwrap(multiplier));
    }

    /// Fuzz: multipliers below floor always revert.
    function testFuzzBelowFloorReverts(uint8 coeff, int16 exp) external {
        vm.assume(coeff > 0);
        // Bound exponent low enough that even coeff=255 produces below-floor.
        // 255e-21 * 1e18 = 255e-3 = 0.255 → trunc = 0.
        exp = int16(bound(exp, -100, -21));
        // forge-lint: disable-next-line(unsafe-typecast)
        Float multiplier = LibDecimalFloat.packLossless(int256(uint256(coeff)), int256(exp));
        vm.expectRevert();
        v.validate(abi.encode(multiplier));
    }
}

contract LibStockSplitResolveTest is Test {
    StockSplitHarness internal h;

    function setUp() public {
        h = new StockSplitHarness();
    }

    /// STOCK_SPLIT_TYPE_HASH resolves to ACTION_TYPE_STOCK_SPLIT.
    function testResolveStockSplit() external view {
        Float twoX = LibDecimalFloat.packLossless(2, 0);
        uint256 bitmap = h.resolveActionType(STOCK_SPLIT_TYPE_HASH, abi.encode(twoX));
        assertEq(bitmap, ACTION_TYPE_STOCK_SPLIT);
    }

    /// Resolve with invalid parameters reverts during validation.
    function testResolveStockSplitZeroMultiplierReverts() external {
        Float zero = LibDecimalFloat.packLossless(0, 0);
        vm.expectRevert(InvalidSplitMultiplier.selector);
        h.resolveActionType(STOCK_SPLIT_TYPE_HASH, abi.encode(zero));
    }

    /// Unknown type hash reverts.
    function testResolveUnknownTypeReverts() external {
        bytes32 unknown = keccak256("Dividend");
        vm.expectRevert(abi.encodeWithSelector(UnknownActionType.selector, unknown));
        h.resolveActionType(unknown, "");
    }
}

contract LibStockSplitLifecycleTest is Test {
    StockSplitHarness internal h;

    function setUp() public {
        h = new StockSplitHarness();
        vm.warp(1000);
    }

    /// Stock split full lifecycle: resolve, schedule, complete, walk, read multiplier.
    function testStockSplitLifecycle() external {
        Float threeX = LibDecimalFloat.packLossless(3, 0);
        uint256 id = h.resolveAndSchedule(STOCK_SPLIT_TYPE_HASH, 1500, abi.encode(threeX));
        assertEq(id, 1);
        assertEq(h.countCompleted(), 0);

        vm.warp(2000);
        assertEq(h.countCompleted(), 1);

        uint256 completed = h.nextOfType(0, ACTION_TYPE_STOCK_SPLIT, CompletionFilter.COMPLETED);
        assertEq(completed, 1);

        CorporateActionNode memory node = h.getNode(1);
        Float stored = LibStockSplit.decodeParameters(node.parameters);
        assertEq(Float.unwrap(stored), Float.unwrap(threeX));
    }

    /// Multiple stock splits: schedule 3, complete 2, verify filtering.
    function testMultipleStockSplitsFiltered() external {
        Float twoX = LibDecimalFloat.packLossless(2, 0);
        Float threeX = LibDecimalFloat.packLossless(3, 0);
        Float halfX = LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(2, 0));

        uint256 id1 = h.resolveAndSchedule(STOCK_SPLIT_TYPE_HASH, 1500, abi.encode(twoX));
        uint256 id2 = h.resolveAndSchedule(STOCK_SPLIT_TYPE_HASH, 2000, abi.encode(threeX));
        uint256 id3 = h.resolveAndSchedule(STOCK_SPLIT_TYPE_HASH, 3000, abi.encode(halfX));

        // Complete first two.
        vm.warp(2500);

        // COMPLETED filter returns id1 then id2.
        uint256 c1 = h.nextOfType(0, ACTION_TYPE_STOCK_SPLIT, CompletionFilter.COMPLETED);
        assertEq(c1, id1);
        uint256 c2 = h.nextOfType(c1, ACTION_TYPE_STOCK_SPLIT, CompletionFilter.COMPLETED);
        assertEq(c2, id2);
        assertEq(h.nextOfType(c2, ACTION_TYPE_STOCK_SPLIT, CompletionFilter.COMPLETED), 0);

        // PENDING filter returns only id3.
        uint256 p1 = h.nextOfType(0, ACTION_TYPE_STOCK_SPLIT, CompletionFilter.PENDING);
        assertEq(p1, id3);
        assertEq(h.nextOfType(p1, ACTION_TYPE_STOCK_SPLIT, CompletionFilter.PENDING), 0);

        // ALL returns all three.
        assertEq(h.countCompleted(), 2);
    }

    /// Stored node has correct actionType bitmap and decodable parameters
    /// after scheduling through resolveAndSchedule.
    function testStoredNodeDataAfterSchedule() external {
        Float fiveX = LibDecimalFloat.packLossless(5, 0);
        uint256 id = h.resolveAndSchedule(STOCK_SPLIT_TYPE_HASH, 1500, abi.encode(fiveX));

        CorporateActionNode memory node = h.getNode(id);
        assertEq(node.actionType, ACTION_TYPE_STOCK_SPLIT, "bitmap is stock split");
        assertEq(node.effectiveTime, 1500, "effectiveTime stored");

        Float stored = LibStockSplit.decodeParameters(node.parameters);
        assertEq(Float.unwrap(stored), Float.unwrap(fiveX), "multiplier round-trips");
    }

    /// Two stock splits with different multipliers store independently.
    function testTwoSplitsDifferentMultipliersStoreIndependently() external {
        Float twoX = LibDecimalFloat.packLossless(2, 0);
        Float oneThird = LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(3, 0));

        uint256 id1 = h.resolveAndSchedule(STOCK_SPLIT_TYPE_HASH, 1500, abi.encode(twoX));
        uint256 id2 = h.resolveAndSchedule(STOCK_SPLIT_TYPE_HASH, 2000, abi.encode(oneThird));

        Float stored1 = LibStockSplit.decodeParameters(h.getNode(id1).parameters);
        Float stored2 = LibStockSplit.decodeParameters(h.getNode(id2).parameters);

        assertEq(Float.unwrap(stored1), Float.unwrap(twoX));
        assertEq(Float.unwrap(stored2), Float.unwrap(oneThird));
        assertTrue(Float.unwrap(stored1) != Float.unwrap(stored2), "different multipliers stored");
    }
}

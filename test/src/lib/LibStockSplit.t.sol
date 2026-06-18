// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
import {STOCK_SPLIT_V1_TYPE_HASH} from "../../../src/lib/LibCorporateAction.sol";
import {
    ACTION_TYPE_INIT_V1,
    ACTION_TYPE_STOCK_SPLIT_V1,
    ACTION_TYPE_STABLES_DIVIDEND_V1,
    VALID_ACTION_TYPES_MASK
} from "../../../src/interface/ICorporateActionsV1.sol";
import {LibStockSplit} from "../../../src/lib/LibStockSplit.sol";
import {InvalidSplitMultiplier, MultiplierTooSmall, MultiplierTooLarge} from "../../../src/error/ErrStockSplit.sol";
import {LibTestTofu} from "../../lib/LibTestTofu.sol";
import {StockSplitValidationHarness as ValidationHarness} from "../../concrete/StockSplitValidationHarness.sol";

contract LibStockSplitValidationTest is Test {
    ValidationHarness internal v;

    function setUp() public {
        LibTestTofu.deployTofu(vm);
        v = new ValidationHarness(18);
    }

    /// Valid multiplier passes validation.
    function testValidMultiplier() external {
        Float twoX = LibDecimalFloat.packLossless(2, 0);
        v.validate(twoX);
    }

    /// Zero multiplier reverts — covers the `coefficient == 0` branch.
    function testZeroMultiplierReverts() external {
        Float zero = LibDecimalFloat.packLossless(0, 0);
        vm.expectRevert(InvalidSplitMultiplier.selector);
        v.validate(zero);
    }

    /// Audit P2-1: negative coefficient reverts — covers the `coefficient < 0`
    /// branch of the `<= 0` check that `testZeroMultiplierReverts` does not hit.
    function testNegativeCoefficientMultiplierReverts() external {
        Float negative = LibDecimalFloat.packLossless(-2, 0);
        vm.expectRevert(InvalidSplitMultiplier.selector);
        v.validate(negative);
    }

    /// Audit P2-1: negative coefficient with non-zero exponent also reverts.
    function testNegativeCoefficientWithExponentReverts() external {
        Float negative = LibDecimalFloat.packLossless(-1, 18);
        vm.expectRevert(InvalidSplitMultiplier.selector);
        v.validate(negative);
    }

    /// Audit P1-1 / P2-2: near-zero multiplier (`1e-30`) must revert.
    /// Floor check: `trunc(1e18 * 1e-30) == 0` → `MultiplierTooSmall`.
    function testNearZeroMultiplierReverts() external {
        Float tooSmall = LibDecimalFloat.packLossless(1, -30);
        vm.expectRevert(abi.encodeWithSelector(MultiplierTooSmall.selector, tooSmall));
        v.validate(tooSmall);
    }

    /// Audit P1-1 / P2-2: the exact floor boundary, `1e-18`, must pass.
    /// `trunc(1e18 * 1e-18) == 1`.
    function testFloorBoundaryMultiplierPasses() external {
        Float boundary = LibDecimalFloat.packLossless(1, -18);
        v.validate(boundary);
    }

    /// Audit P1-1 / P2-2: near-saturation multiplier (`1e30`) must revert.
    /// Ceiling check: `trunc(1e18 * 1e30) == 1e48 > 1e36` → `MultiplierTooLarge`.
    function testNearSaturationMultiplierReverts() external {
        Float tooLarge = LibDecimalFloat.packLossless(1, 30);
        vm.expectRevert(abi.encodeWithSelector(MultiplierTooLarge.selector, tooLarge));
        v.validate(tooLarge);
    }

    /// Audit P1-1 / P2-2: a large-but-realistic 1000x split must pass.
    function testLargeButRealisticSplitPasses() external {
        Float thousandX = LibDecimalFloat.packLossless(1000, 0);
        v.validate(thousandX);
    }

    /// Fractional multiplier (1/3 reverse split) is valid.
    function testFractionalMultiplierValid() external {
        Float oneThird = LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(3, 0));
        v.validate(oneThird);
    }

    /// `encodeParametersV1` + `decodeParametersV1` roundtrip preserves the
    /// multiplier. Exercises the canonical V1 codec rather than raw
    /// `abi.encode`/`abi.decode` so callers downstream of these helpers
    /// (schedulers building payloads, readers decoding them) are covered
    /// by this test.
    function testEncodeDecodeRoundtrip() external pure {
        Float threeX = LibDecimalFloat.packLossless(3, 0);
        bytes memory encoded = LibStockSplit.encodeParametersV1(threeX);
        Float decoded = LibStockSplit.decodeParametersV1(encoded);
        assertEq(Float.unwrap(decoded), Float.unwrap(threeX));
    }

    /// Wire-format pin: the V1 codec is currently equivalent to raw
    /// `abi.encode(Float)` / `abi.decode(bytes, (Float))`. Off-chain schedulers
    /// that predate this helper hand-encode their payloads this way, and
    /// on-chain `decodeParametersV1` must accept those payloads unchanged. If
    /// the V1 schema ever grows additional fields, this test has to be
    /// updated together with the codec — the test failing is the signal that
    /// every off-chain scheduler needs to migrate before deployment.
    function testFuzzEncodeParametersV1MatchesRawAbiEncode(uint64 coeff, int8 exp) external pure {
        vm.assume(coeff > 0);
        exp = int8(bound(exp, -17, 17));
        // forge-lint: disable-next-line(unsafe-typecast)
        Float multiplier = LibDecimalFloat.packLossless(int256(uint256(coeff)), int256(exp));
        bytes memory libEncoded = LibStockSplit.encodeParametersV1(multiplier);
        bytes memory rawEncoded = abi.encode(multiplier);
        assertEq(libEncoded, rawEncoded, "encodeParametersV1 must match raw abi.encode for V1 schema");
    }

    /// Symmetric wire-format pin for the decode side: a payload produced by
    /// raw `abi.encode(Float)` must decode through `decodeParametersV1` to the
    /// original multiplier. Ensures off-chain-produced bytes round-trip
    /// through the on-chain reader.
    function testFuzzDecodeParametersV1AcceptsRawAbiEncode(uint64 coeff, int8 exp) external pure {
        vm.assume(coeff > 0);
        exp = int8(bound(exp, -17, 17));
        // forge-lint: disable-next-line(unsafe-typecast)
        Float multiplier = LibDecimalFloat.packLossless(int256(uint256(coeff)), int256(exp));
        bytes memory rawEncoded = abi.encode(multiplier);
        Float decoded = LibStockSplit.decodeParametersV1(rawEncoded);
        assertEq(Float.unwrap(decoded), Float.unwrap(multiplier));
    }

    /// Exact ceiling boundary: 1e18 multiplier gives trunc(1e18 * 1e18) = 1e36.
    function testExactCeilingBoundaryPasses() external {
        Float ceiling = LibDecimalFloat.packLossless(1, 18);
        v.validate(ceiling);
    }

    /// Just above ceiling: 1e18 + epsilon must revert.
    function testAboveCeilingReverts() external {
        // 1.000001e18 → trunc(1e18 * 1.000001e18) > 1e36
        Float aboveCeiling = LibDecimalFloat.packLossless(1000001, 12);
        vm.expectRevert(abi.encodeWithSelector(MultiplierTooLarge.selector, aboveCeiling));
        v.validate(aboveCeiling);
    }

    /// Just below floor: 9e-19 must revert (trunc(1e18 * 9e-19) = 0).
    function testBelowFloorReverts() external {
        Float belowFloor = LibDecimalFloat.packLossless(9, -19);
        vm.expectRevert(abi.encodeWithSelector(MultiplierTooSmall.selector, belowFloor));
        v.validate(belowFloor);
    }

    /// Fuzz: any positive multiplier within bounds passes validation.
    function testFuzzValidMultiplier(uint64 coeff, int8 exp) external {
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
        v.validate(multiplier);
    }

    /// Constants have expected values.
    function testConstantValues() external pure {
        assertEq(ACTION_TYPE_STOCK_SPLIT_V1, 1 << 1);
        assertEq(ACTION_TYPE_STABLES_DIVIDEND_V1, 1 << 2);
        assertEq(STOCK_SPLIT_V1_TYPE_HASH, keccak256("st0x.corporate-actions.stock-split.1"));
    }

    /// Each action type constant has exactly one bit set.
    function testActionTypeSingleBit() external pure {
        assertEq(ACTION_TYPE_STOCK_SPLIT_V1 & (ACTION_TYPE_STOCK_SPLIT_V1 - 1), 0);
        assertTrue(ACTION_TYPE_STOCK_SPLIT_V1 != 0);

        assertEq(ACTION_TYPE_STABLES_DIVIDEND_V1 & (ACTION_TYPE_STABLES_DIVIDEND_V1 - 1), 0);
        assertTrue(ACTION_TYPE_STABLES_DIVIDEND_V1 != 0);
    }

    /// Action type bitmap constants are pairwise disjoint. If any two types
    /// share a bit, mask filters cannot distinguish them and `actionType` on
    /// a node becomes ambiguous.
    function testActionTypesDisjoint() external pure {
        assertEq(
            ACTION_TYPE_STOCK_SPLIT_V1 & ACTION_TYPE_STABLES_DIVIDEND_V1,
            0,
            "stock split and dividend must not share any bit"
        );
    }

    /// `VALID_ACTION_TYPES_MASK` is exactly the bitwise union of every
    /// defined type constant. If a future type is added without updating
    /// this mask, traversal getters will reject queries for it as
    /// `InvalidMask`. Pins the expected union so the additions stay
    /// in-sync.
    function testValidActionTypesMaskMatchesUnion() external pure {
        assertEq(
            VALID_ACTION_TYPES_MASK,
            ACTION_TYPE_INIT_V1 | ACTION_TYPE_STOCK_SPLIT_V1 | ACTION_TYPE_STABLES_DIVIDEND_V1,
            "VALID_ACTION_TYPES_MASK must be union of all defined types"
        );
    }

    /// Fuzz: `encodeParametersV1` + `decodeParametersV1` roundtrip preserves
    /// arbitrary valid multipliers.
    function testFuzzDecodeRoundtrip(uint64 coeff, int8 exp) external pure {
        vm.assume(coeff > 0);
        exp = int8(bound(exp, -17, 17));
        // forge-lint: disable-next-line(unsafe-typecast)
        Float multiplier = LibDecimalFloat.packLossless(int256(uint256(coeff)), int256(exp));
        bytes memory encoded = LibStockSplit.encodeParametersV1(multiplier);
        Float decoded = LibStockSplit.decodeParametersV1(encoded);
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
        vm.expectRevert(abi.encodeWithSelector(MultiplierTooSmall.selector, multiplier));
        v.validate(multiplier);
    }
}

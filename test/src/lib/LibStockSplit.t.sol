// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
import {
    LibCorporateAction,
    CorporateActionNode,
    ACTION_TYPE_STOCK_SPLIT,
    STOCK_SPLIT_TYPE_HASH,
    UnknownActionType
} from "src/lib/LibCorporateAction.sol";
import {LibStockSplit, InvalidSplitMultiplier} from "src/lib/LibStockSplit.sol";

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

    function firstCompletedOfType(uint256 mask) external view returns (uint256) {
        return LibCorporateAction.firstCompletedOfType(mask).index;
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

    /// Zero multiplier reverts.
    function testZeroMultiplierReverts() external {
        Float zero = LibDecimalFloat.packLossless(0, 0);
        vm.expectRevert(InvalidSplitMultiplier.selector);
        v.validate(abi.encode(zero));
    }

    /// Fractional multiplier (1/3 reverse split) is valid.
    function testFractionalMultiplierValid() external view {
        Float oneThird = LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(3, 0));
        v.validate(abi.encode(oneThird));
    }

    /// Encode/decode roundtrip preserves the multiplier.
    function testEncodeDecodeRoundtrip() external pure {
        Float threeX = LibDecimalFloat.packLossless(3, 0);
        bytes memory encoded = LibStockSplit.encodeParameters(threeX);
        Float decoded = LibStockSplit.decodeParameters(encoded);
        assertEq(Float.unwrap(decoded), Float.unwrap(threeX));
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

        uint256 completed = h.firstCompletedOfType(ACTION_TYPE_STOCK_SPLIT);
        assertEq(completed, 1);

        CorporateActionNode memory node = h.getNode(1);
        Float stored = LibStockSplit.decodeParameters(node.parameters);
        assertEq(Float.unwrap(stored), Float.unwrap(threeX));
    }
}

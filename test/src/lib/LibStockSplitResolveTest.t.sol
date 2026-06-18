// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
import {STOCK_SPLIT_V1_TYPE_HASH} from "../../../src/lib/LibCorporateAction.sol";
import {ACTION_TYPE_STOCK_SPLIT_V1} from "../../../src/interface/ICorporateActionsV1.sol";
import {UnknownActionType} from "../../../src/error/ErrCorporateAction.sol";
import {LibStockSplit} from "../../../src/lib/LibStockSplit.sol";
import {InvalidSplitMultiplier} from "../../../src/error/ErrStockSplit.sol";
import {LibTestTofu} from "../../lib/LibTestTofu.sol";
import {StockSplitHarness} from "../../concrete/StockSplitHarness.sol";

contract LibStockSplitResolveTest is Test {
    StockSplitHarness internal h;

    function setUp() public {
        LibTestTofu.deployTofu(vm);
        h = new StockSplitHarness(18);
    }

    /// STOCK_SPLIT_V1_TYPE_HASH resolves to ACTION_TYPE_STOCK_SPLIT_V1.
    function testResolveStockSplit() external {
        Float twoX = LibDecimalFloat.packLossless(2, 0);
        uint256 bitmap = h.resolveActionType(STOCK_SPLIT_V1_TYPE_HASH, LibStockSplit.encodeParametersV1(twoX));
        assertEq(bitmap, ACTION_TYPE_STOCK_SPLIT_V1);
    }

    /// Resolve with invalid parameters reverts during validation.
    function testResolveStockSplitZeroMultiplierReverts() external {
        Float zero = LibDecimalFloat.packLossless(0, 0);
        vm.expectRevert(InvalidSplitMultiplier.selector);
        h.resolveActionType(STOCK_SPLIT_V1_TYPE_HASH, LibStockSplit.encodeParametersV1(zero));
    }

    /// Unknown type hash reverts.
    function testResolveUnknownTypeReverts() external {
        bytes32 unknown = keccak256("Dividend");
        vm.expectRevert(abi.encodeWithSelector(UnknownActionType.selector, unknown));
        h.resolveActionType(unknown, "");
    }
}

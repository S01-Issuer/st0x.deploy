// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
import {STOCK_SPLIT_V1_TYPE_HASH} from "../../../src/lib/LibCorporateAction.sol";
import {ACTION_TYPE_STOCK_SPLIT_V1} from "../../../src/interface/ICorporateActionsV1.sol";
import {CorporateActionNode, CompletionFilter, NODE_NONE} from "../../../src/lib/LibCorporateActionNode.sol";
import {LibStockSplit} from "../../../src/lib/LibStockSplit.sol";
import {LibTestTofu} from "../../lib/LibTestTofu.sol";
import {StockSplitHarness} from "../../concrete/StockSplitHarness.sol";

contract LibStockSplitLifecycleTest is Test {
    StockSplitHarness internal h;

    function setUp() public {
        LibTestTofu.deployTofu(vm);
        h = new StockSplitHarness(18);
        vm.warp(1000);
    }

    /// Stock split full lifecycle: resolve, schedule, complete, walk, read multiplier.
    function testStockSplitLifecycle() external {
        Float threeX = LibDecimalFloat.packLossless(3, 0);
        // Bootstrap takes idx 0 on first schedule, so the user split lands
        // at idx 1.
        uint256 id = h.resolveAndSchedule(STOCK_SPLIT_V1_TYPE_HASH, 1500, LibStockSplit.encodeParametersV1(threeX));
        assertEq(id, 1);
        assertEq(h.countCompleted(), 0);

        vm.warp(2000);
        assertEq(h.countCompleted(), 1);

        uint256 completed = h.nextOfType(NODE_NONE, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
        assertEq(completed, id);

        CorporateActionNode memory node = h.getNode(id);
        Float stored = abi.decode(node.parameters, (Float));
        assertEq(Float.unwrap(stored), Float.unwrap(threeX));
    }

    /// Multiple stock splits: schedule 3, complete 2, verify filtering.
    function testMultipleStockSplitsFiltered() external {
        Float twoX = LibDecimalFloat.packLossless(2, 0);
        Float threeX = LibDecimalFloat.packLossless(3, 0);
        Float halfX = LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(2, 0));

        uint256 id1 = h.resolveAndSchedule(STOCK_SPLIT_V1_TYPE_HASH, 1500, LibStockSplit.encodeParametersV1(twoX));
        uint256 id2 = h.resolveAndSchedule(STOCK_SPLIT_V1_TYPE_HASH, 2000, LibStockSplit.encodeParametersV1(threeX));
        uint256 id3 = h.resolveAndSchedule(STOCK_SPLIT_V1_TYPE_HASH, 3000, LibStockSplit.encodeParametersV1(halfX));

        // Complete first two.
        vm.warp(2500);

        // COMPLETED filter returns id1 then id2.
        uint256 c1 = h.nextOfType(NODE_NONE, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
        assertEq(c1, id1);
        uint256 c2 = h.nextOfType(c1, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
        assertEq(c2, id2);
        assertEq(h.nextOfType(c2, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED), NODE_NONE);

        // PENDING filter returns only id3.
        uint256 p1 = h.nextOfType(NODE_NONE, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(p1, id3);
        assertEq(h.nextOfType(p1, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING), NODE_NONE);

        // ALL walks all three in time order.
        uint256 a1 = h.nextOfType(NODE_NONE, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL);
        assertEq(a1, id1);
        uint256 a2 = h.nextOfType(a1, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL);
        assertEq(a2, id2);
        uint256 a3 = h.nextOfType(a2, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL);
        assertEq(a3, id3);
        assertEq(h.nextOfType(a3, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL), NODE_NONE);

        assertEq(h.countCompleted(), 2);
    }

    /// Stored node has correct actionType bitmap and decodable parameters
    /// after scheduling through resolveAndSchedule.
    function testStoredNodeDataAfterSchedule() external {
        Float fiveX = LibDecimalFloat.packLossless(5, 0);
        uint256 id = h.resolveAndSchedule(STOCK_SPLIT_V1_TYPE_HASH, 1500, abi.encode(fiveX));

        CorporateActionNode memory node = h.getNode(id);
        assertEq(node.actionType, ACTION_TYPE_STOCK_SPLIT_V1, "bitmap is stock split");
        assertEq(node.effectiveTime, 1500, "effectiveTime stored");

        Float stored = abi.decode(node.parameters, (Float));
        assertEq(Float.unwrap(stored), Float.unwrap(fiveX), "multiplier round-trips");
    }

    /// Two stock splits with different multipliers store independently.
    function testTwoSplitsDifferentMultipliersStoreIndependently() external {
        Float twoX = LibDecimalFloat.packLossless(2, 0);
        Float oneThird = LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(3, 0));

        uint256 id1 = h.resolveAndSchedule(STOCK_SPLIT_V1_TYPE_HASH, 1500, LibStockSplit.encodeParametersV1(twoX));
        uint256 id2 = h.resolveAndSchedule(STOCK_SPLIT_V1_TYPE_HASH, 2000, abi.encode(oneThird));

        Float stored1 = abi.decode(h.getNode(id1).parameters, (Float));
        Float stored2 = abi.decode(h.getNode(id2).parameters, (Float));

        assertEq(Float.unwrap(stored1), Float.unwrap(twoX));
        assertEq(Float.unwrap(stored2), Float.unwrap(oneThird));
        assertTrue(Float.unwrap(stored1) != Float.unwrap(stored2), "different multipliers stored");
    }
}

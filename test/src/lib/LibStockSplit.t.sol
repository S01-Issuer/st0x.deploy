// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {ACTION_TYPE_STOCK_SPLIT} from "../../../src/lib/LibStockSplit.sol";

contract LibStockSplitTest is Test {
    /// ACTION_TYPE_STOCK_SPLIT is a deterministic hash.
    function testActionTypeValue() external pure {
        assertEq(ACTION_TYPE_STOCK_SPLIT, keccak256("STOCK_SPLIT"));
    }
}

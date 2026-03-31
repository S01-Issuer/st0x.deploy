// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {
    StoxCorporateActionsFacet,
    CORPORATE_ACTION_SCHEDULE,
    CORPORATE_ACTION_EXECUTE,
    UnknownActionType
} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {ACTION_TYPE_STOCK_SPLIT} from "../../../src/lib/LibStockSplit.sol";
import {STATUS_COMPLETE} from "../../../src/lib/LibCorporateAction.sol";
import {LibDecimalFloat, Float} from "rain.math.float/lib/LibDecimalFloat.sol";

contract StoxCorporateActionsFacetTest is Test {
    /// The facet MUST be deployable.
    function testFacetDeploys() external {
        StoxCorporateActionsFacet f = new StoxCorporateActionsFacet();
        assertTrue(address(f) != address(0));
    }

    /// Global CAID starts at 0.
    function testGlobalCAIDStartsAtZero() external {
        StoxCorporateActionsFacet f = new StoxCorporateActionsFacet();
        assertEq(f.globalCAID(), 0);
    }

    /// Action count starts at 0.
    function testActionCountStartsAtZero() external {
        StoxCorporateActionsFacet f = new StoxCorporateActionsFacet();
        assertEq(f.corporateActionCount(), 0);
    }

    /// The scheduling and execution permissions MUST be distinct.
    function testScheduleAndExecutePermissionsAreDistinct() external pure {
        assertTrue(CORPORATE_ACTION_SCHEDULE != CORPORATE_ACTION_EXECUTE);
    }

    /// Permissions MUST be nonzero.
    function testPermissionsAreNonzero() external pure {
        assertTrue(CORPORATE_ACTION_SCHEDULE != bytes32(0));
        assertTrue(CORPORATE_ACTION_EXECUTE != bytes32(0));
    }

    /// Permissions MUST be deterministic keccak256 hashes of their names.
    function testPermissionValues() external pure {
        assertEq(CORPORATE_ACTION_SCHEDULE, keccak256("CORPORATE_ACTION_SCHEDULE"));
        assertEq(CORPORATE_ACTION_EXECUTE, keccak256("CORPORATE_ACTION_EXECUTE"));
    }
}

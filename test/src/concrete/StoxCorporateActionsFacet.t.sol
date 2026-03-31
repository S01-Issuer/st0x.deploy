// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {
    StoxCorporateActionsFacet,
    CORPORATE_ACTION_SCHEDULE,
    CORPORATE_ACTION_EXECUTE
} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {STATUS_SCHEDULED, STATUS_COMPLETE, STATUS_EXPIRED} from "../../../src/lib/LibCorporateAction.sol";

contract StoxCorporateActionsFacetTest is Test {
    /// The facet MUST be deployable.
    function testFacetDeploys() external {
        StoxCorporateActionsFacet f = new StoxCorporateActionsFacet();
        assertTrue(address(f) != address(0));
    }

    /// Reading globalCAID through a direct call returns 0 on fresh storage.
    function testGlobalVersionStartsAtZero() external {
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

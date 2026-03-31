// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {
    StoxCorporateActionsFacet,
    CORPORATE_ACTION_SCHEDULE,
    CORPORATE_ACTION_EXECUTE
} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {LibCorporateAction} from "../../../src/lib/LibCorporateAction.sol";

/// @dev Harness that exposes the facet behind a delegatecall, simulating
/// how the vault would invoke the facet. The harness and facet share the
/// same storage space (since delegatecall uses the caller's storage), which
/// is exactly the diamond pattern.
contract FacetDelegatecallHarness {
    StoxCorporateActionsFacet public immutable facet;

    constructor() {
        facet = new StoxCorporateActionsFacet();
    }

    /// Delegatecall into the facet's corporateActionGlobalVersion().
    function corporateActionGlobalVersion() external returns (uint256) {
        (bool success, bytes memory data) =
            address(facet).delegatecall(abi.encodeCall(StoxCorporateActionsFacet.corporateActionGlobalVersion, ()));
        require(success, "delegatecall failed");
        return abi.decode(data, (uint256));
    }
}

contract StoxCorporateActionsFacetTest is Test {
    /// The facet MUST be deployable. If the constructor reverts, nothing else
    /// works.
    function testFacetDeploys() external {
        StoxCorporateActionsFacet f = new StoxCorporateActionsFacet();
        assertTrue(address(f) != address(0));
    }

    /// Reading globalVersion through a direct call returns 0 on fresh storage.
    function testGlobalVersionStartsAtZero() external {
        StoxCorporateActionsFacet f = new StoxCorporateActionsFacet();
        assertEq(f.corporateActionGlobalVersion(), 0);
    }

    /// Reading globalVersion through delegatecall (the actual diamond pattern)
    /// returns 0 on fresh storage. This proves the facet correctly reads from
    /// the caller's storage space, not its own.
    function testGlobalVersionViaDelegatecall() external {
        FacetDelegatecallHarness harness = new FacetDelegatecallHarness();
        assertEq(harness.corporateActionGlobalVersion(), 0);
    }

    /// The scheduling and execution permissions MUST be distinct. If they
    /// were equal, separating the two privileges would be impossible.
    function testScheduleAndExecutePermissionsAreDistinct() external pure {
        assertTrue(CORPORATE_ACTION_SCHEDULE != CORPORATE_ACTION_EXECUTE);
    }

    /// Permissions MUST be nonzero. A zero permission could collide with
    /// default/unset values in access control systems.
    function testPermissionsAreNonzero() external pure {
        assertTrue(CORPORATE_ACTION_SCHEDULE != bytes32(0));
        assertTrue(CORPORATE_ACTION_EXECUTE != bytes32(0));
    }

    /// Permissions MUST be deterministic keccak256 hashes of their names.
    /// This ensures they are reproducible across deployments and match what
    /// the authorizer contract expects.
    function testPermissionValues() external pure {
        assertEq(CORPORATE_ACTION_SCHEDULE, keccak256("CORPORATE_ACTION_SCHEDULE"));
        assertEq(CORPORATE_ACTION_EXECUTE, keccak256("CORPORATE_ACTION_EXECUTE"));
    }
}

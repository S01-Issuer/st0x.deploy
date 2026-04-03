// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {
    LibCorporateAction,
    CORPORATE_ACTION_STORAGE_LOCATION,
    SCHEDULE_CORPORATE_ACTION,
    CANCEL_CORPORATE_ACTION
} from "../../../src/lib/LibCorporateAction.sol";

/// @dev Minimal harness that delegates calls to a facet, simulating how the
/// vault would route unknown selectors via its fallback.
contract DelegatecallHarness {
    address public immutable facet;

    constructor(address facet_) {
        facet = facet_;
    }

    fallback() external payable {
        address target = facet;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), target, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch success
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}

contract StoxCorporateActionsFacetTest is Test {
    StoxCorporateActionsFacet internal facetImpl;
    DelegatecallHarness internal harness;
    StoxCorporateActionsFacet internal facetViaHarness;

    function setUp() public {
        facetImpl = new StoxCorporateActionsFacet();
        harness = new DelegatecallHarness(address(facetImpl));
        facetViaHarness = StoxCorporateActionsFacet(address(harness));
    }

    /// nextNodeId() returns 0 on a fresh deployment (no nodes created).
    function testNextNodeIdInitiallyZero() external view {
        assertEq(facetViaHarness.nextNodeId(), 0);
    }

    /// Facet routing: calling nextNodeId() via delegatecall harness works.
    function testFacetRoutingViaDelegatecall() external view {
        uint256 id = facetViaHarness.nextNodeId();
        assertEq(id, 0);
    }

    /// Storage isolation: two harnesses sharing the same facet impl have
    /// independent storage because delegatecall uses the caller's storage.
    function testStorageIsolationBetweenHarnesses() external {
        DelegatecallHarness harness2 = new DelegatecallHarness(address(facetImpl));
        StoxCorporateActionsFacet facet2 = StoxCorporateActionsFacet(address(harness2));

        assertEq(facetViaHarness.nextNodeId(), 0);
        assertEq(facet2.nextNodeId(), 0);

        // Write directly to harness1's storage at the nextNodeId slot
        // (first field in the struct at the ERC-7201 location).
        vm.store(address(harness), CORPORATE_ACTION_STORAGE_LOCATION, bytes32(uint256(42)));

        // harness1 reflects the write, harness2 is unaffected.
        assertEq(facetViaHarness.nextNodeId(), 42);
        assertEq(facet2.nextNodeId(), 0);
    }

    /// ERC-7201 storage slot matches the documented formula.
    function testStorageSlotCalculation() external pure {
        bytes32 expected =
            keccak256(abi.encode(uint256(keccak256("rain.storage.corporate-action.1")) - 1)) & ~bytes32(uint256(0xff));
        assertEq(CORPORATE_ACTION_STORAGE_LOCATION, expected);
    }

    /// Auth permission constants are correct keccak256 hashes.
    function testAuthPermissionConstants() external pure {
        assertEq(SCHEDULE_CORPORATE_ACTION, keccak256("SCHEDULE_CORPORATE_ACTION"));
        assertEq(CANCEL_CORPORATE_ACTION, keccak256("CANCEL_CORPORATE_ACTION"));
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {ICorporateActionsV1} from "../../../src/interface/ICorporateActionsV1.sol";
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
    ICorporateActionsV1 internal facetViaHarness;

    function setUp() public {
        facetImpl = new StoxCorporateActionsFacet();
        harness = new DelegatecallHarness(address(facetImpl));
        facetViaHarness = ICorporateActionsV1(address(harness));
    }

    /// globalCAID() returns 0 on a fresh deployment.
    function testGlobalCAIDInitiallyZero() external view {
        assertEq(facetViaHarness.globalCAID(), 0);
    }

    /// Facet routing: calling globalCAID() via delegatecall harness works.
    function testFacetRoutingViaDelegatecall() external view {
        uint256 caid = facetViaHarness.globalCAID();
        assertEq(caid, 0);
    }

    /// Storage isolation: the harness and a second harness sharing the same
    /// facet impl have independent storage because they are different contracts.
    function testStorageIsolationBetweenHarnesses() external {
        DelegatecallHarness harness2 = new DelegatecallHarness(address(facetImpl));
        ICorporateActionsV1 facet2 = ICorporateActionsV1(address(harness2));

        // Both start at zero.
        assertEq(facetViaHarness.globalCAID(), 0);
        assertEq(facet2.globalCAID(), 0);

        // Write directly to harness1's storage at the CAID slot to simulate
        // a completed action incrementing the counter.
        bytes32 storageSlot = CORPORATE_ACTION_STORAGE_LOCATION;
        vm.store(address(harness), storageSlot, bytes32(uint256(42)));

        // harness1 reflects the write, harness2 is unaffected.
        assertEq(facetViaHarness.globalCAID(), 42);
        assertEq(facet2.globalCAID(), 0);
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

    /// The facet implements ICorporateActionsV1.
    function testFacetImplementsInterface() external view {
        // Verify the call succeeds — that's the interface conformance test.
        facetViaHarness.globalCAID();
    }
}

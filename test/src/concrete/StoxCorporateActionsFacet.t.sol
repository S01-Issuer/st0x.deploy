// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {
    LibCorporateAction,
    CORPORATE_ACTION_STORAGE_LOCATION,
    SCHEDULE_CORPORATE_ACTION,
    CANCEL_CORPORATE_ACTION,
    UnknownActionType
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

/// @dev Harness to test library functions directly.
contract LibHarness {
    function resolveActionType(bytes32 typeHash, bytes memory parameters) external pure returns (uint256) {
        return LibCorporateAction.resolveActionType(typeHash, parameters);
    }

    function countCompleted() external pure returns (uint256) {
        return LibCorporateAction.countCompleted();
    }
}

contract StoxCorporateActionsFacetTest is Test {
    StoxCorporateActionsFacet internal facetImpl;
    DelegatecallHarness internal harness;
    StoxCorporateActionsFacet internal facetViaHarness;
    LibHarness internal libHarness;

    function setUp() public {
        facetImpl = new StoxCorporateActionsFacet();
        harness = new DelegatecallHarness(address(facetImpl));
        facetViaHarness = StoxCorporateActionsFacet(address(harness));
        libHarness = new LibHarness();
    }

    /// completedActionCount returns 0 on a fresh deployment.
    function testCompletedActionCountInitiallyZero() external view {
        assertEq(facetViaHarness.completedActionCount(), 0);
    }

    /// Facet routing via delegatecall works.
    function testFacetRoutingViaDelegatecall() external view {
        assertEq(facetViaHarness.completedActionCount(), 0);
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

    /// resolveActionType reverts with UnknownActionType for any hash.
    function testResolveActionTypeRevertsUnknown() external {
        bytes32 unknown = keccak256("SomethingRandom");
        vm.expectRevert(abi.encodeWithSelector(UnknownActionType.selector, unknown));
        libHarness.resolveActionType(unknown, "");
    }

    /// countCompleted returns 0 (placeholder).
    function testCountCompletedReturnsZero() external view {
        assertEq(libHarness.countCompleted(), 0);
    }
}

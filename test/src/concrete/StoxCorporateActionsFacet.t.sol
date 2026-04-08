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
import {IAuthorizeV1, Unauthorized} from "ethgild/interface/IAuthorizeV1.sol";

/// @dev Mock authorizer used by the facet tests. Records the most recent
/// `authorize` call so tests can assert the per-action context that the facet
/// passes through. When `denyMode` is true, every `authorize` call reverts
/// with `Unauthorized`, exercising the auth-denial code path.
contract MockAuthorizer is IAuthorizeV1 {
    bool public denyMode;
    address public lastUser;
    bytes32 public lastPermission;
    bytes public lastData;
    uint256 public callCount;

    function setDenyMode(bool deny) external {
        denyMode = deny;
    }

    function authorize(address user, bytes32 permission, bytes memory data) external override {
        callCount++;
        lastUser = user;
        lastPermission = permission;
        lastData = data;
        if (denyMode) {
            revert Unauthorized(user, permission, data);
        }
    }
}

/// @dev Minimal harness that delegates calls to a facet, simulating how the
/// vault would route unknown selectors via its fallback. Also exposes an
/// `authorizer()` function so the facet's `OffchainAssetReceiptVault(address
/// (this)).authorizer()` lookup resolves to a test-controlled mock instead of
/// a real ethgild authorizer.
contract DelegatecallHarness {
    address public immutable facet;
    IAuthorizeV1 public authorizer;

    constructor(address facet_) {
        facet = facet_;
    }

    function setAuthorizer(IAuthorizeV1 authorizer_) external {
        authorizer = authorizer_;
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
    MockAuthorizer internal mockAuthorizer;

    address internal constant ALICE = address(0xA11CE);

    function setUp() public {
        facetImpl = new StoxCorporateActionsFacet();
        harness = new DelegatecallHarness(address(facetImpl));
        facetViaHarness = StoxCorporateActionsFacet(address(harness));
        libHarness = new LibHarness();
        mockAuthorizer = new MockAuthorizer();
        harness.setAuthorizer(mockAuthorizer);
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

    /// `scheduleCorporateAction` calls the authorizer with the SCHEDULE
    /// permission and `abi.encode(typeHash, effectiveTime, parameters)` as
    /// the data argument. On PR1 the call reverts at the `resolveActionType`
    /// stub, so we use `vm.expectCall` (which survives the revert) to assert
    /// the authorizer call was made with the right arguments.
    function testScheduleCorporateActionForwardsContextToAuthorizer() external {
        bytes32 typeHash = keccak256("DefinitelyUnknownActionType");
        uint64 effectiveTime = 1500;
        bytes memory parameters = hex"deadbeef";

        vm.expectCall(
            address(mockAuthorizer),
            abi.encodeWithSelector(
                IAuthorizeV1.authorize.selector,
                ALICE,
                SCHEDULE_CORPORATE_ACTION,
                abi.encode(typeHash, effectiveTime, parameters)
            )
        );

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(UnknownActionType.selector, typeHash));
        facetViaHarness.scheduleCorporateAction(typeHash, effectiveTime, parameters);
    }

    /// `cancelCorporateAction` calls the authorizer with the CANCEL permission
    /// and `abi.encode(actionIndex)` as the data argument. On PR1 the cancel
    /// path is a no-op stub, so the outer call succeeds and we can also
    /// observe the mock's recorded state.
    function testCancelCorporateActionForwardsContextToAuthorizer() external {
        uint256 actionIndex = 42;

        vm.expectCall(
            address(mockAuthorizer),
            abi.encodeWithSelector(
                IAuthorizeV1.authorize.selector, ALICE, CANCEL_CORPORATE_ACTION, abi.encode(actionIndex)
            )
        );

        vm.prank(ALICE);
        facetViaHarness.cancelCorporateAction(actionIndex);

        assertEq(mockAuthorizer.callCount(), 1);
        assertEq(mockAuthorizer.lastUser(), ALICE);
        assertEq(mockAuthorizer.lastPermission(), CANCEL_CORPORATE_ACTION);
        assertEq(mockAuthorizer.lastData(), abi.encode(actionIndex));
    }

    /// `scheduleCorporateAction` propagates the authorizer's revert when the
    /// authorizer denies the action.
    function testScheduleCorporateActionRevertsWhenAuthorizerDenies() external {
        mockAuthorizer.setDenyMode(true);
        bytes32 typeHash = keccak256("DefinitelyUnknownActionType");
        uint64 effectiveTime = 1500;
        bytes memory parameters = hex"deadbeef";

        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                Unauthorized.selector, ALICE, SCHEDULE_CORPORATE_ACTION, abi.encode(typeHash, effectiveTime, parameters)
            )
        );
        facetViaHarness.scheduleCorporateAction(typeHash, effectiveTime, parameters);
    }

    /// `cancelCorporateAction` propagates the authorizer's revert when the
    /// authorizer denies the action.
    function testCancelCorporateActionRevertsWhenAuthorizerDenies() external {
        mockAuthorizer.setDenyMode(true);
        uint256 actionIndex = 7;

        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(Unauthorized.selector, ALICE, CANCEL_CORPORATE_ACTION, abi.encode(actionIndex))
        );
        facetViaHarness.cancelCorporateAction(actionIndex);
    }
}

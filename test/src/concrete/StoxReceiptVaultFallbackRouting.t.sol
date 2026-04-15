// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {ICorporateActionsV1} from "../../../src/interface/ICorporateActionsV1.sol";
import {LibProdDeployV3} from "../../../src/lib/LibProdDeployV3.sol";
import {
    STOCK_SPLIT_TYPE_HASH,
    ACTION_TYPE_STOCK_SPLIT,
    UnknownActionType
} from "../../../src/lib/LibCorporateAction.sol";
import {CompletionFilter} from "../../../src/lib/LibCorporateActionNode.sol";
import {IAuthorizeV1, Unauthorized} from "rain.vats/interface/IAuthorizeV1.sol";
import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";

/// @dev Slot 0 of the OffchainAssetReceiptVault ERC-7201 namespace
/// ("rain.storage.offchain-asset-receipt-vault.1") holds the authorizer
/// address. Copied here (rather than re-derived) so the tests do not depend
/// on the rain.vats internal constant layout beyond this single SSTORE.
bytes32 constant OFFCHAIN_ASSET_RECEIPT_VAULT_STORAGE_LOCATION =
    0xba9f160a0257aef2aa878e698d5363429ea67cc3c427f23f7cb9c3069b67bd00;

/// @dev Permissive authorizer used by the fallback routing tests. Records the
/// most recent call and allows every permission by default so we can exercise
/// the forward-to-facet path without reproducing the full ethgild auth setup.
contract PermissiveAuthorizer is IAuthorizeV1 {
    address public lastUser;
    bytes32 public lastPermission;
    bytes public lastData;
    uint256 public callCount;

    function authorize(address user, bytes32 permission, bytes memory data) external override {
        callCount++;
        lastUser = user;
        lastPermission = permission;
        lastData = data;
    }
}

/// Fallback routing tests for `StoxReceiptVault`. The vault's `fallback()`
/// override delegatecalls into `StoxCorporateActionsFacet` at the deterministic
/// `LibProdDeployV3.STOX_CORPORATE_ACTIONS_FACET` address.
///
/// The facet's `onlyDelegatecalled` modifier relies on an immutable `_SELF`
/// captured in the constructor. `vm.etch` would leave `_SELF` pointing at the
/// original temporary deploy address, so the "direct call reverts" assertion
/// would not exercise the real guard. We use `vm.deployCodeTo` instead which
/// runs the constructor at the target address, so the facet's `_SELF` matches
/// the `LibProdDeployV3` constant exactly.
contract StoxReceiptVaultFallbackRoutingTest is Test {
    StoxReceiptVault internal vault;
    PermissiveAuthorizer internal mockAuthorizer;
    address internal constant ALICE = address(0xA11CE);

    function setUp() public {
        // Plant the real facet at the production address, running its
        // constructor there so `_SELF` resolves to `STOX_CORPORATE_ACTIONS_FACET`.
        deployCodeTo(
            "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet",
            LibProdDeployV3.STOX_CORPORATE_ACTIONS_FACET
        );

        vault = new StoxReceiptVault();
        mockAuthorizer = new PermissiveAuthorizer();

        // Seed the vault's authorizer storage slot so the facet's internal
        // `OffchainAssetReceiptVault(address(this)).authorizer()` lookup
        // resolves to our permissive mock. Slot 0 of the ERC-7201 namespace
        // is the authorizer address.
        vm.store(
            address(vault),
            OFFCHAIN_ASSET_RECEIPT_VAULT_STORAGE_LOCATION,
            bytes32(uint256(uint160(address(mockAuthorizer))))
        );

        vm.warp(1000);
    }

    /// View entry points on the facet are reachable through the vault's
    /// fallback: `completedActionCount()` returns 0 on a fresh vault.
    function testCompletedActionCountRoutesThroughFallback() external view {
        assertEq(ICorporateActionsV1(address(vault)).completedActionCount(), 0);
    }

    /// `latestActionOfType` on a fresh vault returns (0, 0, 0) through the
    /// fallback delegatecall.
    function testLatestActionOfTypeRoutesThroughFallback() external view {
        (uint256 cursor, uint256 actionType, uint64 effectiveTime) =
            ICorporateActionsV1(address(vault)).latestActionOfType(ACTION_TYPE_STOCK_SPLIT, CompletionFilter.ALL);
        assertEq(cursor, 0);
        assertEq(actionType, 0);
        assertEq(effectiveTime, 0);
    }

    /// `scheduleCorporateAction` reaches the facet through the fallback,
    /// invokes the authorizer on the vault, and stores an action readable
    /// via `latestActionOfType`. Exercises the full write path.
    function testScheduleCorporateActionRoutesAndPersists() external {
        bytes memory params = abi.encode(LibDecimalFloat.packLossless(2, 0));
        uint64 effectiveTime = 2000;

        vm.prank(ALICE);
        uint256 actionIndex =
            ICorporateActionsV1(address(vault)).scheduleCorporateAction(STOCK_SPLIT_TYPE_HASH, effectiveTime, params);
        assertEq(actionIndex, 1);

        // Authorizer was invoked from the vault's context (address(this) in
        // the facet resolves to the vault).
        assertEq(mockAuthorizer.callCount(), 1);
        assertEq(mockAuthorizer.lastUser(), ALICE);

        // The scheduled action is readable through the fallback as well.
        (uint256 cursor, uint256 actionType, uint64 gotEffectiveTime) =
            ICorporateActionsV1(address(vault)).latestActionOfType(ACTION_TYPE_STOCK_SPLIT, CompletionFilter.PENDING);
        assertEq(cursor, 1);
        assertEq(actionType, ACTION_TYPE_STOCK_SPLIT);
        assertEq(gotEffectiveTime, effectiveTime);
    }

    /// Direct calls to the facet at its production address revert with
    /// `FacetMustBeDelegatecalled`. Because we used `vm.deployCodeTo`, the
    /// facet's `_SELF` immutable is the `LibProdDeployV3` constant and
    /// `address(this) == _SELF` on a direct call, firing the guard.
    function testDirectCallToFacetRevertsWithFacetMustBeDelegatecalled() external {
        ICorporateActionsV1 facetDirect = ICorporateActionsV1(LibProdDeployV3.STOX_CORPORATE_ACTIONS_FACET);
        vm.expectRevert(StoxCorporateActionsFacet.FacetMustBeDelegatecalled.selector);
        facetDirect.completedActionCount();
    }

    /// Reverts inside the facet propagate through the vault fallback with the
    /// original error selector. An unknown `typeHash` triggers
    /// `UnknownActionType` inside the facet's delegatecall, and the vault's
    /// assembly `revert(0, returndatasize())` forwards the full revert data.
    function testRevertInFacetPropagatesThroughFallback() external {
        bytes32 unknown = keccak256("not-a-real-action-type");
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(UnknownActionType.selector, unknown));
        ICorporateActionsV1(address(vault)).scheduleCorporateAction(unknown, 2000, "");
    }

    /// Plain ETH with empty calldata hits `receive()`, not `fallback()`, and
    /// the vault accepts it without invoking the facet delegatecall. If ETH
    /// were routed through `fallback()` the empty calldata would reach the
    /// facet, which has no selector-less entry point, and revert.
    function testPlainEthTransferHitsReceiveNotFallback() external {
        vm.deal(ALICE, 1 ether);
        uint256 pre = address(vault).balance;

        vm.prank(ALICE);
        (bool ok,) = address(vault).call{value: 0.5 ether}("");
        assertTrue(ok);
        assertEq(address(vault).balance, pre + 0.5 ether);

        // The authorizer was not touched; ETH transfer did not enter the
        // facet delegatecall path.
        assertEq(mockAuthorizer.callCount(), 0);
    }
}

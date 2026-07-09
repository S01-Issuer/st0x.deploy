// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {
    ICorporateActionsV1,
    ACTION_TYPE_INIT_V1,
    ACTION_TYPE_STOCK_SPLIT_V1
} from "../../../src/interface/ICorporateActionsV1.sol";
import {LibProdDeployV4} from "../../../src/lib/LibProdDeployV4.sol";
import {STOCK_SPLIT_V1_TYPE_HASH, UnknownActionType} from "../../../src/lib/LibCorporateAction.sol";
import {CompletionFilter, NODE_NONE} from "../../../src/lib/LibCorporateActionNode.sol";
import {IAuthorizeV1, Unauthorized} from "rain-vats-0.1.6/src/interface/IAuthorizeV1.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
import {LibTestTofu} from "../../lib/LibTestTofu.sol";
import {PermissiveAuthorizer} from "./PermissiveAuthorizer.sol";

/// @dev Slot 0 of the OffchainAssetReceiptVault ERC-7201 namespace
/// ("rain.storage.offchain-asset-receipt-vault.1") holds the authorizer
/// address. Copied here (rather than re-derived) so the tests do not depend
/// on the rain.vats internal constant layout beyond this single SSTORE.
bytes32 constant OFFCHAIN_ASSET_RECEIPT_VAULT_STORAGE_LOCATION =
    0xba9f160a0257aef2aa878e698d5363429ea67cc3c427f23f7cb9c3069b67bd00;

/// Fallback routing tests for `StoxReceiptVault`. The vault's `fallback()`
/// override delegatecalls into `StoxCorporateActionsFacet` at the deterministic
/// `LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_3` address.
///
/// The facet's `onlyDelegatecalled` modifier relies on an immutable `_SELF`
/// captured in the constructor. `vm.etch` would leave `_SELF` pointing at the
/// original temporary deploy address, so the "direct call reverts" assertion
/// would not exercise the real guard. We use `vm.deployCodeTo` instead which
/// runs the constructor at the target address, so the facet's `_SELF` matches
/// the `LibProdDeployV4` constant exactly.
contract StoxReceiptVaultFallbackRoutingTest is Test {
    StoxReceiptVault internal vault;
    PermissiveAuthorizer internal mockAuthorizer;
    address internal constant ALICE = address(0xA11CE);

    function setUp() public {
        // The TOFU singleton must be planted before any stock-split parameter
        // validation runs — `LibStockSplit.validateMultiplierV1` reads
        // `address(this).decimals()` through `LibTOFUTokenDecimals`.
        LibTestTofu.deployTofu(vm);

        // Plant the real facet at the production address, running its
        // constructor there so `_SELF` resolves to `STOX_CORPORATE_ACTIONS_FACET`.
        deployCodeTo(
            "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet",
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_3
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

    /// `latestActionOfType` on a fresh vault returns (NODE_NONE, 0, 0)
    /// through the fallback delegatecall.
    function testLatestActionOfTypeRoutesThroughFallback() external view {
        (uint256 cursor, uint256 actionType, uint64 effectiveTime) =
            ICorporateActionsV1(address(vault)).latestActionOfType(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.ALL);
        assertEq(cursor, NODE_NONE);
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
        uint256 actionIndex = ICorporateActionsV1(address(vault))
            .scheduleCorporateAction(STOCK_SPLIT_V1_TYPE_HASH, effectiveTime, params);
        // Bootstrap occupies idx 0, so this user action lands at idx 1.
        assertEq(actionIndex, 1);

        // Authorizer was invoked from the vault's context (address(this) in
        // the facet resolves to the vault).
        assertEq(mockAuthorizer.callCount(), 1);
        assertEq(mockAuthorizer.lastUser(), ALICE);

        // The scheduled action is readable through the fallback as well.
        (uint256 cursor, uint256 actionType, uint64 gotEffectiveTime) =
            ICorporateActionsV1(address(vault)).latestActionOfType(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(cursor, actionIndex);
        assertEq(actionType, ACTION_TYPE_STOCK_SPLIT_V1);
        assertEq(gotEffectiveTime, effectiveTime);
    }

    /// Cross-contract head-inclusive walk hits bootstrap (idx 0) when the
    /// mask includes `ACTION_TYPE_INIT_V1`. The receipt-side rebase relies
    /// on this — `LibReceiptRebase.migratedBalance` calls
    /// `vault.nextOfType(cursor, BALANCE_MIGRATION_TYPES_MASK, COMPLETED)`
    /// across the contract boundary, expecting bootstrap to surface as a
    /// real (idx 0) cursor when walking head-inclusive (cursor = NODE_NONE).
    /// Pins that the fallback delegatecall path returns idx 0 for this,
    /// not silently rewriting it through some sentinel translation layer.
    function testNextOfTypeHeadInclusiveReturnsBootstrap() external {
        // Schedule a user action so `ensureBootstrap` fires; bootstrap
        // is at idx 0, user action at idx 1.
        bytes memory params = abi.encode(LibDecimalFloat.packLossless(2, 0));
        vm.prank(ALICE);
        ICorporateActionsV1(address(vault)).scheduleCorporateAction(STOCK_SPLIT_V1_TYPE_HASH, 2000, params);

        // INIT-only mask + ALL filter: head-inclusive walk hits bootstrap.
        (uint256 cursor, uint256 actionType, uint64 effectiveTime) =
            ICorporateActionsV1(address(vault)).nextOfType(NODE_NONE, ACTION_TYPE_INIT_V1, CompletionFilter.ALL);
        assertEq(cursor, 0, "bootstrap is observable at idx 0 via cross-contract head-inclusive walk");
        assertEq(actionType, ACTION_TYPE_INIT_V1, "actionType matches bootstrap");
        assertEq(
            uint256(effectiveTime), block.timestamp, "bootstrap effectiveTime is block.timestamp at first schedule"
        );
    }

    /// Direct calls to the facet at its production address revert with
    /// `FacetMustBeDelegatecalled`. Because we used `vm.deployCodeTo`, the
    /// facet's `_SELF` immutable is the `LibProdDeployV4` constant and
    /// `address(this) == _SELF` on a direct call, firing the guard.
    function testDirectCallToFacetRevertsWithFacetMustBeDelegatecalled() external {
        ICorporateActionsV1 facetDirect = ICorporateActionsV1(LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_3);
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

    /// All four traversal getters route through the fallback and return the
    /// correct tuple. Schedules two stock splits and walks them in both
    /// directions, exercising `earliestActionOfType`, `latestActionOfType`,
    /// `nextOfType`, and `prevOfType` via the routed path.
    function testAllTraversalGettersRouteThroughFallback() external {
        bytes memory paramsA = abi.encode(LibDecimalFloat.packLossless(2, 0));
        bytes memory paramsB = abi.encode(LibDecimalFloat.packLossless(3, 0));

        // Bootstrap occupies idx 0; the two user actions land at idx 1 and 2.
        vm.prank(ALICE);
        uint256 idA =
            ICorporateActionsV1(address(vault)).scheduleCorporateAction(STOCK_SPLIT_V1_TYPE_HASH, 2000, paramsA);
        vm.prank(ALICE);
        uint256 idB =
            ICorporateActionsV1(address(vault)).scheduleCorporateAction(STOCK_SPLIT_V1_TYPE_HASH, 3000, paramsB);

        // earliest pending → first scheduled
        (uint256 cursor, uint256 actionType, uint64 effectiveTime) = ICorporateActionsV1(address(vault))
            .earliestActionOfType(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(cursor, idA);
        assertEq(actionType, ACTION_TYPE_STOCK_SPLIT_V1);
        assertEq(effectiveTime, 2000);

        // next from idA → second scheduled
        (cursor, actionType, effectiveTime) =
            ICorporateActionsV1(address(vault)).nextOfType(idA, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(cursor, idB);
        assertEq(actionType, ACTION_TYPE_STOCK_SPLIT_V1, "routed nextOfType returns the actionType tuple field");
        assertEq(effectiveTime, 3000);

        // prev from idB → first scheduled
        (cursor, actionType, effectiveTime) =
            ICorporateActionsV1(address(vault)).prevOfType(idB, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(cursor, idA);
        assertEq(actionType, ACTION_TYPE_STOCK_SPLIT_V1, "routed prevOfType returns the actionType tuple field");
        assertEq(effectiveTime, 2000);
    }

    /// `CompletionFilter` works correctly through the routed path: a warp
    /// past one of two scheduled splits flips the COMPLETED / PENDING
    /// partition, and the routed traversal returns the right cursor for
    /// each filter. Pins that the timestamp-driven completion check
    /// (`effectiveTime <= block.timestamp`) reads the outer transaction's
    /// timestamp under delegatecall — not the facet's own context.
    function testCompletionFilterAcrossRoutedTraversal() external {
        bytes memory params = abi.encode(LibDecimalFloat.packLossless(2, 0));

        vm.startPrank(ALICE);
        uint256 a = ICorporateActionsV1(address(vault)).scheduleCorporateAction(STOCK_SPLIT_V1_TYPE_HASH, 1500, params);
        uint256 b = ICorporateActionsV1(address(vault)).scheduleCorporateAction(STOCK_SPLIT_V1_TYPE_HASH, 5000, params);
        vm.stopPrank();

        // Warp past `a`'s effectiveTime but not `b`'s.
        vm.warp(2000);

        (uint256 completedCursor,,) = ICorporateActionsV1(address(vault))
            .latestActionOfType(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
        assertEq(completedCursor, a, "a is the only completed split");

        (uint256 pendingCursor,,) =
            ICorporateActionsV1(address(vault)).latestActionOfType(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(pendingCursor, b, "b is the only pending split");

        assertEq(
            ICorporateActionsV1(address(vault)).completedActionCount(),
            1,
            "exactly one completed action across the list"
        );
    }

    /// A sequence of routed schedule and cancel calls leaves the linked
    /// list in a coherent state, traversable end-to-end through the
    /// fallback. Schedules three nodes, cancels the middle one, and walks
    /// the remaining two via `nextOfType`.
    function testMultipleRoutedCallsPreserveListCoherence() external {
        bytes memory params = abi.encode(LibDecimalFloat.packLossless(2, 0));

        vm.startPrank(ALICE);
        uint256 a = ICorporateActionsV1(address(vault)).scheduleCorporateAction(STOCK_SPLIT_V1_TYPE_HASH, 2000, params);
        uint256 b = ICorporateActionsV1(address(vault)).scheduleCorporateAction(STOCK_SPLIT_V1_TYPE_HASH, 3000, params);
        uint256 c = ICorporateActionsV1(address(vault)).scheduleCorporateAction(STOCK_SPLIT_V1_TYPE_HASH, 4000, params);
        ICorporateActionsV1(address(vault)).cancelCorporateAction(b);
        vm.stopPrank();

        // Bootstrap occupies idx 0; user actions land at idx 1, 2, 3.
        assertEq(a, 1);
        assertEq(b, 2);
        assertEq(c, 3);

        // Walk forward from the head — should hit a (cursor 1) then c
        // (cursor 3), skipping the cancelled b.
        (uint256 cursor1,,) = ICorporateActionsV1(address(vault))
            .earliestActionOfType(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(cursor1, a);

        (uint256 cursor2,, uint64 effectiveTime2) = ICorporateActionsV1(address(vault))
            .nextOfType(cursor1, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(cursor2, c, "next-after-a is c, not the cancelled b");
        assertEq(effectiveTime2, 4000);

        // Walk past c — no further pending nodes.
        (uint256 cursor3,,) = ICorporateActionsV1(address(vault))
            .nextOfType(cursor2, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(cursor3, NODE_NONE);
    }

    /// `cancelCorporateAction` reaches the facet through the fallback,
    /// invokes the authorizer with `CANCEL_CORPORATE_ACTION`, unlinks the
    /// node, and the cancelled action is no longer findable via the
    /// COMPLETED-filtered traversal. Mirrors the schedule routing test for
    /// the cancel surface.
    function testCancelCorporateActionRoutesAndUnlinks() external {
        bytes memory params = abi.encode(LibDecimalFloat.packLossless(2, 0));

        vm.prank(ALICE);
        uint256 actionIndex =
            ICorporateActionsV1(address(vault)).scheduleCorporateAction(STOCK_SPLIT_V1_TYPE_HASH, 2000, params);

        uint256 callsBeforeCancel = mockAuthorizer.callCount();

        vm.prank(ALICE);
        ICorporateActionsV1(address(vault)).cancelCorporateAction(actionIndex);

        // Authorizer was invoked with the CANCEL permission.
        assertEq(mockAuthorizer.callCount(), callsBeforeCancel + 1);
        assertEq(mockAuthorizer.lastUser(), ALICE);
        assertEq(mockAuthorizer.lastPermission(), keccak256("CANCEL_CORPORATE_ACTION"));

        // The cancelled node is no longer reachable via the pending list —
        // cancel zeroes its prev/next pointers and resets effectiveTime.
        (uint256 cursor,,) =
            ICorporateActionsV1(address(vault)).latestActionOfType(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
        assertEq(cursor, NODE_NONE, "cancelled split is no longer pending");
    }

    /// `getActionParameters` returns the raw `bytes` payload through the
    /// fallback. Bytes returns are different shape from tuple returns —
    /// covered separately to confirm the routed path doesn't truncate or
    /// mis-handle dynamic-size returns.
    function testGetActionParametersRoutesThroughFallback() external {
        bytes memory params = abi.encode(LibDecimalFloat.packLossless(7, 0));
        vm.prank(ALICE);
        uint256 actionIndex =
            ICorporateActionsV1(address(vault)).scheduleCorporateAction(STOCK_SPLIT_V1_TYPE_HASH, 2000, params);

        bytes memory read = ICorporateActionsV1(address(vault)).getActionParameters(actionIndex);
        assertEq(read, params);
    }

    /// An authorizer that reverts with `Unauthorized` propagates the exact
    /// error tuple back through the vault's fallback. Asserts the error
    /// shape, not just that the call reverted, so a regression that
    /// swallows the revert data fails.
    function testAuthorizerDeniedScheduleRoutesAndReverts() external {
        mockAuthorizer.setDenyMode(true);
        bytes memory params = abi.encode(LibDecimalFloat.packLossless(2, 0));
        bytes memory expectedData = abi.encode(STOCK_SPLIT_V1_TYPE_HASH, uint64(2000), params);

        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(Unauthorized.selector, ALICE, keccak256("SCHEDULE_CORPORATE_ACTION"), expectedData)
        );
        ICorporateActionsV1(address(vault)).scheduleCorporateAction(STOCK_SPLIT_V1_TYPE_HASH, 2000, params);
    }

    /// ETH attached to a routed mutating call reverts. The vault's
    /// `fallback()` is payable, so msg.value enters the delegatecall, but
    /// `scheduleCorporateAction` on the facet is non-payable so its
    /// dispatch reverts when msg.value > 0. Pins that the routed call
    /// doesn't silently accept value into the facet path.
    function testRoutedMutatingCallWithValueReverts() external {
        bytes memory params = abi.encode(LibDecimalFloat.packLossless(2, 0));
        bytes memory data = abi.encodeWithSelector(
            ICorporateActionsV1.scheduleCorporateAction.selector, STOCK_SPLIT_V1_TYPE_HASH, uint64(2000), params
        );

        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        (bool ok,) = address(vault).call{value: 1}(data);
        assertFalse(ok, "routed call with non-zero value must revert at facet dispatch");
    }

    /// A call with an unknown selector hits the vault's fallback, gets
    /// delegatecalled into the facet, and reverts because the facet's
    /// dispatch doesn't recognize the selector. The vault forwards the
    /// empty revert data via `revert(0, returndatasize())`. Pins that
    /// unknown selectors don't silently succeed.
    function testRoutedCallWithUnknownSelectorReverts() external {
        bytes memory data = abi.encodeWithSelector(0xdeadbeef, uint256(1));

        vm.prank(ALICE);
        (bool ok,) = address(vault).call(data);
        assertFalse(ok, "unknown selector must not match anything in the facet");

        // Authorizer was not touched — the call reverted at the facet's
        // dispatch before any logic ran.
        assertEq(mockAuthorizer.callCount(), 0);
    }

    /// Calldata shorter than 4 bytes (no full selector) still hits the
    /// vault's fallback (Solidity's dispatch ignores anything that isn't
    /// a complete selector match). The truncated calldata gets
    /// delegatecalled into the facet, which can't dispatch to any
    /// selector, and reverts.
    function testRoutedCallWithTruncatedCalldataReverts() external {
        bytes memory truncated = hex"deadbe"; // 3 bytes, not enough for a selector

        vm.prank(ALICE);
        (bool ok,) = address(vault).call(truncated);
        assertFalse(ok, "truncated calldata routed through fallback must revert at facet dispatch");
        assertEq(mockAuthorizer.callCount(), 0);
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

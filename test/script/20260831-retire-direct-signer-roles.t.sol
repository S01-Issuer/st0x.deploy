// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";

import {
    OrchestratorPathNotEnabled,
    DirectSignerRolesAlreadyRetired,
    SafeMissingRoleAdminForRetire
} from "../../script/20260831-retire-direct-signer-roles.s.sol";
import {RetireDirectSignerRolesHarness} from "./RetireDirectSignerRolesHarness.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {SafeTx} from "../../src/lib/LibSafeOps.sol";

/// @title RetireDirectSignerRolesTest
/// @notice Guard coverage for `20260831-retire-direct-signer-roles` without
/// a fork: the burn-in gate, the `_ADMIN` refusal, the self-scoping, and
/// the already-retired refusal. The live-fork walk is in
/// `20260831-retire-direct-signer-roles.prod.t.sol`.
contract RetireDirectSignerRolesTest is Test {
    RetireDirectSignerRolesHarness internal harness;

    address internal constant SAFE = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
    address internal constant AUTHORISER = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
    address internal constant ORCHESTRATOR = LibProdDeployV4.ST0X_ORCHESTRATOR_INSTANCE;
    address internal constant SIGNER = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;

    function setUp() external {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        harness = new RetireDirectSignerRolesHarness();
        vm.etch(AUTHORISER, hex"fe");
        vm.etch(ORCHESTRATOR, hex"fe");
    }

    /// @notice Mock the fully-enabled burn-in state: orchestrator holds both
    /// vault roles, signer holds both orchestrator roles AND both direct
    /// vault roles, Safe holds the `_ADMIN`s.
    function mockBurnInState() internal {
        vm.mockCall(AUTHORISER, abi.encodeWithSelector(IAccessControl.hasRole.selector), abi.encode(true));
        vm.mockCall(ORCHESTRATOR, abi.encodeWithSelector(IAccessControl.hasRole.selector), abi.encode(true));
    }

    /// The burn-in gate refuses when the orchestrator lacks a vault role,
    /// naming the missing (holder, role) — retiring would strand the chain.
    function testGateRefusesWhenOrchestratorLacksVaultAccess() external {
        mockBurnInState();
        vm.mockCall(
            AUTHORISER, abi.encodeCall(IAccessControl.hasRole, (keccak256("WITHDRAW"), ORCHESTRATOR)), abi.encode(false)
        );
        vm.expectRevert(
            abi.encodeWithSelector(OrchestratorPathNotEnabled.selector, ORCHESTRATOR, keccak256("WITHDRAW"))
        );
        harness.callAssertOrchestratorPathEnabled(IAccessControl(AUTHORISER), ORCHESTRATOR);
    }

    /// The burn-in gate refuses when the signer lacks an orchestrator role.
    function testGateRefusesWhenSignerLacksOrchestratorRole() external {
        mockBurnInState();
        vm.mockCall(
            ORCHESTRATOR, abi.encodeCall(IAccessControl.hasRole, (keccak256("BURN"), SIGNER)), abi.encode(false)
        );
        vm.expectRevert(abi.encodeWithSelector(OrchestratorPathNotEnabled.selector, SIGNER, keccak256("BURN")));
        harness.callAssertOrchestratorPathEnabled(IAccessControl(AUTHORISER), ORCHESTRATOR);
    }

    /// The fully-enabled state passes the gate.
    function testGateAcceptsTheEnabledPath() external {
        mockBurnInState();
        harness.callAssertOrchestratorPathEnabled(IAccessControl(AUTHORISER), ORCHESTRATOR);
    }

    /// Authoring refuses when the Safe lacks a needed `_ADMIN`.
    function testAuthoringRefusesWithoutRoleAdmin() external {
        mockBurnInState();
        vm.mockCall(
            AUTHORISER, abi.encodeCall(IAccessControl.hasRole, (keccak256("WITHDRAW_ADMIN"), SAFE)), abi.encode(false)
        );
        vm.expectRevert(abi.encodeWithSelector(SafeMissingRoleAdminForRetire.selector, keccak256("WITHDRAW_ADMIN")));
        harness.callAuthorBundle(AUTHORISER, SAFE);
    }

    /// The burn-in state authors both revokes in the fixed order.
    function testAuthoringProducesBothRevokes() external {
        mockBurnInState();
        SafeTx[] memory txs = harness.callAuthorBundle(AUTHORISER, SAFE);
        assertEq(txs.length, 2);
        assertEq(txs[0].to, AUTHORISER);
        assertEq(txs[0].data, abi.encodeCall(IAccessControl.revokeRole, (keccak256("DEPOSIT"), SIGNER)));
        assertEq(txs[1].data, abi.encodeCall(IAccessControl.revokeRole, (keccak256("WITHDRAW"), SIGNER)));
    }

    /// A half-retired chain self-scopes to the remaining role.
    function testAuthoringSelfScopesAPartialRetirement() external {
        mockBurnInState();
        vm.mockCall(
            AUTHORISER, abi.encodeCall(IAccessControl.hasRole, (keccak256("DEPOSIT"), SIGNER)), abi.encode(false)
        );
        SafeTx[] memory txs = harness.callAuthorBundle(AUTHORISER, SAFE);
        assertEq(txs.length, 1);
        assertEq(txs[0].data, abi.encodeCall(IAccessControl.revokeRole, (keccak256("WITHDRAW"), SIGNER)));
    }

    /// A fully-retired chain refuses to author anything.
    function testAuthoringRefusesWhenAlreadyRetired() external {
        mockBurnInState();
        vm.mockCall(
            AUTHORISER, abi.encodeCall(IAccessControl.hasRole, (keccak256("DEPOSIT"), SIGNER)), abi.encode(false)
        );
        vm.mockCall(
            AUTHORISER, abi.encodeCall(IAccessControl.hasRole, (keccak256("WITHDRAW"), SIGNER)), abi.encode(false)
        );
        vm.expectRevert(DirectSignerRolesAlreadyRetired.selector);
        harness.callAuthorBundle(AUTHORISER, SAFE);
    }
}

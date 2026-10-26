// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";

import {OrchestratorPathNotEnabled} from "../../script/20260831-retire-direct-signer-roles.s.sol";
import {RetireDirectSignerRolesHarness} from "./RetireDirectSignerRolesHarness.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";

/// @title RetireDirectSignerRolesTest
/// @notice Guard coverage for `20260831-retire-direct-signer-roles` without
/// a fork: the burn-in gate, and the retired-state check. The live-fork walk is in
/// `20260831-retire-direct-signer-roles.prod.t.sol`.
contract RetireDirectSignerRolesTest is Test {
    RetireDirectSignerRolesHarness internal harness;

    address internal constant SAFE = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
    address internal constant AUTHORISER = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
    address internal constant ORCHESTRATOR = LibProdDeployV4.ST0X_ORCHESTRATOR_INSTANCE;
    address internal constant SIGNER = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;

    function setUp() external {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        harness = new RetireDirectSignerRolesHarness("unit");
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

    /// @notice Mock the retired state: burn-in with both direct vault roles
    /// gone from the signer.
    function mockRetiredState() internal {
        mockBurnInState();
        vm.mockCall(
            AUTHORISER, abi.encodeCall(IAccessControl.hasRole, (keccak256("DEPOSIT"), SIGNER)), abi.encode(false)
        );
        vm.mockCall(
            AUTHORISER, abi.encodeCall(IAccessControl.hasRole, (keccak256("WITHDRAW"), SIGNER)), abi.encode(false)
        );
    }

    /// The retired state passes the post-state check.
    function testPostStateAcceptsTheRetiredState() external {
        mockRetiredState();
        harness.callAssertPostRetireState(IAccessControl(AUTHORISER), ORCHESTRATOR, SAFE);
    }

    /// A signer still holding a direct vault role fails the post-state check.
    function testPostStateRefusesALingeringDirectRole() external {
        mockRetiredState();
        vm.mockCall(
            AUTHORISER, abi.encodeCall(IAccessControl.hasRole, (keccak256("WITHDRAW"), SIGNER)), abi.encode(true)
        );
        vm.expectRevert(bytes("RetireDirectSignerRoles: signer still holds a direct vault role"));
        harness.callAssertPostRetireState(IAccessControl(AUTHORISER), ORCHESTRATOR, SAFE);
    }

    /// Any other row of the canonical grant map going missing fails the
    /// post-state check: the retirement touches exactly two rows.
    function testPostStateRefusesADisturbedUnrelatedGrant() external {
        mockRetiredState();
        vm.mockCall(AUTHORISER, abi.encodeCall(IAccessControl.hasRole, (keccak256("CERTIFY"), SAFE)), abi.encode(false));
        vm.expectRevert(bytes("RetireDirectSignerRoles: retirement disturbed an unrelated grant"));
        harness.callAssertPostRetireState(IAccessControl(AUTHORISER), ORCHESTRATOR, SAFE);
    }
}

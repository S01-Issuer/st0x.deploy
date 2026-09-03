// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";

import {
    FleetNotUpgraded,
    SafeNotOrchestratorAdmin,
    OrchestratorRolesAlreadyEnabled
} from "../../script/20260831-enable-orchestrator-roles.s.sol";
import {EnableOrchestratorRolesHarness} from "./EnableOrchestratorRolesHarness.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {SafeTx} from "../../src/lib/LibSafeOps.sol";

/// @title EnableOrchestratorRolesTest
/// @notice Guard coverage for `20260831-enable-orchestrator-roles` without
/// a full replica: the fleet-upgrade interlock, the orchestrator-admin
/// refusal, the self-scoping, and the already-executed refusal are each
/// shown to fire. The live-fork walk of the rollout states is in
/// `20260831-enable-orchestrator-roles.prod.t.sol`.
contract EnableOrchestratorRolesTest is Test {
    EnableOrchestratorRolesHarness internal harness;

    address internal constant SAFE = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
    address internal constant AUTHORISER = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
    address internal constant ORCHESTRATOR = LibProdDeployV4.ST0X_ORCHESTRATOR_INSTANCE;
    address internal constant SIGNER = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;

    function setUp() external {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        harness = new EnableOrchestratorRolesHarness();
    }

    /// @notice Mock Base's three in-use production beacons pointing at the
    /// 0.1.30 receipt/vault impls (the post-fleet-upgrade state).
    function mockUpgradedFleet() internal {
        address[3] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(LibSafeInvariants.BASE_CHAIN_ID);
        vm.etch(beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX], hex"fe");
        vm.etch(beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX], hex"fe");
        vm.mockCall(
            beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX],
            abi.encodeCall(IBeacon.implementation, ()),
            abi.encode(LibProdDeployV4.STOX_RECEIPT_0_1_30)
        );
        vm.mockCall(
            beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX],
            abi.encodeCall(IBeacon.implementation, ()),
            abi.encode(LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30)
        );
    }

    /// @notice Mock the canonical grant map fully held on the authoriser,
    /// with no principal holding `DEFAULT_ADMIN_ROLE`, and the Safe holding
    /// orchestrator admin. `hasRole` defaults are then narrowed per test.
    function mockHealthyPrincipals() internal {
        vm.etch(AUTHORISER, hex"fe");
        vm.etch(ORCHESTRATOR, hex"fe");
        // Default every authoriser hasRole probe to true, then carve out the
        // DEFAULT_ADMIN probes the map assertion requires to be false.
        vm.mockCall(AUTHORISER, abi.encodeWithSelector(IAccessControl.hasRole.selector), abi.encode(true));
        address[4] memory admins = [SAFE, SAFE, LibAuthoriserInvariants.GRANTEE_SERVICE_1C66, SIGNER];
        for (uint256 i = 0; i < admins.length; i++) {
            vm.mockCall(AUTHORISER, abi.encodeCall(IAccessControl.hasRole, (bytes32(0), admins[i])), abi.encode(false));
        }
        // The retired signer holds nothing (absence pin).
        bytes32[3] memory actionRoles = [keccak256("DEPOSIT"), keccak256("WITHDRAW"), keccak256("CERTIFY")];
        for (uint256 i = 0; i < actionRoles.length; i++) {
            vm.mockCall(
                AUTHORISER,
                abi.encodeCall(IAccessControl.hasRole, (actionRoles[i], LibAuthoriserInvariants.GRANTEE_SERVICE_1C66)),
                abi.encode(false)
            );
        }
        // Orchestrator: Safe is admin; signer holds nothing yet; the
        // orchestrator itself holds no direct vault roles yet.
        vm.mockCall(ORCHESTRATOR, abi.encodeWithSelector(IAccessControl.hasRole.selector), abi.encode(false));
        vm.mockCall(ORCHESTRATOR, abi.encodeCall(IAccessControl.hasRole, (bytes32(0), SAFE)), abi.encode(true));
        bytes32[2] memory vaultRoles = [keccak256("DEPOSIT"), keccak256("WITHDRAW")];
        for (uint256 i = 0; i < vaultRoles.length; i++) {
            vm.mockCall(
                AUTHORISER, abi.encodeCall(IAccessControl.hasRole, (vaultRoles[i], ORCHESTRATOR)), abi.encode(false)
            );
        }
    }

    /// The fleet-upgrade interlock refuses beacons still on pre-0.1.30
    /// impls, naming the beacon and both impls.
    function testFleetGateRefusesUnupgradedBeacons() external {
        address[3] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(LibSafeInvariants.BASE_CHAIN_ID);
        vm.etch(beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX], hex"fe");
        vm.mockCall(
            beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX],
            abi.encodeCall(IBeacon.implementation, ()),
            abi.encode(LibProdDeployV4.STOX_RECEIPT_0_1_1)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                FleetNotUpgraded.selector,
                beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX],
                LibProdDeployV4.STOX_RECEIPT_0_1_30,
                LibProdDeployV4.STOX_RECEIPT_0_1_1
            )
        );
        harness.callAssertFleetUpgraded();
    }

    /// The interlock passes once both gated beacons point at 0.1.30.
    function testFleetGateAcceptsUpgradedBeacons() external {
        mockUpgradedFleet();
        harness.callAssertFleetUpgraded();
    }

    /// Authoring refuses when the Safe lacks `DEFAULT_ADMIN_ROLE` on the
    /// orchestrator — the bundle's orchestrator grants could never execute.
    function testAuthoringRefusesWithoutOrchestratorAdmin() external {
        mockHealthyPrincipals();
        vm.mockCall(ORCHESTRATOR, abi.encodeCall(IAccessControl.hasRole, (bytes32(0), SAFE)), abi.encode(false));
        vm.expectRevert(abi.encodeWithSelector(SafeNotOrchestratorAdmin.selector, ORCHESTRATOR));
        harness.callAuthorBundle(AUTHORISER, ORCHESTRATOR, SAFE);
    }

    /// The fresh pre-enable state authors all four transactions in the
    /// fixed order: grant orchestrator both vault roles, grant the signer
    /// both orchestrator roles. NO revokes — the signer's direct roles stay
    /// for the parallel burn-in window.
    function testAuthoringProducesTheFullFourTxBundle() external {
        mockHealthyPrincipals();
        SafeTx[] memory txs = harness.callAuthorBundle(AUTHORISER, ORCHESTRATOR, SAFE);
        assertEq(txs.length, 4);
        assertEq(txs[0].to, AUTHORISER);
        assertEq(txs[0].data, abi.encodeCall(IAccessControl.grantRole, (keccak256("DEPOSIT"), ORCHESTRATOR)));
        assertEq(txs[1].data, abi.encodeCall(IAccessControl.grantRole, (keccak256("WITHDRAW"), ORCHESTRATOR)));
        assertEq(txs[2].to, ORCHESTRATOR);
        assertEq(txs[2].data, abi.encodeCall(IAccessControl.grantRole, (keccak256("MINT"), SIGNER)));
        assertEq(txs[3].to, ORCHESTRATOR);
        assertEq(txs[3].data, abi.encodeCall(IAccessControl.grantRole, (keccak256("BURN"), SIGNER)));
    }

    /// A partially-executed cutover self-scopes: an orchestrator grant that
    /// already landed is not re-authored (the canonical map is untouched by
    /// EXTRA holders, so the map gate still passes).
    function testAuthoringSelfScopesLandedOrchestratorGrants() external {
        mockHealthyPrincipals();
        vm.mockCall(
            AUTHORISER, abi.encodeCall(IAccessControl.hasRole, (keccak256("DEPOSIT"), ORCHESTRATOR)), abi.encode(true)
        );
        SafeTx[] memory txs = harness.callAuthorBundle(AUTHORISER, ORCHESTRATOR, SAFE);
        assertEq(txs.length, 3);
        assertEq(txs[0].data, abi.encodeCall(IAccessControl.grantRole, (keccak256("WITHDRAW"), ORCHESTRATOR)));
    }

    /// A fully-enabled chain refuses to author anything — and because the
    /// enable removes no map rows, this refusal is reachable immediately
    /// after execution, before any pin PR.
    function testRefusesWhenAlreadyEnabled() external {
        mockHealthyPrincipals();
        vm.mockCall(
            AUTHORISER, abi.encodeCall(IAccessControl.hasRole, (keccak256("DEPOSIT"), ORCHESTRATOR)), abi.encode(true)
        );
        vm.mockCall(
            AUTHORISER, abi.encodeCall(IAccessControl.hasRole, (keccak256("WITHDRAW"), ORCHESTRATOR)), abi.encode(true)
        );
        vm.mockCall(ORCHESTRATOR, abi.encodeCall(IAccessControl.hasRole, (keccak256("MINT"), SIGNER)), abi.encode(true));
        vm.mockCall(ORCHESTRATOR, abi.encodeCall(IAccessControl.hasRole, (keccak256("BURN"), SIGNER)), abi.encode(true));
        vm.mockCall(ORCHESTRATOR, abi.encodeCall(IAccessControl.hasRole, (bytes32(0), SAFE)), abi.encode(true));
        vm.expectRevert(OrchestratorRolesAlreadyEnabled.selector);
        harness.callAuthorBundle(AUTHORISER, ORCHESTRATOR, SAFE);
    }
}

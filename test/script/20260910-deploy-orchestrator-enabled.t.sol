// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";

import {
    DeployKeyHoldsRole,
    SignerMissingOrchestratorRole
} from "../../script/20260910-deploy-orchestrator-enabled.s.sol";
import {OrchestratorAlreadyDeployed, InstanceAddressMismatch} from "../../script/20260818-deploy-orchestrator.s.sol";
import {FleetNotUpgraded} from "../../script/20260831-enable-orchestrator-roles.s.sol";
import {DeployOrchestratorEnabledHarness} from "./DeployOrchestratorEnabledHarness.sol";
import {ClosureNotDeployed} from "../../src/lib/LibClosureInvariants.sol";
import {ExpectedGrantMissing, LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {
    LibOrchestratorInvariants,
    ST0xOrchestratorBeaconSetDeployerLike,
    OrchestratorAdminMissing
} from "../../src/lib/LibOrchestratorInvariants.sol";
import {IST0xOrchestratorV1} from "../../src/interface/IST0xOrchestratorV1.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";

/// @title DeployOrchestratorEnabledTest
/// @notice Every gate of the enabled orchestrator deploy, driven with mocks
/// so each refusal is shown to fire; the end-to-end path runs on a live
/// fork in the `.prod` suite.
contract DeployOrchestratorEnabledTest is Test {
    DeployOrchestratorEnabledHarness internal harness;

    address internal constant SAFE = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
    address internal constant AUTHORISER = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
    address internal constant ORCHESTRATOR = LibProdDeployV4.ST0X_ORCHESTRATOR_INSTANCE;
    address internal constant SIGNER = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;
    address internal constant DEPLOY_KEY = address(0xDEAD);

    function setUp() external {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        harness = new DeployOrchestratorEnabledHarness();
    }

    function mockUpgradedFleet() internal {
        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(LibSafeInvariants.BASE_CHAIN_ID);
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

    function mockBeaconSet() internal {
        vm.mockCall(
            LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30,
            abi.encodeCall(ST0xOrchestratorBeaconSetDeployerLike.iOrchestratorBeacon, ()),
            abi.encode(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON)
        );
        vm.mockCall(
            LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON,
            abi.encodeCall(IBeacon.implementation, ()),
            abi.encode(LibProdDeployV4.ST0X_ORCHESTRATOR_0_1_30)
        );
        vm.mockCall(
            LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON, abi.encodeCall(Ownable.owner, ()), abi.encode(SAFE)
        );
        vm.etch(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON, hex"fe");
    }

    /// @notice The enabled end state: authoriser on the canonical map
    /// (orchestrator rows included), orchestrator with the Safe as admin and
    /// the signer on MINT/BURN, the deploy key holding nothing.
    function mockEnabledState() internal {
        vm.etch(AUTHORISER, hex"fe");
        vm.etch(ORCHESTRATOR, hex"fe");
        vm.mockCall(AUTHORISER, abi.encodeWithSelector(IAccessControl.hasRole.selector), abi.encode(true));
        address[5] memory admins = [SAFE, SAFE, LibAuthoriserInvariants.GRANTEE_SERVICE_1C66, SIGNER, ORCHESTRATOR];
        for (uint256 i = 0; i < admins.length; i++) {
            vm.mockCall(AUTHORISER, abi.encodeCall(IAccessControl.hasRole, (bytes32(0), admins[i])), abi.encode(false));
        }
        bytes32[3] memory actionRoles = [keccak256("DEPOSIT"), keccak256("WITHDRAW"), keccak256("CERTIFY")];
        for (uint256 i = 0; i < actionRoles.length; i++) {
            vm.mockCall(
                AUTHORISER,
                abi.encodeCall(IAccessControl.hasRole, (actionRoles[i], LibAuthoriserInvariants.GRANTEE_SERVICE_1C66)),
                abi.encode(false)
            );
        }
        vm.mockCall(ORCHESTRATOR, abi.encodeWithSelector(IAccessControl.hasRole.selector), abi.encode(false));
        vm.mockCall(ORCHESTRATOR, abi.encodeCall(IAccessControl.hasRole, (bytes32(0), SAFE)), abi.encode(true));
        vm.mockCall(ORCHESTRATOR, abi.encodeCall(IAccessControl.hasRole, (keccak256("MINT"), SIGNER)), abi.encode(true));
        vm.mockCall(ORCHESTRATOR, abi.encodeCall(IAccessControl.hasRole, (keccak256("BURN"), SIGNER)), abi.encode(true));
        vm.mockCall(ORCHESTRATOR, abi.encodeCall(IST0xOrchestratorV1.vaultLogicIsExpected, ()), abi.encode(true));
    }

    function testClosureRefusesABlankChain() external {
        vm.expectRevert(
            abi.encodeWithSelector(ClosureNotDeployed.selector, LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_30)
        );
        harness.assertClosureReady();
    }

    function testRefusesWhenInstanceAlreadyDeployed() external {
        vm.etch(ORCHESTRATOR, hex"fe");
        vm.expectRevert(abi.encodeWithSelector(OrchestratorAlreadyDeployed.selector, ORCHESTRATOR));
        harness.assertNoInstanceYet(LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30);
    }

    function testFleetGateRefusesUnupgradedBeacons() external {
        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(LibSafeInvariants.BASE_CHAIN_ID);
        mockUpgradedFleet();
        vm.mockCall(
            beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX],
            abi.encodeCall(IBeacon.implementation, ()),
            abi.encode(LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                FleetNotUpgraded.selector,
                beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX],
                LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30,
                LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1
            )
        );
        harness.assertFleetUpgraded();
    }

    function testFleetGateAcceptsUpgradedBeacons() external {
        mockUpgradedFleet();
        harness.assertFleetUpgraded();
    }

    function testLandedRefusesAnUnpinnedInstance() external {
        vm.expectRevert(abi.encodeWithSelector(InstanceAddressMismatch.selector, ORCHESTRATOR, address(0xBAD)));
        harness.assertEnabledLanded(address(0xBAD), SAFE, AUTHORISER, DEPLOY_KEY);
    }

    function testLandedRefusesWhenSafeLacksAdmin() external {
        mockBeaconSet();
        mockEnabledState();
        vm.mockCall(ORCHESTRATOR, abi.encodeCall(IAccessControl.hasRole, (bytes32(0), SAFE)), abi.encode(false));
        vm.expectRevert(abi.encodeWithSelector(OrchestratorAdminMissing.selector, ORCHESTRATOR, SAFE));
        harness.assertEnabledLanded(ORCHESTRATOR, SAFE, AUTHORISER, DEPLOY_KEY);
    }

    /// @notice Any role left on the deploy key — admin OR operational — is a
    /// failed hand-off. MINT is the one a half-done ceremony is likeliest to
    /// leave behind.
    function testLandedRefusesWhenDeployKeyHoldsARole() external {
        mockBeaconSet();
        mockEnabledState();
        vm.mockCall(
            ORCHESTRATOR, abi.encodeCall(IAccessControl.hasRole, (keccak256("MINT"), DEPLOY_KEY)), abi.encode(true)
        );
        vm.expectRevert(
            abi.encodeWithSelector(DeployKeyHoldsRole.selector, ORCHESTRATOR, keccak256("MINT"), DEPLOY_KEY)
        );
        harness.assertEnabledLanded(ORCHESTRATOR, SAFE, AUTHORISER, DEPLOY_KEY);
    }

    function testLandedRefusesWhenSignerLacksBurn() external {
        mockBeaconSet();
        mockEnabledState();
        vm.mockCall(
            ORCHESTRATOR, abi.encodeCall(IAccessControl.hasRole, (keccak256("BURN"), SIGNER)), abi.encode(false)
        );
        vm.expectRevert(abi.encodeWithSelector(SignerMissingOrchestratorRole.selector, ORCHESTRATOR, keccak256("BURN")));
        harness.assertEnabledLanded(ORCHESTRATOR, SAFE, AUTHORISER, DEPLOY_KEY);
    }

    /// @notice The orchestrator's vault access is the authoriser ceremony's
    /// to grant; if the map lacks it the chain is not enabled, whatever the
    /// orchestrator's own roles say.
    function testLandedRefusesAnAuthoriserWithoutTheOrchestratorRows() external {
        mockBeaconSet();
        mockEnabledState();
        vm.mockCall(
            AUTHORISER, abi.encodeCall(IAccessControl.hasRole, (keccak256("WITHDRAW"), ORCHESTRATOR)), abi.encode(false)
        );
        vm.expectRevert(
            abi.encodeWithSelector(ExpectedGrantMissing.selector, AUTHORISER, keccak256("WITHDRAW"), ORCHESTRATOR)
        );
        harness.assertEnabledLanded(ORCHESTRATOR, SAFE, AUTHORISER, DEPLOY_KEY);
    }

    function testLandedAcceptsTheEnabledState() external {
        mockBeaconSet();
        mockEnabledState();
        harness.assertEnabledLanded(ORCHESTRATOR, SAFE, AUTHORISER, DEPLOY_KEY);
    }
}

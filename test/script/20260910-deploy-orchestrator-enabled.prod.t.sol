// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";

import {DeployOrchestratorEnabled} from "../../script/20260910-deploy-orchestrator-enabled.s.sol";
import {OrchestratorAlreadyDeployed} from "../../script/20260818-deploy-orchestrator.s.sol";
import {
    EnableOrchestratorRoles,
    FleetNotUpgraded,
    OrchestratorRolesAlreadyEnabled
} from "../../script/20260831-enable-orchestrator-roles.s.sol";
import {ClosureNotDeployed} from "../../src/lib/LibClosureInvariants.sol";
import {AuthoriserNotReady, LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {IST0xOrchestratorBeaconSetDeployerV1} from "../../src/interface/IST0xOrchestratorBeaconSetDeployerV1.sol";

/// @notice The enabled-orchestrator rollout deadline passed with this chain
/// still pending. Run the outstanding dispatches, extend the deadline, or
/// delete the invariant.
/// @param label The chain still pending.
error OrchestratorEnabledRolloutOverdue(string label);

/// @title DeployOrchestratorEnabledProdTest
/// @notice PROD coverage for the enabled orchestrator deploy on the chains
/// that bootstrap through it, read from a real fork with no mocks, walking
/// the bootstrap states:
///
/// 1. **Closure missing**: the pre-flight refuses on the first closure
///    contract.
/// 2. **Authoriser pin unhydrated** (closure live): refuses
///    `AuthoriserNotReady` — the ceremony + hydration PR come first.
/// 3. **Fleet on 0.1.1** (authoriser live): refuses `FleetNotUpgraded` —
///    `20260909-upgrade-and-migrate-token-beacons` comes first.
/// 4. **Ready**: simulates the ceremony `run()` performs on the fork — instance at its
///    pin, Safe admin, signer on MINT/BURN, deploy key clean, canonical
///    map intact — then proves the Safe-bundle enable script has nothing
///    left to author (`OrchestratorRolesAlreadyEnabled`).
/// 5. **Executed**: the steady state above holds on-chain; a re-dispatch
///    refuses (`OrchestratorAlreadyDeployed`) and so does the enable
///    script.
///
/// States 1-4 stop passing at the rollout deadline; state 5 is steady.
contract DeployOrchestratorEnabledProdTest is Test {
    /// @notice Shared with the Robinhood / BNB parity legs.
    uint256 internal constant ROLLOUT_DEADLINE = 1_796_083_200;

    address internal constant SIGNER = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;

    function assertEnabledSteadyState(string memory label) internal view {
        address instance = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;
        address safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibOrchestratorInvariants.assertBeaconSet(safe);
        LibOrchestratorInvariants.assertInstance(safe);
        IAccessControl orch = IAccessControl(instance);
        assertTrue(orch.hasRole(keccak256("MINT"), SIGNER), string.concat(label, ": signer lacks MINT"));
        assertTrue(orch.hasRole(keccak256("BURN"), SIGNER), string.concat(label, ": signer lacks BURN"));
        address authoriser = LibAuthoriserInvariants.activeChainAuthoriser();
        LibAuthoriserInvariants.assertExpectedGrants(authoriser, safe);
        assertTrue(
            IAccessControl(authoriser).hasRole(keccak256("DEPOSIT"), instance),
            string.concat(label, ": orchestrator lacks DEPOSIT on the authoriser")
        );
    }

    function pending(string memory label, string memory what) internal view {
        if (block.timestamp >= ROLLOUT_DEADLINE) {
            revert OrchestratorEnabledRolloutOverdue(label);
        }
        console2.log(string.concat("PENDING [", label, "]: ", what));
    }

    function assertRollout(string memory label, address authoriserPin) internal {
        DeployOrchestratorEnabled script = new DeployOrchestratorEnabled();
        EnableOrchestratorRoles enable = new EnableOrchestratorRoles();
        address instance = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;

        if (LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30.code.length == 0) {
            pending(label, "0.1.30 closure not deployed -> dispatch manual-sol-artifacts-0-1-30");
            vm.expectRevert(
                abi.encodeWithSelector(ClosureNotDeployed.selector, LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_30)
            );
            script.run();
            return;
        }

        if (instance.code.length != 0) {
            assertEnabledSteadyState(label);
            vm.expectRevert(abi.encodeWithSelector(OrchestratorAlreadyDeployed.selector, instance));
            script.run();
            vm.expectRevert(OrchestratorRolesAlreadyEnabled.selector);
            enable.run();
            return;
        }

        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        address receiptImpl = IBeacon(beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX]).implementation();
        if (receiptImpl != LibProdDeployV4.STOX_RECEIPT_0_1_30) {
            pending(label, "fleet not on 0.1.30 -> run 20260909-upgrade-and-migrate-token-beacons");
            vm.expectRevert(
                abi.encodeWithSelector(
                    FleetNotUpgraded.selector,
                    beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX],
                    LibProdDeployV4.STOX_RECEIPT_0_1_30,
                    receiptImpl
                )
            );
            script.run();
            return;
        }

        if (authoriserPin == address(0)) {
            pending(label, "authoriser pin unhydrated -> ceremony + hydration PR");
            vm.expectRevert(abi.encodeWithSelector(AuthoriserNotReady.selector, address(0)));
            script.run();
            return;
        }

        pending(label, "ready - simulating the enabled deploy ceremony on the fork");
        simulateCeremony(script, label);
        assertEnabledSteadyState(label);
        vm.expectRevert(OrchestratorRolesAlreadyEnabled.selector);
        enable.run();
    }

    /// @notice Drive the ceremony `run()` performs, step by step, as a
    /// synthetic deploy key: `deploy(deployer)`, the two signer grants, the
    /// admin hand-off to the Safe, the deploy key's renounce — then run the
    /// script's own `assertEnabledLanded` against the result. Driven inline
    /// under `vm.prank` because `vm.startBroadcast` (which `run()` wraps
    /// around the sequence) is mutually exclusive with `vm.prank` in
    /// `forge test`, and `msg.sender` inside `run()` would be this test
    /// contract rather than the broadcaster. Mirrors
    /// `DeployV4AuthoriserCloneTest.testHappyPathLeavesExpectedGrantsAndNoDeployerAdmin`.
    /// @param script The script whose post-state assertion is exercised.
    /// @param label Human chain name for messages.
    function simulateCeremony(DeployOrchestratorEnabled script, string memory label) internal {
        address deployer = makeAddr("orchestrator-enabled-deploy-key");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address authoriser = LibAuthoriserInvariants.activeChainAuthoriser();
        address setDeployer = LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30;

        vm.prank(deployer, deployer);
        address instance = IST0xOrchestratorBeaconSetDeployerV1(setDeployer).deploy(deployer);
        assertEq(instance, LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE, string.concat(label, ": instance pin"));

        IAccessControl orch = IAccessControl(instance);
        vm.prank(deployer, deployer);
        orch.grantRole(keccak256("MINT"), SIGNER);
        vm.prank(deployer, deployer);
        orch.grantRole(keccak256("BURN"), SIGNER);
        vm.prank(deployer, deployer);
        orch.grantRole(bytes32(0), safe);
        vm.prank(deployer, deployer);
        orch.renounceRole(bytes32(0), deployer);

        script.assertEnabledLanded(instance, safe, authoriser, deployer);
    }

    function testOrchestratorEnabledRolloutRobinhood() external {
        vm.createSelectFork(LibStoxDeployNetworks.ROBINHOOD);
        assertRollout("robinhood", LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ROBINHOOD);
    }

    function testOrchestratorEnabledRolloutBsc() external {
        vm.createSelectFork(LibStoxDeployNetworks.BSC);
        assertRollout("bsc", LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_BSC);
    }
}

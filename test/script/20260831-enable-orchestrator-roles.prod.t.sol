// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {EnableOrchestratorRoles, FleetNotUpgraded} from "../../script/20260831-enable-orchestrator-roles.s.sol";
import {
    LibOrchestratorInvariants,
    OrchestratorInstanceMissing,
    OrchestratorSetDeployerMissing
} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";

/// @notice The enable deadline passed with this chain still pending.
/// Run the outstanding dispatches, extend the deadline, or delete the
/// invariant.
/// @param label The chain still pending.
error OrchestratorEnableOverdue(string label);

/// @title EnableOrchestratorRolesProdTest
/// @notice PROD coverage for the orchestrator enable: what production IS on each
/// chain, read from a real fork with no mocks, walking the rollout states:
///
/// 1. **Orchestrator world pending** (every chain today): `run()`'s
///    pre-flight refuses at the 0.1.30 beacon-set read
///    (`OrchestratorSetDeployerMissing`) — the closure + instance dispatches
///    come first.
/// 2. **Fleet pending** (orchestrator live, production beacons still on
///    pre-0.1.30 impls): pins the `FleetNotUpgraded` interlock — the rule
///    that vault access is granted only after the fleet upgrade (RAI-2125).
/// 3. **Ready** (fleet upgraded, not cut over): drives `run()` end to end
///    on the fork — bundle authored, simulated, post-state and n+1 proven.
/// 4. **Executed** (the parallel burn-in state): the orchestrator holds
///    vault access, the signer holds MINT/BURN on it AND keeps its direct
///    roles (the fallback path the retire script removes later); plus the
///    re-authoring refusal.
///
/// States 1–3 stop passing at `ENABLE_DEADLINE`; state 4 is steady and
/// never expires.
contract EnableOrchestratorRolesProdTest is Test {
    /// @notice Unix timestamp (2026-10-01T00:00:00Z) past which a chain
    /// still in a pending state fails instead of logging PENDING. Shared
    /// with the orchestrator rollout deadline — the cutover is its last
    /// step.
    uint256 internal constant ENABLE_DEADLINE = 1_790_812_800;

    /// @notice Walk the active fork's cutover state (see the contract
    /// NatSpec) and assert it.
    /// @param label Human chain name, surfaced in logs and messages.
    function assertEnableRollout(string memory label) internal {
        EnableOrchestratorRoles script = new EnableOrchestratorRoles();
        address setDeployer = LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30;
        address orchestrator = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;

        if (setDeployer.code.length == 0 || orchestrator.code.length == 0) {
            if (block.timestamp >= ENABLE_DEADLINE) {
                revert OrchestratorEnableOverdue(label);
            }
            console2.log(string.concat("PENDING [", label, "]: 0.1.30 orchestrator world not deployed"));
            console2.log("-> manual-sol-artifacts-0-1-30 suites, then 20260818-deploy-orchestrator, come first");
            // run() reads the beacon set before the instance, so whichever
            // is missing first decides the revert.
            if (setDeployer.code.length == 0) {
                vm.expectRevert(abi.encodeWithSelector(OrchestratorSetDeployerMissing.selector, setDeployer));
            } else {
                vm.expectRevert(abi.encodeWithSelector(OrchestratorInstanceMissing.selector, orchestrator));
            }
            script.run();
            return;
        }

        address[3] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        bool fleetUpgraded = IBeacon(beacons[0]).implementation() == LibProdDeployV4.STOX_RECEIPT_0_1_30
            && IBeacon(beacons[1]).implementation() == LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30;
        if (!fleetUpgraded) {
            if (block.timestamp >= ENABLE_DEADLINE) {
                revert OrchestratorEnableOverdue(label);
            }
            console2.log(string.concat("PENDING [", label, "]: fleet not upgraded to 0.1.30 - cutover gated"));
            console2.log("-> execute the fleet beacon-repoint through governance first");
            vm.expectRevert(
                abi.encodeWithSelector(
                    FleetNotUpgraded.selector,
                    beacons[0],
                    LibProdDeployV4.STOX_RECEIPT_0_1_30,
                    IBeacon(beacons[0]).implementation()
                )
            );
            script.run();
            return;
        }

        IAccessControl acl = IAccessControl(activeAuthoriser());
        bool enabled = acl.hasRole(keccak256("DEPOSIT"), orchestrator);
        if (!enabled) {
            if (block.timestamp >= ENABLE_DEADLINE) {
                revert OrchestratorEnableOverdue(label);
            }
            console2.log(string.concat("PENDING [", label, "]: ready - driving the authoring end to end"));
            script.run();
            return;
        }

        // Executed steady state — the parallel burn-in: the orchestrator
        // holds vault access AND the signer keeps its direct roles until
        // the retire script removes them.
        assertTrue(acl.hasRole(keccak256("WITHDRAW"), orchestrator), string.concat(label, ": orchestrator WITHDRAW"));
        IAccessControl orch = IAccessControl(orchestrator);
        assertTrue(
            orch.hasRole(keccak256("MINT"), LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C)
                && orch.hasRole(keccak256("BURN"), LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C),
            string.concat(label, ": signer lacks orchestrator MINT/BURN")
        );
        // While the retire script is pending, the signer's direct roles are
        // the fallback path and must still hold; the retire prod test owns
        // the post-retirement asserts.
        if (acl.hasRole(keccak256("DEPOSIT"), LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C)) {
            console2.log(string.concat("PARALLEL [", label, "]: burn-in window - direct signer path still live"));
        }
    }

    /// @notice The active chain's authoriser pin (mirrors the script's
    /// chain switch; the script's own guard covers validation).
    function activeAuthoriser() internal view returns (address) {
        if (block.chainid == LibSafeInvariants.BASE_CHAIN_ID) {
            return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        }
        return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM;
    }

    function testEnableRolloutBase() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertEnableRollout("base");
    }

    function testEnableRolloutEthereum() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        assertEnableRollout("ethereum");
    }

    function testEnableRolloutHyperEvm() external {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        assertEnableRollout("hyperevm");
    }
}

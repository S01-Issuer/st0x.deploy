// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {RetireDirectSignerRoles, RETIRE_DEADLINE} from "../../script/20260831-retire-direct-signer-roles.s.sol";
import {LibOrchestratorInvariants, OrchestratorSetDeployerMissing} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";

/// @notice The retirement deadline passed with this chain still pending.
/// Run the outstanding dispatches, extend the deadline, or delete the
/// invariant.
/// @param label The chain still pending.
error RetirementOverdue(string label);

/// @title RetireDirectSignerRolesProdTest
/// @notice PROD coverage for the direct-role retirement: what production IS
/// on each chain, read from a real fork with no mocks, walking the states:
///
/// 1. **Orchestrator world pending** (every chain today): `run()`'s
///    pre-flight refuses at the 0.1.30 beacon-set read.
/// 2. **Burn-in pending** (orchestrator live but path not fully enabled):
///    the burn-in gate refuses — retirement can never strand a chain
///    without a working mint path.
/// 3. **Burn-in** (path enabled, direct roles still live): drives `run()`
///    end to end — revokes authored and simulated, post-state and n+1
///    proven. The window between states 3 and 4 is DELIBERATE: the
///    fallback path stays until the orchestrator has proven itself.
/// 4. **Retired**: the signer holds no direct vault roles; asserted
///    directly.
///
/// States 1–3 stop passing at `RETIRE_DEADLINE` (two weeks after the
/// enable/fleet deadline, honouring the burn-in); state 4 is steady.
contract RetireDirectSignerRolesProdTest is Test {
    /// @notice Walk the active fork's retirement state (see the contract
    /// NatSpec) and assert it.
    /// @param label Human chain name, surfaced in logs and messages.
    function assertRetireRollout(string memory label) internal {
        RetireDirectSignerRoles script = new RetireDirectSignerRoles();
        address setDeployer = LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30;
        address orchestrator = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;
        address signer = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;

        if (setDeployer.code.length == 0 || orchestrator.code.length == 0) {
            if (block.timestamp >= RETIRE_DEADLINE) {
                revert RetirementOverdue(label);
            }
            console2.log(string.concat("PENDING [", label, "]: 0.1.30 orchestrator world not deployed"));
            vm.expectRevert(abi.encodeWithSelector(OrchestratorSetDeployerMissing.selector, setDeployer));
            script.run();
            return;
        }

        IAccessControl acl = IAccessControl(activeAuthoriser());
        bool pathEnabled = acl.hasRole(keccak256("DEPOSIT"), orchestrator)
            && acl.hasRole(keccak256("WITHDRAW"), orchestrator)
            && IAccessControl(orchestrator).hasRole(keccak256("MINT"), signer)
            && IAccessControl(orchestrator).hasRole(keccak256("BURN"), signer);
        if (!pathEnabled) {
            if (block.timestamp >= RETIRE_DEADLINE) {
                revert RetirementOverdue(label);
            }
            console2.log(string.concat("PENDING [", label, "]: orchestrator path not enabled - retirement gated"));
            console2.log("-> execute 20260831-enable-orchestrator-roles (and its burn-in) first");
            vm.expectRevert();
            script.run();
            return;
        }

        bool retired = !acl.hasRole(keccak256("DEPOSIT"), signer) && !acl.hasRole(keccak256("WITHDRAW"), signer);
        if (!retired) {
            if (block.timestamp >= RETIRE_DEADLINE) {
                revert RetirementOverdue(label);
            }
            console2.log(string.concat("BURN-IN [", label, "]: driving the retirement authoring end to end"));
            script.run();
            return;
        }

        // Retired steady state: the orchestrator is the signer's only path.
        assertFalse(acl.hasRole(keccak256("DEPOSIT"), signer), string.concat(label, ": signer direct DEPOSIT"));
        assertFalse(acl.hasRole(keccak256("WITHDRAW"), signer), string.concat(label, ": signer direct WITHDRAW"));
    }

    /// @notice The active chain's authoriser pin (the script's own guard
    /// covers validation).
    function activeAuthoriser() internal view returns (address) {
        if (block.chainid == LibSafeInvariants.BASE_CHAIN_ID) {
            return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        }
        return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM;
    }

    function testRetireRolloutBase() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertRetireRollout("base");
    }

    function testRetireRolloutEthereum() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        assertRetireRollout("ethereum");
    }

    function testRetireRolloutHyperEvm() external {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        assertRetireRollout("hyperevm");
    }
}

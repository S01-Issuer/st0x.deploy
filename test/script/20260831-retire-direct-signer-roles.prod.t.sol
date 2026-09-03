// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {
    RetireDirectSignerRoles,
    RETIRE_DEADLINE,
    OrchestratorPathNotEnabled
} from "../../script/20260831-retire-direct-signer-roles.s.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
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
/// 1. **Burn-in pending** (every chain today: orchestrator live, path not
///    fully enabled):
///    the burn-in gate refuses — retirement can never strand a chain
///    without a working mint path.
/// 2. **Burn-in** (path enabled, direct roles still live): drives `run()`
///    end to end — revokes authored and simulated, post-state and n+1
///    proven. The window between states 2 and 3 is DELIBERATE: the
///    fallback path stays until the orchestrator has proven itself.
/// 3. **Retired**: the signer holds no direct vault roles; asserted
///    directly.
///
/// States 1–2 stop passing at `RETIRE_DEADLINE` (two weeks after the
/// enable/fleet deadline, honouring the burn-in); state 3 is steady.
contract RetireDirectSignerRolesProdTest is Test {
    /// @notice Walk the active fork's retirement state (see the contract
    /// NatSpec) and assert it.
    /// @param label Human chain name, surfaced in logs and messages.
    function assertRetireRollout(string memory label) internal {
        RetireDirectSignerRoles script = new RetireDirectSignerRoles();
        address orchestrator = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;
        address signer = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;

        IAccessControl acl = IAccessControl(LibAuthoriserInvariants.activeChainAuthoriser());
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
            (address holder, bytes32 role) = firstMissingGrant(acl, orchestrator, signer);
            vm.expectRevert(abi.encodeWithSelector(OrchestratorPathNotEnabled.selector, holder, role));
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

    /// @notice The first (holder, role) the burn-in gate finds missing, in
    /// the gate's own order.
    function firstMissingGrant(IAccessControl acl, address orchestrator, address signer)
        internal
        view
        returns (address, bytes32)
    {
        if (!acl.hasRole(keccak256("DEPOSIT"), orchestrator)) return (orchestrator, keccak256("DEPOSIT"));
        if (!acl.hasRole(keccak256("WITHDRAW"), orchestrator)) return (orchestrator, keccak256("WITHDRAW"));
        if (!IAccessControl(orchestrator).hasRole(keccak256("MINT"), signer)) return (signer, keccak256("MINT"));
        return (signer, keccak256("BURN"));
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

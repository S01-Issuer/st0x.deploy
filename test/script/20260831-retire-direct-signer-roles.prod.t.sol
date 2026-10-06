// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {console2} from "forge-std-1.16.2/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibRainDeploy} from "rain-deploy-0.1.10/src/lib/LibRainDeploy.sol";

import {
    RETIRE_DEADLINE,
    OrchestratorPathNotEnabled,
    SafeMissingRoleAdminForRetire
} from "../../script/20260831-retire-direct-signer-roles.s.sol";
import {RetireDirectSignerRolesHarness} from "./RetireDirectSignerRolesHarness.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @notice The retirement deadline passed with this chain still pending.
/// Run the outstanding dispatches, extend the deadline, or delete the
/// invariant.
/// @param label The chain still pending.
error RetirementOverdue(string label);

/// @title RetireDirectSignerRolesProdTest
/// @notice PROD coverage for the direct-role retirement: what production IS
/// on each chain, read from a real fork with no mocks.
///
/// The authoriser's `_ADMIN` roles are on the governance timelock, so the
/// Safe can no longer author the revokes this script bundles: until the
/// signer's direct roles are gone, every chain must refuse with
/// `SafeMissingRoleAdminForRetire`, and the retirement has to be scheduled
/// through the timelock instead. A chain whose orchestrator path is not
/// fully enabled refuses earlier, at the burn-in gate. Once retired, the
/// signer holds no direct vault role.
///
/// Every not-yet-retired state stops passing at `RETIRE_DEADLINE`.
contract RetireDirectSignerRolesProdTest is Test {
    /// @notice Walk the active fork's retirement state (see the contract
    /// NatSpec) and assert it.
    /// @param label Human chain name, surfaced in logs and messages.
    /// @param chainId The chain the leg must be forked on.
    function assertRetireRollout(string memory label, uint256 chainId) internal {
        assertEq(block.chainid, chainId, string.concat(label, ": fork"));
        RetireDirectSignerRolesHarness script = new RetireDirectSignerRolesHarness();
        address orchestrator = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;
        address signer = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;

        IAccessControl acl = IAccessControl(LibAuthoriserInvariants.activeChainAuthoriser());
        bool retired = !acl.hasRole(keccak256("DEPOSIT"), signer) && !acl.hasRole(keccak256("WITHDRAW"), signer);
        if (retired) {
            // Retired steady state: the orchestrator is the signer's only
            // path, so it must be fully enabled.
            if (!pathFullyEnabled(acl, orchestrator, signer)) {
                (address holder, bytes32 role) = firstMissingGrant(acl, orchestrator, signer);
                revert OrchestratorPathNotEnabled(holder, role);
            }
            return;
        }

        // A date on a rollout plan, not a race: the window is days wide, so the
        // seconds a validator could skew cannot change which side of it we are on.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp >= RETIRE_DEADLINE) {
            revert RetirementOverdue(label);
        }

        if (!pathFullyEnabled(acl, orchestrator, signer)) {
            console2.log(string.concat("PENDING [", label, "]: orchestrator path not enabled - retirement gated"));
            (address holder, bytes32 role) = firstMissingGrant(acl, orchestrator, signer);
            vm.expectRevert(abi.encodeWithSelector(OrchestratorPathNotEnabled.selector, holder, role));
            script.run();
            return;
        }

        console2.log(
            string.concat(
                "PENDING [",
                label,
                "]: signer's direct DEPOSIT/WITHDRAW still live; the Safe no longer holds the authoriser",
                " _ADMIN roles, so the retirement must be scheduled through the governance timelock"
            )
        );
        vm.expectRevert(abi.encodeWithSelector(SafeMissingRoleAdminForRetire.selector, keccak256("DEPOSIT_ADMIN")));
        script.run();

        // The same revokes scheduled through the timelock land: the timelock
        // administers both roles.
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        vm.startPrank(timelock);
        acl.revokeRole(keccak256("DEPOSIT"), signer);
        acl.revokeRole(keccak256("WITHDRAW"), signer);
        vm.stopPrank();
        assertFalse(acl.hasRole(keccak256("DEPOSIT"), signer), string.concat(label, ": signer direct DEPOSIT"));
        assertFalse(acl.hasRole(keccak256("WITHDRAW"), signer), string.concat(label, ": signer direct WITHDRAW"));
    }

    /// @notice Whether the orchestrator path is fully enabled: the
    /// orchestrator holds both vault roles and the signer both orchestrator
    /// roles.
    function pathFullyEnabled(IAccessControl acl, address orchestrator, address signer) internal view returns (bool) {
        return acl.hasRole(keccak256("DEPOSIT"), orchestrator) && acl.hasRole(keccak256("WITHDRAW"), orchestrator)
            && IAccessControl(orchestrator).hasRole(keccak256("MINT"), signer)
            && IAccessControl(orchestrator).hasRole(keccak256("BURN"), signer);
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
        assertRetireRollout("base", LibSafeInvariants.BASE_CHAIN_ID);
    }

    function testRetireRolloutEthereum() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        assertRetireRollout("ethereum", LibSafeInvariants.ETHEREUM_CHAIN_ID);
    }

    function testRetireRolloutHyperEvm() external {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        assertRetireRollout("hyperevm", LibSafeInvariants.HYPEREVM_CHAIN_ID);
    }

    function testRetireRolloutRobinhood() external {
        vm.createSelectFork(LibStoxDeployNetworks.ROBINHOOD);
        assertRetireRollout("robinhood", LibSafeInvariants.ROBINHOOD_CHAIN_ID);
    }

    function testRetireRolloutBsc() external {
        vm.createSelectFork(LibStoxDeployNetworks.BSC);
        assertRetireRollout("bsc", LibSafeInvariants.BSC_CHAIN_ID);
    }

    /// @notice A new chain still in burn-in is overdue at the deadline like
    /// any other.
    function testRetireRolloutOverdueOnANewChain() external {
        vm.createSelectFork(LibStoxDeployNetworks.ROBINHOOD);
        vm.warp(RETIRE_DEADLINE);
        vm.expectRevert(abi.encodeWithSelector(RetirementOverdue.selector, "robinhood"));
        this.externalAssertRetireRollout("robinhood", LibSafeInvariants.ROBINHOOD_CHAIN_ID);
    }

    /// @notice External shim so `vm.expectRevert` can see the helper's revert.
    function externalAssertRetireRollout(string memory label, uint256 chainId) external {
        assertRetireRollout(label, chainId);
    }
}

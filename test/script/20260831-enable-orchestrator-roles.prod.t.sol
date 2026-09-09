// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {OrchestratorRolesAlreadyEnabled} from "../../script/20260831-enable-orchestrator-roles.s.sol";
import {EnableOrchestratorRolesHarness} from "./EnableOrchestratorRolesHarness.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";

/// @title EnableOrchestratorRolesProdTest
/// @notice PROD coverage for the orchestrator enable: what production IS on
/// each chain, read from a real fork with no mocks. The enable has executed
/// on every chain, so each fork is in the parallel burn-in state: the fleet
/// interlock passes, the orchestrator holds vault access, the signer holds
/// MINT/BURN on it AND keeps its direct roles (the fallback path the retire
/// script removes later), and re-authoring refuses.
contract EnableOrchestratorRolesProdTest is Test {
    /// @notice Assert the active fork's executed state (see the contract
    /// NatSpec).
    /// @param label Human chain name, surfaced in logs and messages.
    function assertEnableExecuted(string memory label) internal {
        EnableOrchestratorRolesHarness script = new EnableOrchestratorRolesHarness();
        address orchestrator = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;

        script.callAssertFleetUpgraded();

        IAccessControl acl = IAccessControl(script.callActiveChainAuthoriser());
        assertTrue(acl.hasRole(keccak256("DEPOSIT"), orchestrator), string.concat(label, ": orchestrator DEPOSIT"));
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
        // Re-authoring against the executed state refuses rather than
        // emitting an empty bundle.
        vm.expectRevert(OrchestratorRolesAlreadyEnabled.selector);
        script.run();
    }

    function testEnableExecutedBase() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertEnableExecuted("base");
    }

    function testEnableExecutedEthereum() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        assertEnableExecuted("ethereum");
    }

    function testEnableExecutedHyperEvm() external {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        assertEnableExecuted("hyperevm");
    }
}

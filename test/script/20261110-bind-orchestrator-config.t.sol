// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.30/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.30/src/lib/LibSafeTxBuilderJson.sol";

import {SafeNotOrchestratorConfigDelegate} from "../../script/20261110-bind-orchestrator-config.s.sol";
import {BindOrchestratorConfigHarness} from "./BindOrchestratorConfigHarness.sol";
import {BackfillMigrationRegistryV5Harness} from "./BackfillMigrationRegistryV5Harness.sol";
import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";
import {LibProdOrchestratorParams} from "../../src/lib/LibProdOrchestratorParams.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations, UnexpectedMigrationLine} from "../../src/lib/LibStoxMigrations.sol";
import {LibTestConfigRegistryDelegates} from "../lib/LibTestConfigRegistryDelegates.sol";
import {LibTestOrchestratorConfigBind} from "../lib/LibTestOrchestratorConfigBind.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";

/// @title BindOrchestratorConfigTest
/// @notice The bind on every deployment network at its pinned pre-backfill
/// block, with the V5 backfill bundle executed first and the root's unscoped
/// approval of the Safe written on the fork.
contract BindOrchestratorConfigTest is Test {
    function executeBackfill(address safe, string memory tag) internal {
        LibSafeFork.executeBundle(
            vm, Safe(payable(safe)), new BackfillMigrationRegistryV5Harness(tag).callAuthorBundle()
        );
    }

    function onChain(string memory message) internal view returns (string memory) {
        return string.concat(vm.toString(block.chainid), ": ", message);
    }

    function assertBundle(string memory network) internal {
        LibTestPreBackfillFork.select(vm, network);
        BindOrchestratorConfigHarness script = new BindOrchestratorConfigHarness(network);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        bytes32 id = LibStoxMigrations.BIND_ORCHESTRATOR_CONFIG;
        LibTestOrchestratorConfigBind.approveSafe(vm, safe);

        vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, MIGRATION_HEAD_GENESIS));
        script.callPreflight();
        executeBackfill(safe, network);

        uint256 preRun = vm.snapshotState();
        script.run();
        vm.revertToState(preRun);

        string memory artifactPath = script.callArtifactPath();
        script.verify(artifactPath);

        (, address artifactSafe, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, vm.readFile(artifactPath));
        assertEq(artifactSafe, safe, onChain("artifact Safe"));
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);

        assertEq(
            LibTestOrchestratorConfigBind.boundBeacon(),
            LibProdOrchestratorParams.orchestratorParams().beacon,
            onChain("bound beacon")
        );
        assertEq(
            LibStoxConfig.orchestratorInitialAdmin(),
            LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK,
            onChain("bound initial admin")
        );
        assertEq(LibStoxMigrations.applied(id), block.timestamp, onChain("record moment"));
        assertEq(LibStoxMigrations.head(), id, onChain("line head"));

        vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, id));
        script.callPreflight();
    }

    function backfilledWithoutUnscopedApproval(string memory tag)
        internal
        returns (BindOrchestratorConfigHarness, address)
    {
        LibTestPreBackfillFork.select(vm, LibStoxDeployNetworks.HYPEREVM);
        BindOrchestratorConfigHarness script = new BindOrchestratorConfigHarness(tag);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        executeBackfill(safe, tag);
        LibTestConfigRegistryDelegates.revokeUnscoped(vm, safe);
        return (script, safe);
    }

    function testBindLandsFromASafeTheRootApprovesForEachNameAlone() external {
        (BindOrchestratorConfigHarness script, address safe) = backfilledWithoutUnscopedApproval("scoped");
        LibTestConfigRegistryDelegates.approve(vm, LibStoxConfig.ORCHESTRATOR_BEACON_NAME, safe);
        LibTestConfigRegistryDelegates.approve(vm, LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME, safe);
        script.callPreflight();
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), script.callAuthorBundle());
        script.callAssertPostState();
    }

    function testPreflightRefusesASafeTheRootDoesNotApprove() external {
        (BindOrchestratorConfigHarness script, address safe) = backfilledWithoutUnscopedApproval("unapproved");
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeNotOrchestratorConfigDelegate.selector, LibStoxConfig.ORCHESTRATOR_BEACON_NAME, safe
            )
        );
        script.callPreflight();
    }

    function assertPreflightRefusesASafeApprovedOnlyFor(bytes32 approved, bytes32 unapproved) internal {
        (BindOrchestratorConfigHarness script, address safe) = backfilledWithoutUnscopedApproval("unapproved");
        LibTestConfigRegistryDelegates.approve(vm, approved, safe);
        vm.expectRevert(abi.encodeWithSelector(SafeNotOrchestratorConfigDelegate.selector, unapproved, safe));
        script.callPreflight();
    }

    function testPreflightRefusesASafeTheRootDoesNotApproveAsBeaconBinder() external {
        assertPreflightRefusesASafeApprovedOnlyFor(
            LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME, LibStoxConfig.ORCHESTRATOR_BEACON_NAME
        );
    }

    function testPreflightRefusesASafeTheRootDoesNotApproveAsInitialAdminBinder() external {
        assertPreflightRefusesASafeApprovedOnlyFor(
            LibStoxConfig.ORCHESTRATOR_BEACON_NAME, LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME
        );
    }

    function testBindBundleOnEveryDeploymentNetwork() external {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            assertBundle(networks[i]);
        }
    }

    function testArtifactIsTheChainsJsonUnderOut() external {
        BindOrchestratorConfigHarness script = new BindOrchestratorConfigHarness("path");
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            assertEq(
                script.callScriptArtifactPath(),
                string.concat("out/20261110-bind-orchestrator-config-", vm.toString(networks[i].chainId), ".json")
            );
        }
    }
}

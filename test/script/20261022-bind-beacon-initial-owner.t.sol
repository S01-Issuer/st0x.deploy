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

import {SafeNotBeaconInitialOwnerDelegate} from "../../script/20261022-bind-beacon-initial-owner.s.sol";
import {BindBeaconInitialOwnerHarness} from "./BindBeaconInitialOwnerHarness.sol";
import {BackfillMigrationRegistryV5Harness} from "./BackfillMigrationRegistryV5Harness.sol";
import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations, UnexpectedMigrationLine} from "../../src/lib/LibStoxMigrations.sol";
import {LibTestBeaconInitialOwnerBind} from "../lib/LibTestBeaconInitialOwnerBind.sol";
import {LibTestConfigRegistryDelegates} from "../lib/LibTestConfigRegistryDelegates.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";

/// @title BindBeaconInitialOwnerTest
/// @notice The bind on every deployment network at its pinned pre-backfill
/// block, with the V5 backfill bundle executed first, the root's unscoped
/// approval of the Safe and the governance timelock written on the fork.
contract BindBeaconInitialOwnerTest is Test {
    function executeBackfill(address safe, string memory tag) internal {
        LibSafeFork.executeBundle(
            vm, Safe(payable(safe)), new BackfillMigrationRegistryV5Harness(tag).callAuthorBundle()
        );
    }

    function deployTimelock(address safe) internal {
        assertEq(
            LibTestBeaconInitialOwnerBind.deployTimelock(vm, safe),
            LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK,
            onChain("timelock address")
        );
    }

    function onChain(string memory message) internal view returns (string memory) {
        return string.concat(vm.toString(block.chainid), ": ", message);
    }

    function assertBundle(string memory network) internal {
        LibTestPreBackfillFork.select(vm, network);
        BindBeaconInitialOwnerHarness script = new BindBeaconInitialOwnerHarness(network);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK;
        bytes32 id = LibStoxMigrations.BIND_BEACON_INITIAL_OWNER;
        deployTimelock(safe);
        LibTestBeaconInitialOwnerBind.approveSafe(vm, safe);

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

        assertEq(LibStoxConfig.beaconInitialOwner(), timelock, onChain("bound timelock"));
        assertEq(LibStoxMigrations.applied(id), block.timestamp, onChain("record moment"));
        assertEq(LibStoxMigrations.head(), id, onChain("line head"));

        vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, id));
        script.callPreflight();
    }

    function backfilledWithoutApproval(string memory tag) internal returns (BindBeaconInitialOwnerHarness, address) {
        LibTestPreBackfillFork.select(vm, LibStoxDeployNetworks.HYPEREVM);
        BindBeaconInitialOwnerHarness script = new BindBeaconInitialOwnerHarness(tag);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        deployTimelock(safe);
        executeBackfill(safe, tag);
        return (script, safe);
    }

    function testBindLandsFromASafeTheRootApprovesForTheNameAlone() external {
        (BindBeaconInitialOwnerHarness script, address safe) = backfilledWithoutApproval("scoped");
        LibTestConfigRegistryDelegates.approve(vm, LibStoxConfig.BEACON_INITIAL_OWNER_NAME, safe);
        script.callPreflight();
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), script.callAuthorBundle());
        script.callAssertPostState();
    }

    function testPreflightRefusesASafeTheRootDoesNotApproveAsBinder() external {
        (BindBeaconInitialOwnerHarness script, address safe) = backfilledWithoutApproval("unapproved");
        vm.expectRevert(abi.encodeWithSelector(SafeNotBeaconInitialOwnerDelegate.selector, safe));
        script.callPreflight();
    }

    function testBindBundleOnEveryDeploymentNetwork() external {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            assertBundle(networks[i]);
        }
    }

    function testArtifactIsTheChainsJsonUnderOut() external {
        BindBeaconInitialOwnerHarness script = new BindBeaconInitialOwnerHarness("path");
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            assertEq(
                script.callScriptArtifactPath(),
                string.concat("out/20261022-bind-beacon-initial-owner-", vm.toString(networks[i].chainId), ".json")
            );
        }
    }
}

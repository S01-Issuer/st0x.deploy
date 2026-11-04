// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {OwnerManager} from "safe-global-safe-smart-account-1.4.1-3/contracts/base/OwnerManager.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {IMigrationRegistryV5} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.30/src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibConfigRegistryDeploy.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";
import {LibSafe} from "rain-deploy-0.1.30/src/lib/LibSafe.sol";
import {LibSafeFork} from "rain-deploy-0.1.30/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.30/src/lib/LibSafeTxBuilderJson.sol";
import {ITimelockControllerState, LibTimelockController} from "rain-deploy-0.1.30/src/lib/LibTimelockController.sol";

import {
    BeaconInitialOwnerBindingMismatch,
    BindBeaconInitialOwnerRecordMismatch,
    BindBeaconInitialOwnerUnexpectedLine,
    SafeNotBeaconInitialOwnerDelegate,
    bindBeaconInitialOwnerDeclaration
} from "../../script/20261022-bind-beacon-initial-owner.s.sol";
import {migrateMultisigThresholdDeclaration} from "../../script/20260619-migrate-multisig-threshold.s.sol";
import {BindBeaconInitialOwnerHarness} from "./BindBeaconInitialOwnerHarness.sol";
import {BackfillMigrationRegistryV5Harness} from "./BackfillMigrationRegistryV5Harness.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {StoxGovernanceTimelock} from "../../src/concrete/StoxGovernanceTimelock.sol";
import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";

/// @dev A Safe line write past the bind.
bytes32 constant LATER = keccak256("later");

/// @title BindBeaconInitialOwnerTest
/// @notice The bind on every deployment network at a block pinned before the
/// V5 backfill, with every predecessor on the Safe's line, the root's approval
/// of the Safe and the governance timelock written on the fork.
contract BindBeaconInitialOwnerTest is Test {
    IConfigRegistryV5 internal constant CONFIG_REGISTRY =
        IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);

    /// @dev Applies every predecessor on the Safe's line.
    function advanceLine(address safe, string memory tag) internal {
        LibSafeFork.executeBundle(
            vm, Safe(payable(safe)), new BackfillMigrationRegistryV5Harness(tag).callAuthorBundle()
        );
        LibSafeFork.executeBundle(
            vm, Safe(payable(safe)), new OrchestratorAdminToTimelockHarness(tag).callAuthorBundle()
        );
        (address to, bytes memory data) = LibStoxMigrations.recordCall(
            migrateMultisigThresholdDeclaration(), safe, LibTimelockInvariants.timelockForChainId(block.chainid)
        );
        LibSafeFork.simulateCall(vm, Safe(payable(safe)), to, data);
    }

    /// @dev The governance timelock, proposed by the Safe.
    function deployTimelock(address safe) internal {
        vm.prank(LibStoxConfig.ROOT_AUTHORITY);
        CONFIG_REGISTRY.registerV5(
            LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.TIMELOCK_INITIAL_PROPOSER_NAME, "address", abi.encode(safe), ""
        );
        assertEq(
            LibRainDeploy.etchAndDeployZoltu(vm, type(StoxGovernanceTimelock).creationCode),
            LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK,
            "timelock address"
        );
    }

    /// @dev The root approves the Safe.
    function approveSafe(address safe) internal {
        vm.prank(LibStoxConfig.ROOT_AUTHORITY);
        CONFIG_REGISTRY.approveV5(LibStoxConfig.BEACON_INITIAL_OWNER_NAME, safe);
    }

    function assertBundle(string memory network) internal {
        LibTestPreBackfillFork.select(vm, network);
        BindBeaconInitialOwnerHarness script = new BindBeaconInitialOwnerHarness(network);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK;
        bytes32 id = bindBeaconInitialOwnerDeclaration().id;
        deployTimelock(safe);
        advanceLine(safe, network);
        approveSafe(safe);

        uint256 preRun = vm.snapshotState();
        script.run();
        vm.revertToState(preRun);

        string memory artifactPath = script.callArtifactPath();
        script.verify(artifactPath);

        (, address artifactSafe, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, vm.readFile(artifactPath));
        assertEq(artifactSafe, safe, "artifact Safe");
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);

        assertEq(LibStoxConfig.beaconInitialOwner(), timelock, "bound timelock");
        assertEq(LibStoxMigrations.applied(safe, id), block.timestamp, "record moment");
        assertEq(LibStoxMigrations.head(safe), id, "line head");

        vm.expectRevert(abi.encodeWithSelector(BindBeaconInitialOwnerUnexpectedLine.selector, id));
        script.callPreflight();
    }

    /// @dev A HyperEVM fork pinned before the bind, with the governance
    /// timelock deployed.
    function onFork(string memory tag) internal returns (BindBeaconInitialOwnerHarness, address) {
        LibTestPreBackfillFork.select(vm, LibStoxDeployNetworks.HYPEREVM);
        BindBeaconInitialOwnerHarness script = new BindBeaconInitialOwnerHarness(tag);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        deployTimelock(safe);
        return (script, safe);
    }

    function executedOnFork(string memory tag) internal returns (BindBeaconInitialOwnerHarness, address) {
        (BindBeaconInitialOwnerHarness script, address safe) = onFork(tag);
        advanceLine(safe, tag);
        approveSafe(safe);
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), script.callAuthorBundle());
        script.callAssertPostState();
        return (script, safe);
    }

    function testPreflightRefusesAnUnapprovedSafe() external {
        (BindBeaconInitialOwnerHarness script, address safe) = onFork("unapproved");
        advanceLine(safe, "unapproved");
        vm.expectRevert(abi.encodeWithSelector(SafeNotBeaconInitialOwnerDelegate.selector, safe));
        script.callPreflight();
    }

    function testPreflightRefusesALineBeforeTheThreshold() external {
        (BindBeaconInitialOwnerHarness script, address safe) = onFork("early");
        bytes32 head = LibStoxMigrations.head(safe);
        approveSafe(safe);
        vm.expectRevert(abi.encodeWithSelector(BindBeaconInitialOwnerUnexpectedLine.selector, head));
        script.callPreflight();
    }

    function testPreflightRefusesALinePastTheThreshold() external {
        (BindBeaconInitialOwnerHarness script, address safe) = onFork("past");
        advanceLine(safe, "past");
        approveSafe(safe);
        vm.prank(safe);
        IMigrationRegistryV5(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .applyMigrationV5(
                safe,
                LibStoxMigrations.NAMESPACE,
                LATER,
                LibStoxMigrations.onto(safe, migrateMultisigThresholdDeclaration().id),
                ""
            );
        vm.expectRevert(abi.encodeWithSelector(BindBeaconInitialOwnerUnexpectedLine.selector, LATER));
        script.callPreflight();
    }

    function testPostStateRefusesAnotherTimelock() external {
        address other = address(0xBEEF);
        (BindBeaconInitialOwnerHarness script,) = executedOnFork("other-timelock");
        vm.warp(block.timestamp + 1);
        vm.prank(LibStoxConfig.ROOT_AUTHORITY);
        CONFIG_REGISTRY.registerV5(
            LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.BEACON_INITIAL_OWNER_NAME, "address", abi.encode(other), ""
        );
        vm.expectRevert(
            abi.encodeWithSelector(BeaconInitialOwnerBindingMismatch.selector, abi.encode(other), block.timestamp)
        );
        script.callAssertPostState();
    }

    function testPostStateRefusesABindingFromAnotherBlock() external {
        (BindBeaconInitialOwnerHarness script,) = executedOnFork("binding-block");
        uint256 boundAt = block.timestamp;
        vm.warp(boundAt + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconInitialOwnerBindingMismatch.selector,
                abi.encode(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK),
                boundAt
            )
        );
        script.callAssertPostState();
    }

    function testPostStateRefusesARecordFromAnotherBlock() external {
        (BindBeaconInitialOwnerHarness script,) = executedOnFork("record-block");
        uint256 recordedAt = block.timestamp;
        vm.warp(recordedAt + 1);
        vm.prank(LibStoxConfig.ROOT_AUTHORITY);
        CONFIG_REGISTRY.registerV5(
            LibStoxConfig.ROOT_AUTHORITY,
            LibStoxConfig.BEACON_INITIAL_OWNER_NAME,
            "address",
            abi.encode(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK),
            ""
        );
        vm.expectRevert(abi.encodeWithSelector(BindBeaconInitialOwnerRecordMismatch.selector, recordedAt));
        script.callAssertPostState();
    }

    function testPostStateRefusesALineThatDoesNotEndAtTheRecord() external {
        (BindBeaconInitialOwnerHarness script, address safe) = executedOnFork("line");
        vm.prank(safe);
        IMigrationRegistryV5(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .applyMigrationV5(
                safe,
                LibStoxMigrations.NAMESPACE,
                LATER,
                LibStoxMigrations.onto(safe, bindBeaconInitialOwnerDeclaration().id),
                ""
            );
        vm.expectRevert(abi.encodeWithSelector(BindBeaconInitialOwnerUnexpectedLine.selector, LATER));
        script.callAssertPostState();
    }

    function testPreflightRefusesAnUnpinnedRegistry() external {
        (BindBeaconInitialOwnerHarness script, address safe) = onFork("unpinned");
        advanceLine(safe, "unpinned");
        approveSafe(safe);
        vm.etch(address(CONFIG_REGISTRY), hex"00");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedConfigRegistryCodeHash.selector,
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(hex"00")
            )
        );
        script.callPreflight();
    }

    function testPostStateRefusesADriftedSafe() external {
        (BindBeaconInitialOwnerHarness script, address safe) = executedOnFork("drifted");
        vm.mockCall(safe, abi.encodeCall(OwnerManager.getThreshold, ()), abi.encode(uint256(4)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeThresholdMismatch.selector, safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD, 4
            )
        );
        script.callAssertPostState();
    }

    function testBindBundleBase() external {
        assertBundle(LibRainDeploy.BASE);
    }

    function testBindBundleEthereum() external {
        assertBundle(LibStoxDeployNetworks.ETHEREUM);
    }

    function testBindBundleHyperEvm() external {
        assertBundle(LibStoxDeployNetworks.HYPEREVM);
    }

    function testBindBundleRobinhood() external {
        assertBundle(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testBindBundleBsc() external {
        assertBundle(LibStoxDeployNetworks.BSC);
    }

    function testPreflightRefusesASafeOffPolicy() external {
        (BindBeaconInitialOwnerHarness script, address safe) = onFork("safe-policy");
        advanceLine(safe, "safe-policy");
        approveSafe(safe);
        vm.mockCall(safe, abi.encodeCall(OwnerManager.getThreshold, ()), abi.encode(uint256(1)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeThresholdMismatch.selector, safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD, 1
            )
        );
        script.callPreflight();
    }

    function testPreflightRefusesATimelockOffState() external {
        (BindBeaconInitialOwnerHarness script, address safe) = onFork("timelock-state");
        advanceLine(safe, "timelock-state");
        approveSafe(safe);
        address timelock = LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK;
        vm.mockCall(timelock, abi.encodeCall(ITimelockControllerState.getMinDelay, ()), abi.encode(uint256(1)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockMinDelayMismatch.selector,
                timelock,
                LibTimelockInvariants.TIMELOCK_MIN_DELAY,
                1
            )
        );
        script.callPreflight();
    }

    function testArtifactNamesTheBundleForItsSigners() external {
        (BindBeaconInitialOwnerHarness script, address safe) = onFork("bundle-name");
        advanceLine(safe, "bundle-name");
        approveSafe(safe);
        script.run();
        assertEq(
            vm.parseJsonString(vm.readFile(script.callArtifactPath()), ".meta.name"),
            "ST0x: bind the beacon initial owner"
        );
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

    function testBundleIsTheBindThenTheRecord() external {
        (BindBeaconInitialOwnerHarness script, address safe) = onFork("bundle");
        SafeTx[] memory txs = script.callAuthorBundle();
        assertEq(txs.length, 2, "bundle length");
        assertEq(txs[0].to, address(CONFIG_REGISTRY), "bind target");
        (address to, bytes memory data) = LibStoxMigrations.recordCall(
            bindBeaconInitialOwnerDeclaration(), safe, LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK
        );
        assertEq(txs[1].to, to, "record target");
        assertEq(txs[1].data, data, "record call");
    }
}


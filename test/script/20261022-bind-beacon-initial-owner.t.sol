// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
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

/// @dev A Safe line write past the bind.
bytes32 constant LATER = keccak256("later");

/// @title BindBeaconInitialOwnerTest
/// @notice The bind on every deployment network at head, with every
/// predecessor on the Safe's line, the root's approval of the Safe and the
/// governance timelock written on the fork where the chain lacks them.
contract BindBeaconInitialOwnerTest is Test {
    IConfigRegistryV5 internal constant CONFIG_REGISTRY =
        IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);

    /// @dev Applies every predecessor on the Safe's line that the chain lacks.
    function advanceLine(address safe, string memory tag) internal {
        if (LibStoxMigrations.applied(safe, LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5) == 0) {
            LibSafeFork.executeBundle(
                vm, Safe(payable(safe)), new BackfillMigrationRegistryV5Harness(tag).callAuthorBundle()
            );
        }
        if (LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) == 0) {
            LibSafeFork.executeBundle(
                vm, Safe(payable(safe)), new OrchestratorAdminToTimelockHarness(tag).callAuthorBundle()
            );
        }
        if (LibStoxMigrations.applied(safe, migrateMultisigThresholdDeclaration().id) == 0) {
            (address to, bytes memory data) = LibStoxMigrations.recordCall(
                migrateMultisigThresholdDeclaration(), safe, LibTimelockInvariants.timelockForChainId(block.chainid)
            );
            LibSafeFork.simulateCall(vm, Safe(payable(safe)), to, data);
        }
    }

    /// @dev The governance timelock, proposed by the Safe, where the chain lacks it.
    function deployTimelock(address safe) internal {
        if (LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK.code.length != 0) return;
        vm.prank(LibStoxConfig.ROOT_AUTHORITY);
        CONFIG_REGISTRY.registerV5(
            LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.GOVERNANCE_SAFE_NAME, "address", abi.encode(safe), ""
        );
        assertEq(
            LibRainDeploy.etchAndDeployZoltu(vm, type(StoxGovernanceTimelock).creationCode),
            LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK,
            "timelock address"
        );
    }

    /// @dev The root approves the Safe where the chain lacks the approval.
    function approveSafe(address safe) internal {
        if (!CONFIG_REGISTRY.approvedV5(LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.BEACON_INITIAL_OWNER_NAME, safe)) {
            vm.prank(LibStoxConfig.ROOT_AUTHORITY);
            CONFIG_REGISTRY.approveV5(LibStoxConfig.BEACON_INITIAL_OWNER_NAME, safe);
        }
    }

    function assertBundle(string memory network) internal {
        vm.createSelectFork(network);
        BindBeaconInitialOwnerHarness script = new BindBeaconInitialOwnerHarness(network);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK;
        bytes32 id = bindBeaconInitialOwnerDeclaration().id;
        deployTimelock(safe);

        if (LibStoxMigrations.applied(safe, id) != 0) {
            console2.log(string.concat("EXECUTED [", network, "]: asserting the binding"));
            assertEq(LibStoxConfig.beaconInitialOwner(), timelock, "bound timelock");
            vm.expectPartialRevert(BindBeaconInitialOwnerUnexpectedLine.selector);
            script.callPreflight();
            return;
        }

        console2.log(string.concat("PENDING [", network, "]: authoring, verifying and executing the bind"));
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

    /// @dev A HyperEVM fork just before the bind, or false once the bind has
    /// executed on chain.
    function readyOnFork(string memory tag)
        internal
        returns (BindBeaconInitialOwnerHarness script, address safe, bool ready)
    {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        script = new BindBeaconInitialOwnerHarness(tag);
        safe = LibSafeInvariants.safeForChainId(block.chainid);
        deployTimelock(safe);
        ready = LibStoxMigrations.applied(safe, bindBeaconInitialOwnerDeclaration().id) == 0;
        if (!ready) console2.log("SPENT: the bind has executed on this chain");
    }

    function executedOnFork(string memory tag)
        internal
        returns (BindBeaconInitialOwnerHarness script, address safe, bool ready)
    {
        (script, safe, ready) = readyOnFork(tag);
        if (!ready) return (script, safe, ready);
        advanceLine(safe, tag);
        approveSafe(safe);
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), script.callAuthorBundle());
        script.callAssertPostState();
    }

    function testPreflightRefusesAnUnapprovedSafe() external {
        (BindBeaconInitialOwnerHarness script, address safe, bool ready) = readyOnFork("unapproved");
        if (!ready) return;
        advanceLine(safe, "unapproved");
        if (CONFIG_REGISTRY.approvedV5(LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.BEACON_INITIAL_OWNER_NAME, safe)) {
            vm.prank(LibStoxConfig.ROOT_AUTHORITY);
            CONFIG_REGISTRY.revokeV5(LibStoxConfig.BEACON_INITIAL_OWNER_NAME, safe);
        }
        vm.expectRevert(abi.encodeWithSelector(SafeNotBeaconInitialOwnerDelegate.selector, safe));
        script.callPreflight();
    }

    function testPreflightRefusesALineBeforeTheThreshold() external {
        (BindBeaconInitialOwnerHarness script, address safe, bool ready) = readyOnFork("early");
        if (!ready) return;
        bytes32 head = LibStoxMigrations.head(safe);
        if (head == migrateMultisigThresholdDeclaration().id) return;
        approveSafe(safe);
        vm.expectRevert(abi.encodeWithSelector(BindBeaconInitialOwnerUnexpectedLine.selector, head));
        script.callPreflight();
    }

    function testPreflightRefusesALinePastTheThreshold() external {
        (BindBeaconInitialOwnerHarness script, address safe, bool ready) = readyOnFork("past");
        if (!ready) return;
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
        (BindBeaconInitialOwnerHarness script,, bool ready) = executedOnFork("other-timelock");
        if (!ready) return;
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
        (BindBeaconInitialOwnerHarness script,, bool ready) = executedOnFork("binding-block");
        if (!ready) return;
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
        (BindBeaconInitialOwnerHarness script,, bool ready) = executedOnFork("record-block");
        if (!ready) return;
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
        (BindBeaconInitialOwnerHarness script, address safe, bool ready) = executedOnFork("line");
        if (!ready) return;
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
        (BindBeaconInitialOwnerHarness script, address safe, bool ready) = readyOnFork("unpinned");
        if (!ready) return;
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
        (BindBeaconInitialOwnerHarness script, address safe, bool ready) = executedOnFork("drifted");
        if (!ready) return;
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
        (BindBeaconInitialOwnerHarness script, address safe, bool ready) = readyOnFork("safe-policy");
        if (!ready) return;
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
        (BindBeaconInitialOwnerHarness script, address safe, bool ready) = readyOnFork("timelock-state");
        if (!ready) return;
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
        (BindBeaconInitialOwnerHarness script, address safe, bool ready) = readyOnFork("bundle-name");
        if (!ready) return;
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
        (BindBeaconInitialOwnerHarness script, address safe,) = readyOnFork("bundle");
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


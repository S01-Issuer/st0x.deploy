// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {OwnerManager} from "safe-global-safe-smart-account-1.4.1-3/contracts/base/OwnerManager.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.30/src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibConfigRegistryDeploy.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";
import {LibSafe} from "rain-deploy-0.1.30/src/lib/LibSafe.sol";
import {LibSafeFork} from "rain-deploy-0.1.30/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.30/src/lib/LibSafeTxBuilderJson.sol";
import {ITimelockControllerState, LibTimelockController} from "rain-deploy-0.1.30/src/lib/LibTimelockController.sol";

import {
    BeaconInitialOwnerBindingMismatch,
    BindBeaconInitialOwner,
    SafeNotBeaconInitialOwnerDelegate,
    bindBeaconInitialOwnerDeclaration
} from "../../script/20261022-bind-beacon-initial-owner.s.sol";
import {BindBeaconInitialOwnerHarness} from "./BindBeaconInitialOwnerHarness.sol";
import {BackfillMigrationRegistryV5Harness} from "./BackfillMigrationRegistryV5Harness.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {
    LibStoxMigrations,
    LineHeadMismatch,
    RecordMismatch,
    SafeNotApprovedWriter,
    UnexpectedMigrationLine
} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTestBeaconInitialOwnerBind} from "../lib/LibTestBeaconInitialOwnerBind.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";

/// @dev A root line record no script declares.
bytes32 constant LATER = keccak256("later");

/// @title BindBeaconInitialOwnerTest
/// @notice The bind on every deployment network at its pinned pre-backfill
/// block, with the V5 backfill bundle executed first, the root's approval of
/// the Safe and the governance timelock written on the fork.
contract BindBeaconInitialOwnerTest is Test {
    IConfigRegistryV5 internal constant CONFIG_REGISTRY =
        IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);

    function executeBackfill(address safe, string memory tag) internal {
        LibSafeFork.executeBundle(
            vm, Safe(payable(safe)), new BackfillMigrationRegistryV5Harness(tag).callAuthorBundle()
        );
    }

    function deployTimelock(address safe) internal {
        assertEq(
            LibTestBeaconInitialOwnerBind.deployTimelock(vm, safe),
            LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK,
            "timelock address"
        );
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
        assertEq(artifactSafe, safe, "artifact Safe");
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);

        assertEq(LibStoxConfig.beaconInitialOwner(), timelock, "bound timelock");
        assertEq(LibStoxMigrations.applied(id), block.timestamp, "record moment");
        assertEq(LibStoxMigrations.head(), id, "line head");

        vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, id));
        script.callPreflight();
    }

    /// @dev A HyperEVM fork pinned before the backfill, with the governance
    /// timelock deployed.
    function onFork(string memory tag) internal returns (BindBeaconInitialOwnerHarness, address) {
        LibTestPreBackfillFork.select(vm, LibStoxDeployNetworks.HYPEREVM);
        BindBeaconInitialOwnerHarness script = new BindBeaconInitialOwnerHarness(tag);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        deployTimelock(safe);
        return (script, safe);
    }

    /// @dev `onFork` with the backfill executed and the Safe approved.
    function readyOnFork(string memory tag) internal returns (BindBeaconInitialOwnerHarness, address) {
        (BindBeaconInitialOwnerHarness script, address safe) = onFork(tag);
        executeBackfill(safe, tag);
        LibTestBeaconInitialOwnerBind.approveSafe(vm, safe);
        return (script, safe);
    }

    function executedOnFork(string memory tag) internal returns (BindBeaconInitialOwnerHarness, address) {
        (BindBeaconInitialOwnerHarness script, address safe) = readyOnFork(tag);
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), script.callAuthorBundle());
        script.callAssertPostState();
        return (script, safe);
    }

    function testDeclarationIsTheBindOntoTheBackfill(uint256 chainId) external {
        ScriptDeclaration memory declared = new BindBeaconInitialOwner().declaration(chainId);
        assertEq(declared.id, LibStoxMigrations.BIND_BEACON_INITIAL_OWNER);
        assertEq(declared.onto, LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5);
        assertFalse(declared.history);
    }

    function testPreflightRefusesASafeTheRootDoesNotApproveAsBinder() external {
        (BindBeaconInitialOwnerHarness script, address safe) = onFork("unapproved");
        executeBackfill(safe, "unapproved");
        vm.expectRevert(abi.encodeWithSelector(SafeNotBeaconInitialOwnerDelegate.selector, safe));
        script.callPreflight();
    }

    function testPreflightRefusesASafeTheRootDoesNotApproveAsWriter() external {
        (BindBeaconInitialOwnerHarness script, address safe) = readyOnFork("unapproved-writer");
        script.callPreflight();
        LibTestRootLine.revoke(vm, safe);
        vm.expectRevert(abi.encodeWithSelector(SafeNotApprovedWriter.selector, safe));
        script.callPreflight();
    }

    function testPreflightRefusesALineBeforeTheBackfill() external {
        (BindBeaconInitialOwnerHarness script, address safe) = onFork("early");
        LibTestBeaconInitialOwnerBind.approveSafe(vm, safe);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, MIGRATION_HEAD_GENESIS));
        script.callPreflight();
    }

    function testPreflightRefusesALinePastTheBackfill() external {
        (BindBeaconInitialOwnerHarness script, address safe) = readyOnFork("past");
        LibTestRootLine.write(vm, safe, LATER, LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, LATER));
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
        vm.expectRevert(
            abi.encodeWithSelector(
                RecordMismatch.selector, LibStoxMigrations.BIND_BEACON_INITIAL_OWNER, block.timestamp, recordedAt
            )
        );
        script.callAssertPostState();
    }

    function testPostStateRefusesALineThatDoesNotEndAtTheRecord() external {
        (BindBeaconInitialOwnerHarness script, address safe) = executedOnFork("line");
        LibTestRootLine.write(vm, safe, LATER, LibStoxMigrations.BIND_BEACON_INITIAL_OWNER);
        vm.expectRevert(abi.encodeWithSelector(LineHeadMismatch.selector, LATER));
        script.callAssertPostState();
    }

    function testPreflightRefusesAnUnpinnedRegistry() external {
        (BindBeaconInitialOwnerHarness script,) = readyOnFork("unpinned");
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
        (BindBeaconInitialOwnerHarness script, address safe) = readyOnFork("safe-policy");
        vm.mockCall(safe, abi.encodeCall(OwnerManager.getThreshold, ()), abi.encode(uint256(1)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeThresholdMismatch.selector, safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD, 1
            )
        );
        script.callPreflight();
    }

    function testPreflightRefusesATimelockOffState() external {
        (BindBeaconInitialOwnerHarness script,) = readyOnFork("timelock-state");
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
        (BindBeaconInitialOwnerHarness script,) = readyOnFork("bundle-name");
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

    function testBundleIsTheBindThenItsRootLineRecord() external {
        (BindBeaconInitialOwnerHarness script,) = onFork("bundle");
        SafeTx[] memory txs = script.callAuthorBundle();
        assertEq(txs.length, 2, "bundle length");
        assertEq(txs[0].to, address(CONFIG_REGISTRY), "bind target");
        (address to, bytes memory data) = LibStoxMigrations.recordCall(bindBeaconInitialOwnerDeclaration());
        assertEq(txs[1].to, to, "record target");
        assertEq(txs[1].value, 0, "record value");
        assertEq(txs[1].data, data, "record call");
        assertEq(uint8(txs[1].operation), uint8(Enum.Operation.Call), "record operation");
    }
}

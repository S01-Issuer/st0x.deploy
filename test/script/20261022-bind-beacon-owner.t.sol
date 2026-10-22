// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {OwnerManager} from "safe-global-safe-smart-account-1.4.1-3/contracts/base/OwnerManager.sol";
import {IConfigRegistryV3} from "rain-deploy-0.1.21/src/interface/IConfigRegistryV3.sol";
import {IMigrationRegistryV3} from "rain-deploy-0.1.21/src/interface/IMigrationRegistryV3.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.21/src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.21/src/lib/LibConfigRegistryDeploy.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.21/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy} from "rain-deploy-0.1.21/src/lib/LibRainDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.21/src/lib/LibSafeTx.sol";
import {LibSafe} from "rain-deploy-0.1.21/src/lib/LibSafe.sol";
import {LibSafeFork} from "rain-deploy-0.1.21/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.21/src/lib/LibSafeTxBuilderJson.sol";

import {
    BeaconOwnerBindingMismatch,
    BindBeaconOwnerRecordMismatch,
    BindBeaconOwnerUnexpectedLine,
    SafeNotBeaconOwnerDelegate,
    bindBeaconOwnerDeclaration
} from "../../script/20261022-bind-beacon-owner.s.sol";
import {backfillHistoryDeclaration} from "../../script/20261017-backfill-history.s.sol";
import {backfillMigrationRegistryV3Declaration} from "../../script/20261022-backfill-migration-registry-v3.s.sol";
import {migrateMultisigThresholdDeclaration} from "../../script/20260619-migrate-multisig-threshold.s.sol";
import {BackfillHistoryHarness} from "./BackfillHistoryHarness.sol";
import {BackfillMigrationRegistryV3Harness} from "./BackfillMigrationRegistryV3Harness.sol";
import {BindBeaconOwnerHarness} from "./BindBeaconOwnerHarness.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @notice The beacon owner bind is not on this chain. Execute the bundle.
/// @param network The chain still pending.
error BindBeaconOwnerNotApplied(string network);

/// @dev A Safe line write past the bind.
bytes32 constant LATER = keccak256("later");

/// @title BindBeaconOwnerTest
/// @notice The bind on every deployment network at head, with every
/// predecessor on the Safe's line and the root's approval of the Safe written
/// on the fork where the chain lacks them. The requirement: the bind's record
/// is on chain, red until it is.
contract BindBeaconOwnerTest is Test {
    IConfigRegistryV3 internal constant CONFIG_REGISTRY =
        IConfigRegistryV3(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);

    /// @dev Applies every predecessor on the Safe's line that the chain lacks.
    function advanceLine(address safe, string memory tag) internal {
        if (LibStoxMigrations.applied(safe, backfillMigrationRegistryV3Declaration().id) == 0) {
            LibSafeFork.executeBundle(
                vm, Safe(payable(safe)), new BackfillMigrationRegistryV3Harness(tag).callAuthorBundle()
            );
        }
        if (LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) == 0) {
            LibSafeFork.executeBundle(
                vm, Safe(payable(safe)), new OrchestratorAdminToTimelockHarness(tag).callAuthorBundle()
            );
        }
        if (LibStoxMigrations.applied(safe, backfillHistoryDeclaration().id) == 0) {
            LibSafeFork.executeBundle(vm, Safe(payable(safe)), new BackfillHistoryHarness(tag).callAuthorBundle());
        }
        if (LibStoxMigrations.applied(safe, migrateMultisigThresholdDeclaration().id) == 0) {
            (address to, bytes memory data) = LibStoxMigrations.recordCall(
                migrateMultisigThresholdDeclaration(), safe, LibTimelockInvariants.timelockForChainId(block.chainid)
            );
            LibSafeFork.simulateCall(vm, Safe(payable(safe)), to, data);
        }
    }

    /// @dev The root approves the Safe where the chain lacks the approval.
    function approveSafe(address safe) internal {
        if (!CONFIG_REGISTRY.approvedV3(LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.BEACON_OWNER, safe)) {
            vm.prank(LibStoxConfig.ROOT_AUTHORITY);
            CONFIG_REGISTRY.approveV3(LibStoxConfig.BEACON_OWNER, safe);
        }
    }

    function assertBundle(string memory network) internal {
        vm.createSelectFork(network);
        BindBeaconOwnerHarness script = new BindBeaconOwnerHarness(network);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        bytes32 id = bindBeaconOwnerDeclaration().id;

        if (LibStoxMigrations.applied(safe, id) != 0) {
            console2.log(string.concat("EXECUTED [", network, "]: asserting the binding"));
            assertEq(LibStoxConfig.beaconOwner(), timelock, "bound owner");
            vm.expectPartialRevert(BindBeaconOwnerUnexpectedLine.selector);
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

        assertEq(LibStoxConfig.beaconOwner(), timelock, "bound owner");
        assertEq(LibStoxMigrations.applied(safe, id), block.timestamp, "record moment");
        assertEq(LibStoxMigrations.head(safe), id, "line head");

        vm.expectRevert(abi.encodeWithSelector(BindBeaconOwnerUnexpectedLine.selector, id));
        script.callPreflight();
    }

    function assertApplied(string memory network) internal {
        vm.createSelectFork(network);
        if (
            LibStoxMigrations.applied(LibSafeInvariants.safeForChainId(block.chainid), bindBeaconOwnerDeclaration().id)
                == 0
        ) {
            revert BindBeaconOwnerNotApplied(network);
        }
    }

    /// @dev A HyperEVM fork just before the bind, or false once the bind has
    /// executed on chain.
    function readyOnFork(string memory tag) internal returns (BindBeaconOwnerHarness script, address safe, bool ready) {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        script = new BindBeaconOwnerHarness(tag);
        safe = LibSafeInvariants.safeForChainId(block.chainid);
        ready = LibStoxMigrations.applied(safe, bindBeaconOwnerDeclaration().id) == 0;
        if (!ready) console2.log("SPENT: the bind has executed on this chain");
    }

    function executedOnFork(string memory tag)
        internal
        returns (BindBeaconOwnerHarness script, address safe, bool ready)
    {
        (script, safe, ready) = readyOnFork(tag);
        if (!ready) return (script, safe, ready);
        advanceLine(safe, tag);
        approveSafe(safe);
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), script.callAuthorBundle());
        script.callAssertPostState();
    }

    function testPreflightRefusesAnUnapprovedSafe() external {
        (BindBeaconOwnerHarness script, address safe, bool ready) = readyOnFork("unapproved");
        if (!ready) return;
        advanceLine(safe, "unapproved");
        if (CONFIG_REGISTRY.approvedV3(LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.BEACON_OWNER, safe)) {
            vm.prank(LibStoxConfig.ROOT_AUTHORITY);
            CONFIG_REGISTRY.revokeV3(LibStoxConfig.BEACON_OWNER, safe);
        }
        vm.expectRevert(abi.encodeWithSelector(SafeNotBeaconOwnerDelegate.selector, safe));
        script.callPreflight();
    }

    function testPreflightRefusesALineBeforeTheThreshold() external {
        (BindBeaconOwnerHarness script, address safe, bool ready) = readyOnFork("early");
        if (!ready) return;
        bytes32 head = LibStoxMigrations.head(safe);
        if (head == migrateMultisigThresholdDeclaration().id) return;
        approveSafe(safe);
        vm.expectRevert(abi.encodeWithSelector(BindBeaconOwnerUnexpectedLine.selector, head));
        script.callPreflight();
    }

    function testPreflightRefusesALinePastTheThreshold() external {
        (BindBeaconOwnerHarness script, address safe, bool ready) = readyOnFork("past");
        if (!ready) return;
        advanceLine(safe, "past");
        approveSafe(safe);
        vm.prank(safe);
        IMigrationRegistryV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .applyMigrationV3(
                safe,
                LibStoxMigrations.NAMESPACE,
                LATER,
                LibStoxMigrations.onto(safe, migrateMultisigThresholdDeclaration().id)
            );
        vm.expectRevert(abi.encodeWithSelector(BindBeaconOwnerUnexpectedLine.selector, LATER));
        script.callPreflight();
    }

    function testPostStateRefusesAnotherOwner() external {
        address other = address(0xBEEF);
        (BindBeaconOwnerHarness script,, bool ready) = executedOnFork("other-owner");
        if (!ready) return;
        vm.warp(block.timestamp + 1);
        vm.prank(LibStoxConfig.ROOT_AUTHORITY);
        CONFIG_REGISTRY.registerV3(LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.BEACON_OWNER, abi.encode(other));
        vm.expectRevert(abi.encodeWithSelector(BeaconOwnerBindingMismatch.selector, abi.encode(other), block.timestamp));
        script.callAssertPostState();
    }

    function testPostStateRefusesABindingFromAnotherBlock() external {
        (BindBeaconOwnerHarness script,, bool ready) = executedOnFork("binding-block");
        if (!ready) return;
        uint256 boundAt = block.timestamp;
        vm.warp(boundAt + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconOwnerBindingMismatch.selector,
                abi.encode(LibTimelockInvariants.timelockForChainId(block.chainid)),
                boundAt
            )
        );
        script.callAssertPostState();
    }

    function testPostStateRefusesARecordFromAnotherBlock() external {
        (BindBeaconOwnerHarness script,, bool ready) = executedOnFork("record-block");
        if (!ready) return;
        uint256 recordedAt = block.timestamp;
        vm.warp(recordedAt + 1);
        vm.prank(LibStoxConfig.ROOT_AUTHORITY);
        CONFIG_REGISTRY.registerV3(
            LibStoxConfig.ROOT_AUTHORITY,
            LibStoxConfig.BEACON_OWNER,
            abi.encode(LibTimelockInvariants.timelockForChainId(block.chainid))
        );
        vm.expectRevert(abi.encodeWithSelector(BindBeaconOwnerRecordMismatch.selector, recordedAt));
        script.callAssertPostState();
    }

    function testPostStateRefusesALineThatDoesNotEndAtTheRecord() external {
        (BindBeaconOwnerHarness script, address safe, bool ready) = executedOnFork("line");
        if (!ready) return;
        vm.prank(safe);
        IMigrationRegistryV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .applyMigrationV3(
                safe, LibStoxMigrations.NAMESPACE, LATER, LibStoxMigrations.onto(safe, bindBeaconOwnerDeclaration().id)
            );
        vm.expectRevert(abi.encodeWithSelector(BindBeaconOwnerUnexpectedLine.selector, LATER));
        script.callAssertPostState();
    }

    function testPreflightRefusesAnUnpinnedRegistry() external {
        (BindBeaconOwnerHarness script, address safe, bool ready) = readyOnFork("unpinned");
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
        (BindBeaconOwnerHarness script, address safe, bool ready) = executedOnFork("drifted");
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

    function testBindAppliedBase() external {
        assertApplied(LibRainDeploy.BASE);
    }

    function testBindAppliedEthereum() external {
        assertApplied(LibStoxDeployNetworks.ETHEREUM);
    }

    function testBindAppliedHyperEvm() external {
        assertApplied(LibStoxDeployNetworks.HYPEREVM);
    }

    function testBindAppliedRobinhood() external {
        assertApplied(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testBindAppliedBsc() external {
        assertApplied(LibStoxDeployNetworks.BSC);
    }
}


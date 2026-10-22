// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibRainDeploy} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {OwnerManager} from "safe-global-safe-smart-account-1.4.1-3/contracts/base/OwnerManager.sol";
import {IMigrationRegistryV2} from "rain-deploy-0.1.18/src/interface/IMigrationRegistryV2.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.18/src/lib/LibMigrationRegistryDeploy.sol";
import {LibSafe} from "rain-deploy-0.1.18/src/lib/LibSafe.sol";
import {SafeTx} from "rain-deploy-0.1.18/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.18/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.18/src/lib/LibSafeTxBuilderJson.sol";

import {
    LineHeadMismatch,
    RecordMismatch,
    UnexpectedMigrationLine,
    backfillHistoryDeclaration,
    backfilledDeclarations
} from "../../script/20261017-backfill-history.s.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {BackfillHistoryHarness} from "./BackfillHistoryHarness.sol";
import {GrantOrchestratorEmergencyHarness} from "./GrantOrchestratorEmergencyHarness.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";

/// @notice The backfill's record is not on this chain. Execute the bundle.
/// @param network The chain still pending.
error BackfillNotApplied(string network);

/// @dev A Safe line write past the backfill, for the post-state refusal.
bytes32 constant LATER = keccak256("later");

/// @title BackfillHistoryTest
/// @notice The backfill on every deployment network at head. Before the
/// orchestrator admin move the script refuses; with the move executed (live,
/// or its bundles executed on the fork) `run()` executes the backfill through
/// the Safe, `verify` accepts the artifact, and the artifact executed by the
/// owners writes every record in line order and makes a re-dispatch refuse.
/// The requirement: the backfill's record is on chain, red until it is.
contract BackfillHistoryTest is Test {
    function assertBundle(string memory network) internal {
        vm.createSelectFork(network);
        BackfillHistoryHarness script = new BackfillHistoryHarness(network);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        bytes32 id = backfillHistoryDeclaration().id;

        if (LibStoxMigrations.applied(safe, id) != 0) {
            console2.log(string.concat("EXECUTED [", network, "]: asserting the records"));
            // Selector only: a later recorded migration moves the head.
            vm.expectPartialRevert(UnexpectedMigrationLine.selector);
            script.callPreflight();
            return;
        }

        if (LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) == 0) {
            console2.log(string.concat("PENDING [", network, "]: admin move not executed; backfill refused"));
            vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, LibStoxMigrations.head(safe)));
            script.callPreflight();
            if (LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_EMERGENCY) == 0) {
                LibSafeFork.executeBundle(
                    vm, Safe(payable(safe)), new GrantOrchestratorEmergencyHarness("backfill").callAuthorBundle()
                );
            }
            LibSafeFork.executeBundle(
                vm, Safe(payable(safe)), new OrchestratorAdminToTimelockHarness("backfill").callAuthorBundle()
            );
        }

        console2.log(string.concat("PENDING [", network, "]: authoring, verifying and executing the backfill"));
        uint256 preRun = vm.snapshotState();
        script.run();
        vm.revertToState(preRun);

        string memory artifactPath = script.callArtifactPath();
        script.verify(artifactPath);

        // The artifact a signer loads, executed by the owners as the Safe UI
        // executes it, not the bundle re-derived in memory.
        (, address artifactSafe, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, vm.readFile(artifactPath));
        assertEq(artifactSafe, safe, "artifact Safe");
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);

        ScriptDeclaration[] memory declarations = backfilledDeclarations();
        bytes32 previous = LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK;
        for (uint256 i = 0; i < declarations.length; i++) {
            assertEq(LibStoxMigrations.applied(safe, declarations[i].id), block.timestamp, "record moment");
            assertEq(declarations[i].prerequisites[0].migration, previous, "line order");
            previous = declarations[i].id;
        }
        assertEq(LibStoxMigrations.head(safe), id);

        vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, id));
        script.callPreflight();
    }

    function assertApplied(string memory network) internal {
        vm.createSelectFork(network);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        if (LibStoxMigrations.applied(safe, backfillHistoryDeclaration().id) == 0) {
            revert BackfillNotApplied(network);
        }
    }

    /// @dev The backfill executed on a HyperEVM fork, or false once it has
    /// executed on chain and the pre-backfill state is gone.
    function executedOnFork() internal returns (BackfillHistoryHarness script, address safe, bool ready) {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        script = new BackfillHistoryHarness("refusal");
        safe = LibSafeInvariants.safeForChainId(block.chainid);
        ready = LibStoxMigrations.applied(safe, backfillHistoryDeclaration().id) == 0;
        if (!ready) {
            console2.log("SPENT: the backfill has executed on this chain");
            return (script, safe, ready);
        }
        if (LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_EMERGENCY) == 0) {
            LibSafeFork.executeBundle(
                vm, Safe(payable(safe)), new GrantOrchestratorEmergencyHarness("refusal").callAuthorBundle()
            );
        }
        if (LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) == 0) {
            LibSafeFork.executeBundle(
                vm, Safe(payable(safe)), new OrchestratorAdminToTimelockHarness("refusal").callAuthorBundle()
            );
        }
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), script.callAuthorBundle());
        script.callAssertPostState();
        return (script, safe, ready);
    }

    /// @notice Post-state refuses records from another block, naming the
    /// first.
    function testPostStateRefusesARecordFromAnotherBlock() external {
        (BackfillHistoryHarness script,, bool ready) = executedOnFork();
        if (!ready) return;
        uint256 recordedAt = block.timestamp;
        vm.warp(recordedAt + 1);
        vm.expectRevert(
            abi.encodeWithSelector(RecordMismatch.selector, backfilledDeclarations()[0].id, recordedAt + 1, recordedAt)
        );
        script.callAssertPostState();
    }

    /// @notice Post-state refuses a line that has moved past the backfill.
    function testPostStateRefusesALineThatDoesNotEndAtTheRecord() external {
        (BackfillHistoryHarness script, address safe, bool ready) = executedOnFork();
        if (!ready) return;
        vm.prank(safe);
        IMigrationRegistryV2(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .applyMigration(
                LibStoxMigrations.NAMESPACE, LATER, LibStoxMigrations.onto(safe, backfillHistoryDeclaration().id)
            );
        vm.expectRevert(abi.encodeWithSelector(LineHeadMismatch.selector, LATER));
        script.callAssertPostState();
    }

    /// @notice Post-state refuses a Safe out of its token-owner policy.
    function testPostStateRefusesASafeOutOfPolicy() external {
        (BackfillHistoryHarness script, address safe, bool ready) = executedOnFork();
        if (!ready) return;
        uint256 threshold = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD + 1;
        LibSafeFork.simulateCall(
            vm, Safe(payable(safe)), safe, abi.encodeCall(OwnerManager.changeThreshold, (threshold))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeThresholdMismatch.selector,
                safe,
                LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD,
                threshold
            )
        );
        script.callAssertPostState();
    }

    function testBackfillBundleBase() external {
        assertBundle(LibRainDeploy.BASE);
    }

    function testBackfillBundleEthereum() external {
        assertBundle(LibStoxDeployNetworks.ETHEREUM);
    }

    function testBackfillBundleHyperEvm() external {
        assertBundle(LibStoxDeployNetworks.HYPEREVM);
    }

    function testBackfillBundleRobinhood() external {
        assertBundle(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testBackfillBundleBsc() external {
        assertBundle(LibStoxDeployNetworks.BSC);
    }

    function testBackfillAppliedBase() external {
        assertApplied(LibRainDeploy.BASE);
    }

    function testBackfillAppliedEthereum() external {
        assertApplied(LibStoxDeployNetworks.ETHEREUM);
    }

    function testBackfillAppliedHyperEvm() external {
        assertApplied(LibStoxDeployNetworks.HYPEREVM);
    }

    function testBackfillAppliedRobinhood() external {
        assertApplied(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testBackfillAppliedBsc() external {
        assertApplied(LibStoxDeployNetworks.BSC);
    }
}

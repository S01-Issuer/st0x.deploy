// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibRainDeploy} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {IMigrationRegistryV5} from "rain-deploy-0.1.29/src/interface/IMigrationRegistryV5.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.29/src/lib/LibMigrationRegistryDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.29/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.29/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.29/src/lib/LibSafeTxBuilderJson.sol";

import {UnexpectedMigrationLine} from "../../script/20261006-orchestrator-admin-to-timelock.s.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {BackfillMigrationRegistryV5Harness} from "./BackfillMigrationRegistryV5Harness.sol";
import {ST0xOrchestrator} from "../../src/concrete/ST0xOrchestrator.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @title OrchestratorAdminToTimelockTest
/// @notice The admin move on every deployment network at head. The bundle
/// walks the line: before the V5 backfill the script refuses and the bundle
/// cannot execute; with the backfill executed (live, or its bundle executed
/// on the fork) `run()` executes the move
/// through the Safe, proves it and writes the artifact, `verify` accepts
/// that artifact, and the artifact executed by the owners leaves the state
/// the invariants demand and makes a re-dispatch refuse; once executed on
/// chain, the chain must be in that state.
contract OrchestratorAdminToTimelockTest is Test {
    ST0xOrchestrator internal constant ORCHESTRATOR =
        ST0xOrchestrator(payable(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE));

    function executeBackfill(address safe) internal {
        BackfillMigrationRegistryV5Harness backfill = new BackfillMigrationRegistryV5Harness("admin-move-prerequisite");
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), backfill.callAuthorBundle());
    }

    function assertBundle(string memory network) internal {
        vm.createSelectFork(network);
        OrchestratorAdminToTimelockHarness script = new OrchestratorAdminToTimelockHarness(network);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);

        if (LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) != 0) {
            console2.log(string.concat("EXECUTED [", network, "]: asserting the post-move state"));
            LibOrchestratorInvariants.assertInstance();
            assertTrue(ORCHESTRATOR.hasRole(bytes32(0), timelock));
            // Selector only: a later recorded migration moves the head.
            vm.expectPartialRevert(UnexpectedMigrationLine.selector);
            script.callPreflight();
            return;
        }

        if (LibStoxMigrations.applied(safe, LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5) == 0) {
            console2.log(string.concat("PENDING [", network, "]: V5 backfill not executed; move refused"));
            vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, LibStoxMigrations.head(safe)));
            script.callPreflight();
            // Out of order on chain (the move signed at a lower nonce than
            // the grant, or imported where the grant is still queued): the
            // registry refuses the record, so the whole bundle reverts. The
            // Safe reports any inner failure as GS013, so the refuser is
            // pinned by calling the record directly as the Safe.
            SafeTx[] memory early = script.callAuthorBundle();
            vm.expectRevert(bytes("GS013"));
            this.externalExecute(safe, early);
            vm.prank(safe);
            vm.expectPartialRevert(IMigrationRegistryV5.UnexpectedMigrationHead.selector);
            IMigrationRegistryV5(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
                .applyMigrationV5(
                    safe,
                    LibStoxMigrations.NAMESPACE,
                    LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK,
                    LibStoxMigrations.onto(safe, LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5),
                    ""
                );
            executeBackfill(safe);
        }

        console2.log(string.concat("PENDING [", network, "]: authoring, verifying and executing the move"));
        uint256 preRun = vm.snapshotState();
        uint256 runAt = block.timestamp;
        script.run();
        // The governance proof runs on a snapshot, so the fork is left in the
        // post-move state the invariants demand, at the time `run()` started,
        // and the artifact is dated then rather than after the proof's warp.
        LibOrchestratorInvariants.assertInstance();
        assertEq(block.timestamp, runAt, "the governance proof's warp leaked");
        assertEq(
            vm.parseJsonUint(vm.readFile(script.callArtifactPath()), ".createdAt"),
            runAt * 1000,
            "artifact dated after the governance proof's warp"
        );
        vm.revertToState(preRun);

        string memory artifactPath = script.callArtifactPath();
        script.verify(artifactPath);

        // The artifact a signer loads, executed by the owners as the Safe UI
        // executes it, not the bundle re-derived in memory.
        (, address artifactSafe, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, vm.readFile(artifactPath));
        assertEq(artifactSafe, safe, "artifact Safe");
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);

        assertTrue(ORCHESTRATOR.hasRole(bytes32(0), timelock), "exec: timelock admin");
        assertFalse(ORCHESTRATOR.hasRole(bytes32(0), safe), "exec: Safe admin");
        assertTrue(ORCHESTRATOR.hasRole(ORCHESTRATOR.EMERGENCY_ROLE(), safe), "exec: Safe EMERGENCY");
        assertEq(LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK), block.timestamp);
        assertEq(LibStoxMigrations.head(safe), LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK);
        LibOrchestratorInvariants.assertInstance();

        // The Safe can no longer grant directly.
        bytes32 mintRole = ORCHESTRATOR.MINT_ROLE();
        vm.prank(safe);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, safe, bytes32(0))
        );
        ORCHESTRATOR.grantRole(mintRole, safe);

        vm.expectRevert(
            abi.encodeWithSelector(UnexpectedMigrationLine.selector, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK)
        );
        script.callPreflight();
    }

    function testMoveBundleBase() external {
        assertBundle(LibRainDeploy.BASE);
    }

    function testMoveBundleEthereum() external {
        assertBundle(LibStoxDeployNetworks.ETHEREUM);
    }

    function testMoveBundleHyperEvm() external {
        assertBundle(LibStoxDeployNetworks.HYPEREVM);
    }

    function testMoveBundleRobinhood() external {
        assertBundle(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testMoveBundleBsc() external {
        assertBundle(LibStoxDeployNetworks.BSC);
    }

    /// @notice `verify` refuses an artifact that hands admin to an address
    /// other than the chain's timelock.
    /// @dev Needs the pre-move state: once the move has executed on Base
    /// this reports SPENT and stops asserting.
    function testVerifyRefusesTamperedArtifact() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        if (LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) != 0) {
            console2.log("SPENT: the admin move has executed on this chain");
            return;
        }
        if (LibStoxMigrations.applied(safe, LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5) == 0) {
            executeBackfill(safe);
        }
        OrchestratorAdminToTimelockHarness script = new OrchestratorAdminToTimelockHarness("tamper");
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        // Built in memory and written to its own paths, so this test never
        // reads the artifact `run()` writes for the other tests.
        string memory json =
            LibSafeTxBuilderJson.toJson(vm, safe, block.chainid, "tamper test", script.callAuthorBundle());
        string memory cleanPath =
            string.concat("out/20261006-orchestrator-admin-to-timelock-clean-", vm.toString(block.chainid), ".json");
        vm.writeFile(cleanPath, json);
        // Control: the untampered artifact verifies, so the refusal below is
        // the tamper's doing.
        script.verify(cleanPath);
        string memory timelockHex = vm.replace(vm.toLowercase(vm.toString(timelock)), "0x", "");
        string memory tampered = vm.replace(json, timelockHex, "000000000000000000000000000000000000dead");
        assertTrue(keccak256(bytes(tampered)) != keccak256(bytes(json)), "tamper did not apply");
        string memory tamperedPath =
            string.concat("out/20261006-orchestrator-admin-to-timelock-tampered-", vm.toString(block.chainid), ".json");
        vm.writeFile(tamperedPath, tampered);
        vm.expectRevert(abi.encodeWithSelector(LibSafeTxBuilderJson.ArtifactMismatch.selector, "data"));
        script.verify(tamperedPath);
    }

    /// @notice External shim: execute a bundle through the Safe so
    /// `vm.expectRevert` can observe the revert.
    function externalExecute(address safe, SafeTx[] memory txs) external {
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibRainDeploy} from "rain-deploy-0.1.22/src/lib/LibRainDeploy.sol";
import {IRegistryDelegatesV1} from "rain-deploy-0.1.22/src/interface/IRegistryDelegatesV1.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.22/src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.22/src/lib/LibMigrationRegistryDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.22/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.22/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.22/src/lib/LibSafeTxBuilderJson.sol";

import {
    EmergencyNotGranted,
    LineHeadMismatch,
    RecordMismatch,
    SafeNotApprovedWriter,
    UnexpectedMigrationLine
} from "../../script/20261006-orchestrator-admin-to-timelock.s.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {ST0xOrchestrator} from "../../src/concrete/ST0xOrchestrator.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @title OrchestratorAdminToTimelockTest
/// @notice The admin move on every deployment network at head, the first
/// record of the root line. With the Safe approved as a writer of that line
/// (live, or approved on the fork) `run()` executes the move
/// through the Safe, proves it and writes the artifact, `verify` accepts
/// that artifact, and the artifact executed by the owners leaves the state
/// the invariants demand and makes a re-dispatch refuse; once executed on
/// chain, the chain must be in that state.
contract OrchestratorAdminToTimelockTest is Test {
    ST0xOrchestrator internal constant ORCHESTRATOR =
        ST0xOrchestrator(payable(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE));

    /// @notice The root authority's approval of `safe` as a writer of this
    /// repo's line, on the fork, where the chain does not carry it yet.
    /// @param safe The chain's Safe.
    function approveSafe(address safe) internal {
        if (!LibStoxMigrations.approved(safe)) {
            vm.prank(LibStoxMigrations.WRITER);
            IRegistryDelegatesV1(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
                .approveV3(LibStoxMigrations.NAMESPACE, safe);
        }
    }

    function assertBundle(string memory network) internal {
        vm.createSelectFork(network);
        OrchestratorAdminToTimelockHarness script = new OrchestratorAdminToTimelockHarness(network);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);

        if (LibStoxMigrations.applied(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) != 0) {
            console2.log(string.concat("EXECUTED [", network, "]: asserting the post-move state"));
            LibOrchestratorInvariants.assertInstance(safe);
            assertTrue(ORCHESTRATOR.hasRole(bytes32(0), timelock));
            // Selector only: a later recorded migration moves the head.
            vm.expectPartialRevert(UnexpectedMigrationLine.selector);
            script.callPreflight();
            return;
        }

        approveSafe(safe);

        console2.log(string.concat("PENDING [", network, "]: authoring, verifying and executing the move"));
        uint256 preRun = vm.snapshotState();
        uint256 runAt = block.timestamp;
        script.run();
        // The governance proof runs on a snapshot, so the fork is left in the
        // post-move state the invariants demand, at the time `run()` started,
        // and the artifact is dated then rather than after the proof's warp.
        LibOrchestratorInvariants.assertInstance(safe);
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
        assertEq(LibStoxMigrations.applied(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK), block.timestamp);
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK);
        LibOrchestratorInvariants.assertInstance(safe);

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
        if (LibStoxMigrations.applied(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) != 0) {
            console2.log("SPENT: the admin move has executed on this chain");
            return;
        }
        approveSafe(safe);
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

    /// @notice The script refuses a Safe the root authority has not approved
    /// to write its line: the bundle's record would revert.
    function testRefusesAnUnapprovedSafe() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        if (LibStoxMigrations.applied(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) != 0) {
            console2.log("SPENT: the admin move has executed on this chain");
            return;
        }
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        if (LibStoxMigrations.approved(safe)) {
            vm.prank(LibStoxMigrations.WRITER);
            IRegistryDelegatesV1(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
                .revokeV3(LibStoxMigrations.NAMESPACE, safe);
        }
        OrchestratorAdminToTimelockHarness script = new OrchestratorAdminToTimelockHarness("unapproved");
        vm.expectRevert(abi.encodeWithSelector(SafeNotApprovedWriter.selector, safe));
        script.callPreflight();
    }

    /// @notice The script refuses to move admin off a Safe that does not hold
    /// EMERGENCY: the move would leave it unable to pause.
    function testRefusesASafeWithoutEmergency() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        if (LibStoxMigrations.applied(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) != 0) {
            console2.log("SPENT: the admin move has executed on this chain");
            return;
        }
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        approveSafe(safe);
        OrchestratorAdminToTimelockHarness script = new OrchestratorAdminToTimelockHarness("no-emergency");
        // Control: the approved Safe holding EMERGENCY passes.
        script.callPreflight();
        bytes32 emergency = ORCHESTRATOR.EMERGENCY_ROLE();
        vm.prank(safe);
        ORCHESTRATOR.renounceRole(emergency, safe);
        vm.expectRevert(abi.encodeWithSelector(EmergencyNotGranted.selector));
        script.callPreflight();
    }

    /// @notice Executes the move on a Base fork where it has not run yet.
    /// @return script The harness, for its post-state check.
    /// @return executed False when the move already ran on the chain.
    function executedMove() internal returns (OrchestratorAdminToTimelockHarness script, bool executed) {
        vm.createSelectFork(LibRainDeploy.BASE);
        if (LibStoxMigrations.applied(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) != 0) {
            console2.log("SPENT: the admin move has executed on this chain");
            return (script, false);
        }
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        approveSafe(safe);
        script = new OrchestratorAdminToTimelockHarness("post-state");
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), script.callAuthorBundle());
        // Control: the move's own state passes.
        script.callAssertPostState();
        return (script, true);
    }

    /// @notice The post-state check refuses a line whose head is not the
    /// admin move.
    function testPostStateRefusesAnotherHead() external {
        (OrchestratorAdminToTimelockHarness script, bool executed) = executedMove();
        if (!executed) return;
        bytes32 next = keccak256("script/next.s.sol");
        (address registry, bytes memory data) = LibMigrationRegistry.applyMigrationV3Call(
            LibStoxMigrations.WRITER,
            LibStoxMigrations.NAMESPACE,
            next,
            LibStoxMigrations.onto(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK)
        );
        vm.prank(LibStoxMigrations.WRITER);
        (bool ok,) = registry.call(data);
        assertTrue(ok, "next record");
        vm.expectRevert(abi.encodeWithSelector(LineHeadMismatch.selector, next));
        script.callAssertPostState();
    }

    /// @notice The post-state check refuses a record stamped in another
    /// block.
    function testPostStateRefusesARecordFromAnotherBlock() external {
        (OrchestratorAdminToTimelockHarness script, bool executed) = executedMove();
        if (!executed) return;
        uint256 recordedAt = block.timestamp;
        vm.warp(recordedAt + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                RecordMismatch.selector, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK, recordedAt + 1, recordedAt
            )
        );
        script.callAssertPostState();
    }

    /// @notice External shim: execute a bundle through the Safe so
    /// `vm.expectRevert` can observe the revert.
    function externalExecute(address safe, SafeTx[] memory txs) external {
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);
    }
}

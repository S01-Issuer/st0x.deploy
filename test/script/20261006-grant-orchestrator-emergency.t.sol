// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibRainDeploy} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {IMigrationRegistryV2, MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.18/src/interface/IMigrationRegistryV2.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.18/src/lib/LibMigrationRegistryDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.18/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.18/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.18/src/lib/LibSafeTxBuilderJson.sol";

import {
    EmergencyAlreadyGranted,
    EmergencyNotRevoked,
    UnexpectedMigrationLine
} from "../../script/20261006-grant-orchestrator-emergency.s.sol";
import {GrantOrchestratorEmergencyHarness} from "./GrantOrchestratorEmergencyHarness.sol";
import {ST0xOrchestrator} from "../../src/concrete/ST0xOrchestrator.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";

/// @title GrantOrchestratorEmergencyTest
/// @notice The grant on every deployment network at head: while the chain
/// has not executed it, `run()` executes it through the Safe, proves it and
/// writes the artifact, `verify` accepts that artifact, and the artifact
/// executed by the owners leaves the state the invariants demand and makes a
/// re-dispatch refuse; once executed, the chain must be in that state and the
/// script must refuse.
contract GrantOrchestratorEmergencyTest is Test {
    ST0xOrchestrator internal constant ORCHESTRATOR =
        ST0xOrchestrator(payable(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE));

    function assertBundle(string memory network) internal {
        vm.createSelectFork(network);
        GrantOrchestratorEmergencyHarness script = new GrantOrchestratorEmergencyHarness(network);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);

        if (LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_EMERGENCY) != 0) {
            console2.log(string.concat("EXECUTED [", network, "]: asserting the post-grant state"));
            LibOrchestratorInvariants.assertInstance(safe);
            assertTrue(ORCHESTRATOR.hasRole(ORCHESTRATOR.EMERGENCY_ROLE(), safe));
            (uint256 timelockMigratedAt,) = LibStoxMigrations.governanceTimelockExecution(block.chainid);
            assertEq(LibStoxMigrations.applied(safe, LibStoxMigrations.GOVERNANCE_TIMELOCK), timelockMigratedAt);
            vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, LibStoxMigrations.head(safe)));
            script.callPreflight();
            return;
        }

        console2.log(string.concat("PENDING [", network, "]: authoring, verifying and executing the bundle"));
        uint256 preRun = vm.snapshotState();
        script.run();
        assertTrue(ORCHESTRATOR.hasRole(ORCHESTRATOR.EMERGENCY_ROLE(), safe), "run: EMERGENCY");
        vm.revertToState(preRun);

        string memory artifactPath = script.callArtifactPath();
        script.verify(artifactPath);

        // The artifact a signer loads, executed by the owners as the Safe UI
        // executes it, not the bundle re-derived in memory.
        (, address artifactSafe, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, vm.readFile(artifactPath));
        assertEq(artifactSafe, safe, "artifact Safe");
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);

        assertTrue(ORCHESTRATOR.hasRole(ORCHESTRATOR.EMERGENCY_ROLE(), safe), "exec: EMERGENCY");
        assertEq(LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_EMERGENCY), block.timestamp);
        (uint256 executedAt,) = LibStoxMigrations.governanceTimelockExecution(block.chainid);
        assertEq(LibStoxMigrations.applied(safe, LibStoxMigrations.GOVERNANCE_TIMELOCK), executedAt);
        assertEq(LibStoxMigrations.head(safe), LibStoxMigrations.ORCHESTRATOR_EMERGENCY);
        LibOrchestratorInvariants.assertInstance(safe);

        vm.expectRevert(
            abi.encodeWithSelector(UnexpectedMigrationLine.selector, LibStoxMigrations.ORCHESTRATOR_EMERGENCY)
        );
        script.callPreflight();
    }

    function testGrantBundleBase() external {
        assertBundle(LibRainDeploy.BASE);
    }

    function testGrantBundleEthereum() external {
        assertBundle(LibStoxDeployNetworks.ETHEREUM);
    }

    function testGrantBundleHyperEvm() external {
        assertBundle(LibStoxDeployNetworks.HYPEREVM);
    }

    function testGrantBundleRobinhood() external {
        assertBundle(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testGrantBundleBsc() external {
        assertBundle(LibStoxDeployNetworks.BSC);
    }

    /// @notice Whether the grant has executed on the active chain. The
    /// refusal and tamper tests below need the pre-grant state; once it has
    /// executed they report SPENT and stop asserting.
    function spent() internal view returns (bool) {
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        if (LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_EMERGENCY) != 0) {
            console2.log("SPENT: the grant has executed on this chain");
            return true;
        }
        return false;
    }

    /// @notice A grant made outside a recorded migration (a hand-built
    /// transaction) is refused rather than recorded over.
    function testRefusesUnrecordedGrant() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        if (spent()) return;
        GrantOrchestratorEmergencyHarness script = new GrantOrchestratorEmergencyHarness("unrecorded");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        bytes32 emergencyRole = ORCHESTRATOR.EMERGENCY_ROLE();
        vm.prank(safe);
        ORCHESTRATOR.grantRole(emergencyRole, safe);
        vm.expectRevert(EmergencyAlreadyGranted.selector);
        script.callPreflight();
    }

    /// @notice A line that has moved off genesis for any reason is refused.
    function testRefusesLineOffGenesis() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        if (spent()) return;
        GrantOrchestratorEmergencyHarness script = new GrantOrchestratorEmergencyHarness("off-genesis");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        bytes32 other = keccak256("some other migration");
        vm.prank(safe);
        IMigrationRegistryV2(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .applyMigration(LibStoxMigrations.NAMESPACE, other, LibStoxMigrations.onto(safe, MIGRATION_HEAD_GENESIS));
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, other));
        script.callPreflight();
    }

    /// @notice The n+1 proof refuses a revoke that executes but leaves the
    /// Safe holding `EMERGENCY`: the orchestrator's `revokeRole` for exactly
    /// that role and holder is mocked to a silent no-op. The refusal comes
    /// before the artifact is written, so none is.
    function testRefusesNPlus1RevokeThatLeavesTheRole() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        if (spent()) return;
        GrantOrchestratorEmergencyHarness script = new GrantOrchestratorEmergencyHarness("n-plus-1");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        bytes32 emergencyRole = ORCHESTRATOR.EMERGENCY_ROLE();
        vm.mockCall(address(ORCHESTRATOR), abi.encodeCall(IAccessControl.revokeRole, (emergencyRole, safe)), "");
        vm.expectRevert(EmergencyNotRevoked.selector);
        script.run();
        assertFalse(vm.exists(script.callArtifactPath()), "a refused bundle left an artifact");
    }

    /// @notice `verify` refuses an artifact that differs from the re-derived
    /// bundle: here, one that grants the role to a different address.
    function testVerifyRefusesTamperedArtifact() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        if (spent()) return;
        GrantOrchestratorEmergencyHarness script = new GrantOrchestratorEmergencyHarness("tamper");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        // Built in memory and written to its own paths, so this test never
        // reads the artifact `run()` writes for the other tests.
        string memory json =
            LibSafeTxBuilderJson.toJson(vm, safe, block.chainid, "tamper test", script.callAuthorBundle());
        string memory cleanPath =
            string.concat("out/20261006-grant-orchestrator-emergency-clean-", vm.toString(block.chainid), ".json");
        vm.writeFile(cleanPath, json);
        // Control: the untampered artifact verifies, so the refusal below is
        // the tamper's doing.
        script.verify(cleanPath);
        string memory tampered = vm.replace(
            json,
            vm.toString(abi.encodeCall(IAccessControl.grantRole, (ORCHESTRATOR.EMERGENCY_ROLE(), safe))),
            vm.toString(abi.encodeCall(IAccessControl.grantRole, (ORCHESTRATOR.EMERGENCY_ROLE(), address(0xdead))))
        );
        assertTrue(keccak256(bytes(tampered)) != keccak256(bytes(json)), "tamper did not apply");
        string memory tamperedPath =
            string.concat("out/20261006-grant-orchestrator-emergency-tampered-", vm.toString(block.chainid), ".json");
        vm.writeFile(tamperedPath, tampered);
        vm.expectRevert(abi.encodeWithSelector(LibSafeTxBuilderJson.ArtifactMismatch.selector, "data"));
        script.verify(tamperedPath);
    }
}

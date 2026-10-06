// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibRainDeploy} from "rain-deploy-0.1.12/src/lib/LibRainDeploy.sol";
import {IMigrationRegistryV2} from "rain-deploy-0.1.12/src/interface/IMigrationRegistryV2.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.12/src/lib/LibMigrationRegistryDeploy.sol";

import {
    EmergencyAlreadyGranted,
    UnexpectedMigrationLine
} from "../../script/20261006-grant-orchestrator-emergency.s.sol";
import {GrantOrchestratorEmergencyHarness} from "./GrantOrchestratorEmergencyHarness.sol";
import {IGnosisSafe} from "../../src/interface/IGnosisSafe.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx, TxBuilderArtifactMismatch} from "../../src/lib/LibSafeOps.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTestSafeBundle} from "../lib/LibTestSafeBundle.sol";

/// @title GrantOrchestratorEmergencyTest
/// @notice The grant on every deployment network at head. While the chain
/// has not executed it, `run()` authors, simulates and proves the bundle,
/// `verify` accepts the artifact, and the exact bundle executed through the
/// Safe's own MultiSend leaves the state the invariants demand and makes a
/// re-dispatch refuse. Once executed, the chain must be in that state and
/// the script must refuse.
contract GrantOrchestratorEmergencyTest is Test {
    IAccessControl internal constant ORCHESTRATOR =
        IAccessControl(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE);

    function assertGrant(string memory network) internal {
        vm.createSelectFork(network);
        GrantOrchestratorEmergencyHarness script = new GrantOrchestratorEmergencyHarness();
        address safe = LibSafeInvariants.safeForChainId(block.chainid);

        if (LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_EMERGENCY) != 0) {
            console2.log(string.concat("EXECUTED [", network, "]: asserting the post-grant state"));
            LibOrchestratorInvariants.assertInstance(safe);
            assertTrue(ORCHESTRATOR.hasRole(LibOrchestratorInvariants.EMERGENCY_ROLE, safe));
            (uint256 timelockMigratedAt,) = LibStoxMigrations.governanceTimelockExecution(block.chainid);
            assertEq(LibStoxMigrations.applied(safe, LibStoxMigrations.GOVERNANCE_TIMELOCK), timelockMigratedAt);
            vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, LibStoxMigrations.head(safe)));
            script.callPreflight();
            return;
        }

        console2.log(string.concat("PENDING [", network, "]: authoring, verifying and executing the bundle"));
        uint256 preRun = vm.snapshotState();
        script.run();
        assertTrue(ORCHESTRATOR.hasRole(LibOrchestratorInvariants.EMERGENCY_ROLE, safe), "run: EMERGENCY");
        vm.revertToState(preRun);

        script.verify(script.callArtifactPath());

        SafeTx[] memory txs = script.callAuthorBundle(safe);
        LibTestSafeBundle.execute(IGnosisSafe(safe), txs, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);

        assertTrue(ORCHESTRATOR.hasRole(LibOrchestratorInvariants.EMERGENCY_ROLE, safe), "exec: EMERGENCY");
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

    function testGrantBase() external {
        assertGrant(LibRainDeploy.BASE);
    }

    function testGrantEthereum() external {
        assertGrant(LibStoxDeployNetworks.ETHEREUM);
    }

    function testGrantHyperEvm() external {
        assertGrant(LibStoxDeployNetworks.HYPEREVM);
    }

    function testGrantRobinhood() external {
        assertGrant(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testGrantBsc() external {
        assertGrant(LibStoxDeployNetworks.BSC);
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
        GrantOrchestratorEmergencyHarness script = new GrantOrchestratorEmergencyHarness();
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        vm.prank(safe);
        ORCHESTRATOR.grantRole(LibOrchestratorInvariants.EMERGENCY_ROLE, safe);
        vm.expectRevert(EmergencyAlreadyGranted.selector);
        script.callPreflight();
    }

    /// @notice A line that has moved off genesis for any reason is refused.
    function testRefusesLineOffGenesis() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        if (spent()) return;
        GrantOrchestratorEmergencyHarness script = new GrantOrchestratorEmergencyHarness();
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        bytes32 other = keccak256("some other migration");
        vm.prank(safe);
        IMigrationRegistryV2(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .applyMigration(
                LibStoxMigrations.NAMESPACE, other, LibStoxMigrations.onto(safe, LibStoxMigrations.genesis())
            );
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, other));
        script.callPreflight();
    }

    /// @notice `verify` refuses an artifact that differs from the re-derived
    /// bundle: here, one that grants the role to a different address.
    function testVerifyRefusesTamperedArtifact() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        if (spent()) return;
        GrantOrchestratorEmergencyHarness script = new GrantOrchestratorEmergencyHarness();
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        // Built in memory and written to its own paths, so this test never
        // reads the artifact `run()` writes for the other tests.
        string memory json =
            LibSafeOps.emitTxBuilderJson(safe, block.chainid, "tamper test", script.callAuthorBundle(safe));
        string memory cleanPath =
            string.concat("out/20261006-grant-orchestrator-emergency-clean-", vm.toString(block.chainid), ".json");
        vm.writeFile(cleanPath, json);
        // Control: the untampered artifact verifies, so the refusal below is
        // the tamper's doing.
        script.verify(cleanPath);
        string memory tampered = vm.replace(
            json,
            vm.toString(abi.encodeCall(IAccessControl.grantRole, (LibOrchestratorInvariants.EMERGENCY_ROLE, safe))),
            vm.toString(
                abi.encodeCall(IAccessControl.grantRole, (LibOrchestratorInvariants.EMERGENCY_ROLE, address(0xdead)))
            )
        );
        assertTrue(keccak256(bytes(tampered)) != keccak256(bytes(json)), "tamper did not apply");
        string memory tamperedPath =
            string.concat("out/20261006-grant-orchestrator-emergency-tampered-", vm.toString(block.chainid), ".json");
        vm.writeFile(tamperedPath, tampered);
        vm.expectPartialRevert(TxBuilderArtifactMismatch.selector);
        script.verify(tamperedPath);
    }
}

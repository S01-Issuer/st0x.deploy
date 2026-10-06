// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibRainDeploy} from "rain-deploy-0.1.12/src/lib/LibRainDeploy.sol";

import {UnexpectedMigrationLine} from "../../script/20261006-orchestrator-admin-to-timelock.s.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {GrantOrchestratorEmergencyHarness} from "./GrantOrchestratorEmergencyHarness.sol";
import {IGnosisSafe} from "../../src/interface/IGnosisSafe.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {SafeTx, TxBuilderArtifactMismatch} from "../../src/lib/LibSafeOps.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTestSafeBundle} from "../lib/LibTestSafeBundle.sol";

/// @title OrchestratorAdminToTimelockTest
/// @notice The admin move on every deployment network at head, walking the
/// line: before the EMERGENCY grant the script refuses; with the grant
/// executed (live, or its bundle executed on the fork) `run()` authors,
/// simulates and proves the move, `verify` accepts the artifact, the exact
/// bundle executed through the Safe's own MultiSend leaves the state the
/// invariants demand, and a re-dispatch refuses. Once executed on chain, the
/// chain must be in that state.
contract OrchestratorAdminToTimelockTest is Test {
    IAccessControl internal constant ORCHESTRATOR =
        IAccessControl(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE);

    function executeEmergencyGrant(address safe) internal {
        GrantOrchestratorEmergencyHarness grant = new GrantOrchestratorEmergencyHarness();
        LibTestSafeBundle.execute(
            IGnosisSafe(safe), grant.callAuthorBundle(safe), LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD
        );
    }

    function assertMove(string memory network) internal {
        vm.createSelectFork(network);
        OrchestratorAdminToTimelockHarness script = new OrchestratorAdminToTimelockHarness();
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);

        if (LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) != 0) {
            console2.log(string.concat("EXECUTED [", network, "]: asserting the post-move state"));
            LibOrchestratorInvariants.assertInstance(safe);
            assertTrue(ORCHESTRATOR.hasRole(bytes32(0), timelock));
            vm.expectRevert(
                abi.encodeWithSelector(
                    UnexpectedMigrationLine.selector, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK
                )
            );
            script.callPreflight();
            return;
        }

        if (LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_EMERGENCY) == 0) {
            console2.log(string.concat("PENDING [", network, "]: EMERGENCY grant not executed; move refused"));
            vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, LibStoxMigrations.head(safe)));
            script.callPreflight();
            executeEmergencyGrant(safe);
        }

        console2.log(string.concat("PENDING [", network, "]: authoring, verifying and executing the move"));
        uint256 preRun = vm.snapshotState();
        script.run();
        vm.revertToState(preRun);

        script.verify(script.callArtifactPath());

        SafeTx[] memory txs = script.callAuthorBundle(safe, timelock);
        LibTestSafeBundle.execute(IGnosisSafe(safe), txs, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);

        assertTrue(ORCHESTRATOR.hasRole(bytes32(0), timelock), "exec: timelock admin");
        assertFalse(ORCHESTRATOR.hasRole(bytes32(0), safe), "exec: Safe admin");
        assertTrue(ORCHESTRATOR.hasRole(LibOrchestratorInvariants.EMERGENCY_ROLE, safe), "exec: Safe EMERGENCY");
        assertEq(LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK), block.timestamp);
        assertEq(LibStoxMigrations.head(safe), LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK);
        LibOrchestratorInvariants.assertInstance(safe);

        // The Safe can no longer grant directly.
        vm.prank(safe);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, safe, bytes32(0))
        );
        ORCHESTRATOR.grantRole(LibOrchestratorInvariants.MINT_ROLE, safe);

        vm.expectRevert(
            abi.encodeWithSelector(UnexpectedMigrationLine.selector, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK)
        );
        script.callPreflight();
    }

    function testMoveBase() external {
        assertMove(LibRainDeploy.BASE);
    }

    function testMoveEthereum() external {
        assertMove(LibStoxDeployNetworks.ETHEREUM);
    }

    function testMoveHyperEvm() external {
        assertMove(LibStoxDeployNetworks.HYPEREVM);
    }

    function testMoveRobinhood() external {
        assertMove(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testMoveBsc() external {
        assertMove(LibStoxDeployNetworks.BSC);
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
        if (LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_EMERGENCY) == 0) {
            executeEmergencyGrant(safe);
        }
        OrchestratorAdminToTimelockHarness script = new OrchestratorAdminToTimelockHarness();
        uint256 preRun = vm.snapshotState();
        script.run();
        vm.revertToState(preRun);

        string memory path = script.callArtifactPath();
        string memory json = vm.readFile(path);
        string memory timelockHex =
            vm.replace(vm.toLowercase(vm.toString(LibTimelockInvariants.timelockForChainId(block.chainid))), "0x", "");
        string memory tampered = vm.replace(json, timelockHex, "000000000000000000000000000000000000dead");
        assertTrue(keccak256(bytes(tampered)) != keccak256(bytes(json)), "tamper did not apply");
        string memory tamperedPath = string.concat(path, ".tampered.json");
        vm.writeFile(tamperedPath, tampered);
        vm.expectPartialRevert(TxBuilderArtifactMismatch.selector);
        script.verify(tamperedPath);
    }
}

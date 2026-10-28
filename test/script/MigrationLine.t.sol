// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.25/src/interface/IMigrationRegistryV3.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.25/src/lib/LibMigrationRegistry.sol";
import {LibRainDeploy} from "rain-deploy-0.1.25/src/lib/LibRainDeploy.sol";

import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibMigrationLineFork} from "../lib/LibMigrationLineFork.sol";
import {MigrateMultisigThresholdHarness} from "./MigrateMultisigThresholdHarness.sol";
import {MigrateGovernanceToTimelockHarness} from "./MigrateGovernanceToTimelockHarness.sol";
import {GrantEuAuthoriserRolesHarness} from "./GrantEuAuthoriserRolesHarness.sol";
import {GrantOrchestratorEmergencyHarness} from "./GrantOrchestratorEmergencyHarness.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {RetireDirectSignerRolesHarness} from "./RetireDirectSignerRolesHarness.sol";

/// @title MigrationLineTest
/// @notice On every network the line replays on live state, in line order,
/// from the live head to the end.
contract MigrationLineTest is Test {
    /// @notice Runs the line's migration at `index`.
    /// @param index The migration's position on the line.
    /// @param timelock The chain's timelock.
    /// @param tag The artifact tag, unique per test.
    function replay(uint256 index, address timelock, string memory tag) internal {
        if (index == 0) {
            new MigrateMultisigThresholdHarness(tag).run();
        } else if (index == 1) {
            new MigrateGovernanceToTimelockHarness(timelock, tag).run();
        } else if (index == 2) {
            new GrantEuAuthoriserRolesHarness(tag).run();
        } else if (index == 3) {
            new GrantOrchestratorEmergencyHarness(tag).run();
        } else if (index == 4) {
            new OrchestratorAdminToTimelockHarness(tag).run();
        } else {
            RetireDirectSignerRolesHarness retire = new RetireDirectSignerRolesHarness(tag);
            retire.run();
            vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
            retire.run();
        }
    }

    /// @notice Replays the line on the selected fork from its live head to
    /// the end, then checks every record and the head.
    /// @param network The fork's name, for messages.
    /// @param tag The artifact tag, unique per test.
    function replayFromLiveHead(string memory network, string memory tag) internal {
        ScriptDeclaration[] memory line = LibMigrationLineFork.line();
        bytes32 liveHead = LibStoxMigrations.head();
        uint256 start = 0;
        if (liveHead != MIGRATION_HEAD_GENESIS) {
            while (start < line.length && line[start].id != liveHead) {
                start++;
            }
            assertLt(start, line.length, string.concat(network, ": live head is off the line"));
            start++;
        }
        console2.log(string.concat("[", network, "] replaying from line index"), start);

        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        LibMigrationLineFork.approve(vm, LibSafeInvariants.safeForChainId(block.chainid));
        LibMigrationLineFork.approve(vm, timelock);
        for (uint256 j = start; j < line.length; j++) {
            replay(j, timelock, tag);
        }

        for (uint256 j = 0; j < line.length; j++) {
            assertEq(
                LibMigrationRegistry.appliedOntoV3(LibStoxMigrations.WRITER, LibStoxMigrations.NAMESPACE, line[j].id),
                line[j].onto,
                network
            );
        }
        assertEq(LibStoxMigrations.head(), line[line.length - 1].id, network);
    }

    function testLineReplaysFromTheLiveHeadOnEveryNetwork() external {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.createSelectFork(networks[i]);
            replayFromLiveHead(networks[i], "line");
        }
    }

    /// @notice A line already moved past genesis replays from its head: the
    /// threshold has run, so the replay starts at the governance move.
    function testLineReplaysFromAMovedHead() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        if (LibStoxMigrations.head() == MIGRATION_HEAD_GENESIS) {
            LibMigrationLineFork.approve(vm, LibSafeInvariants.safeForChainId(block.chainid));
            replay(0, LibTimelockInvariants.timelockForChainId(block.chainid), "movedLine");
        }
        assertTrue(LibStoxMigrations.head() != MIGRATION_HEAD_GENESIS);
        replayFromLiveHead(LibRainDeploy.BASE, "movedLine");
    }
}

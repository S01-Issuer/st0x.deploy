// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.22/src/interface/IMigrationRegistryV3.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.22/src/lib/LibMigrationRegistry.sol";

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
/// @notice Every migration replays on the live state of every network, in
/// line order, from genesis.
contract MigrationLineTest is Test {
    function testLineReplaysFromGenesisOnEveryNetwork() external {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.createSelectFork(networks[i]);
            assertEq(LibStoxMigrations.head(), MIGRATION_HEAD_GENESIS, networks[i]);
            address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
            LibMigrationLineFork.approve(vm, LibSafeInvariants.safeForChainId(block.chainid));
            LibMigrationLineFork.approve(vm, timelock);

            new MigrateMultisigThresholdHarness("line").run();
            new MigrateGovernanceToTimelockHarness(timelock, "line").run();
            new GrantEuAuthoriserRolesHarness("line").run();
            new GrantOrchestratorEmergencyHarness().run();
            new OrchestratorAdminToTimelockHarness("line").run();
            RetireDirectSignerRolesHarness retire = new RetireDirectSignerRolesHarness("line");
            retire.run();
            vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
            retire.run();

            ScriptDeclaration[] memory line = LibMigrationLineFork.line();
            for (uint256 j = 0; j < line.length; j++) {
                assertEq(
                    LibMigrationRegistry.appliedOntoV3(LibStoxMigrations.WRITER, LibStoxMigrations.NAMESPACE, line[j].id),
                    line[j].onto,
                    networks[i]
                );
            }
            assertEq(LibStoxMigrations.head(), line[line.length - 1].id, networks[i]);
        }
    }
}

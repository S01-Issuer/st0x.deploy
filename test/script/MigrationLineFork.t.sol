// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.25/src/interface/IMigrationRegistryV3.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.25/src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.25/src/lib/LibMigrationRegistryDeploy.sol";
import {
    RUNTIME_CODE as MIGRATION_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.25/src/generated/candidate/MigrationRegistry.sol";

import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibMigrationLineFork} from "../lib/LibMigrationLineFork.sol";

/// @title MigrationLineForkTest
/// @notice `LibMigrationLineFork.recordOnto` on an empty local registry: it
/// puts the head at a migration's onto from any earlier head, and reports a
/// migration the line already records without touching the line.
contract MigrationLineForkTest is Test {
    function setUp() external {
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, MIGRATION_REGISTRY_RUNTIME_CODE);
    }

    function record(ScriptDeclaration memory declared) internal {
        vm.prank(LibStoxMigrations.WRITER);
        LibMigrationRegistry.applyMigrationV3(
            LibStoxMigrations.WRITER, LibStoxMigrations.NAMESPACE, declared.id, LibStoxMigrations.onto(declared.onto)
        );
    }

    function testRecordOntoFromGenesis() external {
        ScriptDeclaration[] memory line = LibMigrationLineFork.line();
        for (uint256 i = 0; i < line.length; i++) {
            uint256 genesis = vm.snapshotState();
            assertEq(LibStoxMigrations.head(), MIGRATION_HEAD_GENESIS);
            assertFalse(LibMigrationLineFork.recordOnto(vm, line[i]));
            assertEq(LibStoxMigrations.head(), line[i].onto);
            assertEq(LibStoxMigrations.applied(line[i].id), 0);
            vm.revertToState(genesis);
        }
    }

    function testRecordOntoFromAMovedHead() external {
        ScriptDeclaration[] memory line = LibMigrationLineFork.line();
        assertFalse(LibMigrationLineFork.recordOnto(vm, line[2]));
        record(line[2]);
        assertFalse(LibMigrationLineFork.recordOnto(vm, line[5]));
        assertEq(LibStoxMigrations.head(), line[5].onto);
    }

    function testRecordOntoReportsARecordedMigration() external {
        ScriptDeclaration[] memory line = LibMigrationLineFork.line();
        assertFalse(LibMigrationLineFork.recordOnto(vm, line[3]));
        record(line[3]);
        for (uint256 i = 0; i <= 3; i++) {
            assertTrue(LibMigrationLineFork.recordOnto(vm, line[i]));
            assertEq(LibStoxMigrations.head(), line[3].id);
        }
        assertFalse(LibMigrationLineFork.recordOnto(vm, line[4]));
        assertEq(LibStoxMigrations.head(), line[4].onto);
    }
}

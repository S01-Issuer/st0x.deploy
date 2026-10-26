// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {ScriptDeclaration} from "../../../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../../../src/lib/LibStoxMigrations.sol";

contract LibStoxMigrationsDeclarationsTest is Test {
    function testMigrationOntoIsTheIdOntoTheHead(bytes32 id, bytes32 headMigration) external pure {
        ScriptDeclaration memory declared = LibStoxMigrations.migrationOnto(id, headMigration);
        assertTrue(declared.migration);
        assertEq(declared.id, id);
        assertEq(declared.onto, headMigration);
    }

    function testNotAMigrationCarriesNoRecord() external pure {
        ScriptDeclaration memory declared = LibStoxMigrations.notAMigration();
        assertFalse(declared.migration);
        assertEq(declared.id, 0);
        assertEq(declared.onto, 0);
    }
}

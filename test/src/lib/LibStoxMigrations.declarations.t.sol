// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Prerequisite} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";

import {ScriptDeclaration} from "../../../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../../../src/lib/LibStoxMigrations.sol";

contract LibStoxMigrationsDeclarationsTest is Test {
    function testADeclarationIsRecordedAfterItsHeadOnTheRootLineAlone(bytes32 id, bytes32 head, bool history)
        external
        pure
    {
        Prerequisite[] memory prerequisites =
            LibStoxMigrations.prerequisitesFor(ScriptDeclaration({id: id, onto: head, history: history}));
        assertEq(prerequisites.length, 1);
        assertEq(prerequisites[0].writer, LibRegistryAuthority.ROOT_AUTHORITY);
        assertEq(prerequisites[0].namespace, LibStoxMigrations.NAMESPACE);
        assertEq(prerequisites[0].migration, head);
    }
}

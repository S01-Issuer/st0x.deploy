// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.18/src/interface/IMigrationRegistryV2.sol";
import {IStoxScript, ScriptDeclaration} from "../../../../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../../../../src/lib/LibStoxMigrations.sol";

/// @dev The first record in a Safe-written fixture line.
contract ASafeLineFixture is IStoxScript {
    function declaration() external pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.safeMigrationOnto(keccak256("fixture.safe"), "s1", MIGRATION_HEAD_GENESIS, false);
    }
}

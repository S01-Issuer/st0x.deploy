// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.27/src/interface/IMigrationRegistryV3.sol";
import {IStoxScript, MigrationWriter, ScriptDeclaration} from "../../../../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../../../../src/lib/LibStoxMigrations.sol";

/// @dev The first record in a timelock-written fixture line.
contract BTimelockLineFirstFixture is IStoxScript {
    function declaration() external pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.migrationOnto(
            MigrationWriter.Timelock, keccak256("fixture.timelock"), "t1", MIGRATION_HEAD_GENESIS, false
        );
    }
}

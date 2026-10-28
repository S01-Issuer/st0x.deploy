// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.25/src/interface/IMigrationRegistryV3.sol";
import {IStoxScript, ScriptDeclaration} from "../../../../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../../../../src/lib/LibStoxMigrations.sol";

/// @notice The first record of a fixture root line.
contract ALineFirstFixture is IStoxScript {
    function declaration() external pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.migrationOnto(
            keccak256("test/fixture/declarations/line/ALineFirstFixture.s.sol"), MIGRATION_HEAD_GENESIS
        );
    }
}

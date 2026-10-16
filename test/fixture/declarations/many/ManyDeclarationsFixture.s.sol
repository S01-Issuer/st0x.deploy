// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IStoxScript, ScriptDeclaration, ScriptKind} from "../../../../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../../../../src/lib/LibStoxMigrations.sol";

/// @dev The first of two contracts in one file that declare themselves.
contract ManyDeclarationsFixtureA is IStoxScript {
    function declaration() external pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.notAMigration(ScriptKind.Deployment);
    }
}

/// @dev The second.
contract ManyDeclarationsFixtureB is IStoxScript {
    function declaration() external pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.notAMigration(ScriptKind.Deployment);
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IStoxScript, ScriptDeclaration, ScriptKind} from "../../../../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../../../../src/lib/LibStoxMigrations.sol";

/// @dev A migration that declares no record.
contract InvalidDeclarationFixture is IStoxScript {
    function declaration() external pure returns (ScriptDeclaration memory d) {
        d = LibStoxMigrations.notAMigration(ScriptKind.Deployment);
        d.kind = ScriptKind.Migration;
    }
}

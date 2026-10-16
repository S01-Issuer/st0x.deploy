// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IStoxScript, ScriptDeclaration, ScriptKind} from "../../../../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../../../../src/lib/LibStoxMigrations.sol";

/// @dev An interface beside the declaring contract, which discovery skips.
interface IValidDeclarationFixtureSibling {
    function noop() external;
}

/// @dev A script that declares itself.
contract ValidDeclarationFixture is IStoxScript {
    function declaration() external pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.notAMigration(ScriptKind.TimelockExecutor);
    }
}

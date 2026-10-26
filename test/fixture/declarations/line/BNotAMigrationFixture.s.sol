// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IStoxScript, ScriptDeclaration} from "../../../../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../../../../src/lib/LibStoxMigrations.sol";

/// @notice A script on the fixture root line that records nothing.
contract BNotAMigrationFixture is IStoxScript {
    function declaration() external pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.notAMigration();
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IStoxScript, ScriptDeclaration} from "../../../../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../../../../src/lib/LibStoxMigrations.sol";

/// @dev A library in the same file that also answers `declaration()`.
library LibManyDeclarationsFixture {
    function declaration() external pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.notAMigration();
    }
}

/// @dev A script whose file holds a second declaring artifact.
contract ManyDeclarationsFixture is IStoxScript {
    function declaration() external pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.notAMigration();
    }
}

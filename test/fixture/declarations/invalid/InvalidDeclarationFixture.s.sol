// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";
import {IStoxScript, ScriptDeclaration} from "../../../../src/interface/IStoxScript.sol";

/// @dev A migration that declares no record.
contract InvalidDeclarationFixture is IStoxScript {
    function declaration(uint256) external pure returns (ScriptDeclaration memory) {
        return ScriptDeclaration({id: 0, onto: MIGRATION_HEAD_GENESIS, history: false});
    }
}

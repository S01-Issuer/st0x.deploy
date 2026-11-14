// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";
import {IStoxScript, ScriptDeclaration} from "../../../../src/interface/IStoxScript.sol";

/// @dev An interface beside the declaring contract, which discovery skips.
interface IValidDeclarationFixtureSibling {
    function noop() external;
}

/// @dev A script that declares itself.
contract ValidDeclarationFixture is IStoxScript {
    function declaration(uint256) external pure returns (ScriptDeclaration memory) {
        return ScriptDeclaration({
            id: keccak256("test/fixture/declarations/valid/ValidDeclarationFixture.s.sol"),
            onto: MIGRATION_HEAD_GENESIS,
            history: false
        });
    }
}

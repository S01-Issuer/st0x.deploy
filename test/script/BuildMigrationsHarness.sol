// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {BuildMigrations} from "../../script/BuildMigrations.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";

/// @dev Exposes `BuildMigrations.executedAt`.
contract BuildMigrationsHarness is BuildMigrations {
    function callExecutedAt(string memory path, ScriptDeclaration memory declared, address instance, uint256 chainId)
        external
        pure
        returns (uint256)
    {
        return executedAt(path, declared, instance, chainId);
    }
}

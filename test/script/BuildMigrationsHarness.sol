// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {BuildMigrations} from "../../script/BuildMigrations.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";

/// @dev Exposes `BuildMigrations`' internal helpers.
contract BuildMigrationsHarness is BuildMigrations {
    function callExecutedAt(string memory path, ScriptDeclaration memory declared, address instance, uint256 chainId)
        external
        pure
        returns (uint256)
    {
        return executedAt(path, declared, instance, chainId);
    }

    function callBefore(string memory left, string memory right) external pure returns (bool) {
        return before(left, right);
    }

    function callSorted(string[] memory names) external pure returns (string[] memory) {
        return sorted(names);
    }
}

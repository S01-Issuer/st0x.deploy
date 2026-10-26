// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {BuildMigrations} from "../../script/BuildMigrations.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {SupportedNetwork} from "rain-deploy-0.1.22/src/lib/LibRainDeploy.sol";

/// @dev Exposes `BuildMigrations`' internal helpers.
contract BuildMigrationsHarness is BuildMigrations {
    function callBefore(string memory left, string memory right) external pure returns (bool) {
        return before(left, right);
    }

    function callSorted(string[] memory names) external pure returns (string[] memory) {
        return sorted(names);
    }

    function callRenderFor(string memory dir, SupportedNetwork[] memory networks) external returns (string memory) {
        return renderFor(dir, networks);
    }

    function callDeclaring(string memory path, string memory name)
        external
        returns (ScriptDeclaration memory)
    {
        return declaring(path, name);
    }
}

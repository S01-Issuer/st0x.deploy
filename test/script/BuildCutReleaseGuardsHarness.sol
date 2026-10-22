// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Build} from "../../script/Build.sol";

contract BuildCutReleaseGuardsHarness is Build {
    function checkReleaseIsNewExternal(string memory root, string memory tag) external view returns (string memory) {
        return checkReleaseIsNew(root, tag);
    }
}

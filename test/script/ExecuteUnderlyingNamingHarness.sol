// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {ExecuteUnderlyingNaming} from "../../script/20261021-execute-underlying-naming.s.sol";
import {SafeBundleScriptHooks} from "../lib/SafeBundleScriptHooks.sol";

contract ExecuteUnderlyingNamingHarness is ExecuteUnderlyingNaming, SafeBundleScriptHooks {
    constructor(string memory artifactTag) SafeBundleScriptHooks(artifactTag) {}

    /// @inheritdoc ExecuteUnderlyingNaming
    function artifactPath() internal view override returns (string memory) {
        return tagged(super.artifactPath());
    }
}

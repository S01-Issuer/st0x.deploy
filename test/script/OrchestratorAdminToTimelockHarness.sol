// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {OrchestratorAdminToTimelock} from "../../script/20261006-orchestrator-admin-to-timelock.s.sol";
import {SafeBundleScriptHooks} from "../lib/SafeBundleScriptHooks.sol";

contract OrchestratorAdminToTimelockHarness is OrchestratorAdminToTimelock, SafeBundleScriptHooks {
    constructor(string memory artifactTag) SafeBundleScriptHooks(artifactTag) {}

    /// @inheritdoc OrchestratorAdminToTimelock
    function artifactPath() internal view override returns (string memory) {
        return tagged(super.artifactPath());
    }

    function callPreflight() external view override {
        preflight();
    }

    function callAuthorBundle() external view override returns (SafeTx[] memory) {
        return authorBundle();
    }

    function callAssertPostState() external view override {
        assertPostState();
    }

    function callArtifactPath() external view override returns (string memory) {
        return artifactPath();
    }
}

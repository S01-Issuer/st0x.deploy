// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {SafeBundleScript} from "rain-deploy-0.1.30/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

/// @title SafeBundleScriptHooks
/// @notice Exposes a `SafeBundleScript`'s hooks so tests drive them directly.
/// A harness overrides `artifactPath` with `tagged(super.artifactPath())`:
/// `run()` removes and rewrites the artifact, and tests run in parallel.
abstract contract SafeBundleScriptHooks is SafeBundleScript {
    string internal sArtifactTag;

    constructor(string memory artifactTag) {
        sArtifactTag = artifactTag;
    }

    function tagged(string memory path) internal view returns (string memory) {
        return vm.replace(path, ".json", string.concat("-", sArtifactTag, ".json"));
    }

    function callPreflight() external view {
        preflight();
    }

    function callAuthorBundle() external view returns (SafeTx[] memory) {
        return authorBundle();
    }

    function callAssertPostState() external view {
        assertPostState();
    }

    function callArtifactPath() external view returns (string memory) {
        return artifactPath();
    }
}

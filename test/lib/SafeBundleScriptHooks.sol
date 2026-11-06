// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {CommonBase} from "forge-std-1.17.0/src/Base.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

/// @title SafeBundleScriptHooks
/// @notice A `SafeBundleScript` harness exposes the script's hooks and tags
/// its artifact path: `run()` removes and rewrites the artifact, and tests run
/// in parallel. Not a `SafeBundleScript`: a script's non-virtual
/// `assertReversible` override cannot join that diamond.
abstract contract SafeBundleScriptHooks is CommonBase {
    string internal sArtifactTag;

    constructor(string memory artifactTag) {
        sArtifactTag = artifactTag;
    }

    function tagged(string memory path) internal view returns (string memory) {
        return vm.replace(path, ".json", string.concat("-", sArtifactTag, ".json"));
    }

    function callPreflight() external view virtual;

    function callAuthorBundle() external view virtual returns (SafeTx[] memory);

    function callAssertPostState() external view virtual;

    function callArtifactPath() external view virtual returns (string memory);
}

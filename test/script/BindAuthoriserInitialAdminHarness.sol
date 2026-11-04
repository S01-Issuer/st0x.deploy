// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {BindAuthoriserInitialAdmin} from "../../script/20261022-bind-authoriser-initial-admin.s.sol";

/// @dev Exposes the script's hooks, with a per-instance artifact path because
/// tests run in parallel.
contract BindAuthoriserInitialAdminHarness is BindAuthoriserInitialAdmin {
    string internal sArtifactTag;

    /// @param artifactTag Suffixes this instance's artifact path.
    constructor(string memory artifactTag) {
        sArtifactTag = artifactTag;
    }

    /// @inheritdoc BindAuthoriserInitialAdmin
    function artifactPath() internal view override returns (string memory) {
        return string.concat(
            "out/20261022-bind-authoriser-initial-admin-", vm.toString(block.chainid), "-", sArtifactTag, ".json"
        );
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

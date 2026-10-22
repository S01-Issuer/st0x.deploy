// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.21/src/lib/LibSafeTx.sol";

import {BackfillHistory} from "../../script/20261017-backfill-history.s.sol";

/// @dev Exposes the script's hooks so the tests can drive them directly, and
/// gives each test its own artifact path: `run()` removes and rewrites the
/// artifact, and tests run in parallel.
contract BackfillHistoryHarness is BackfillHistory {
    string internal sArtifactTag;

    /// @param artifactTag Suffixes this instance's artifact path.
    constructor(string memory artifactTag) {
        sArtifactTag = artifactTag;
    }

    /// @inheritdoc BackfillHistory
    function artifactPath() internal view override returns (string memory) {
        return string.concat("out/20261017-backfill-history-", vm.toString(block.chainid), "-", sArtifactTag, ".json");
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

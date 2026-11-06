// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {ScheduleUnderlyingNamingRename} from "../../script/20261021-schedule-underlying-naming-rename.s.sol";

/// @dev Exposes the script's hooks; tags the artifact path because `run()` rewrites it and tests run in parallel.
contract ScheduleUnderlyingNamingRenameHarness is ScheduleUnderlyingNamingRename {
    string internal sArtifactTag;

    constructor(string memory artifactTag) {
        sArtifactTag = artifactTag;
    }

    /// @inheritdoc ScheduleUnderlyingNamingRename
    function artifactPath() internal view override returns (string memory) {
        return vm.replace(super.artifactPath(), ".json", string.concat("-", sArtifactTag, ".json"));
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

    /// @inheritdoc ScheduleUnderlyingNamingRename
    /// @dev The tests exercise the rollout against the planted candidate
    /// implementations, as if they were the frozen release.
    function releaseFrozen() internal pure override returns (bool) {
        return true;
    }

    /// @inheritdoc ScheduleUnderlyingNamingRename
    /// @dev The tests run the rename as if the services were ready.
    function downstreamReady() internal pure override returns (bool) {
        return true;
    }

    function callAssertRenamed(uint256 chainId) external view {
        assertRenamed(chainId);
    }
}

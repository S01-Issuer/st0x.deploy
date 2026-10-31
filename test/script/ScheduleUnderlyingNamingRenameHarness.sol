// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.29/src/lib/LibSafeTx.sol";

import {ScheduleUnderlyingNamingRename} from "../../script/20261021-schedule-underlying-naming-rename.s.sol";

/// @dev Exposes the script's hooks and gives each test its own artifact path.
contract ScheduleUnderlyingNamingRenameHarness is ScheduleUnderlyingNamingRename {
    string internal sArtifactTag;

    /// @param artifactTag Suffixes this instance's artifact path.
    constructor(string memory artifactTag) {
        sArtifactTag = artifactTag;
    }

    /// @inheritdoc ScheduleUnderlyingNamingRename
    function artifactPath() internal view override returns (string memory) {
        return string.concat(
            "out/20261021-schedule-underlying-naming-rename-", vm.toString(block.chainid), "-", sArtifactTag, ".json"
        );
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

    function callPreflight() external view {
        preflight();
    }

    function callAuthorBundle() external view returns (SafeTx[] memory) {
        return authorBundle();
    }

    function callArtifactPath() external view returns (string memory) {
        return artifactPath();
    }

    function callAssertRenamed(uint256 chainId) external view {
        assertRenamed(chainId);
    }
}

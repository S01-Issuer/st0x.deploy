// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.38/src/lib/LibSafeTx.sol";

import {ExecuteUnderlyingNamingBeacons} from "../../script/20261021-execute-underlying-naming-beacons.s.sol";

/// @dev Exposes the script's hooks; tags the artifact path because `run()` rewrites it and tests run in parallel.
contract ExecuteUnderlyingNamingBeaconsHarness is ExecuteUnderlyingNamingBeacons {
    string internal sArtifactTag;

    constructor(string memory artifactTag) {
        sArtifactTag = artifactTag;
    }

    /// @inheritdoc ExecuteUnderlyingNamingBeacons
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
}

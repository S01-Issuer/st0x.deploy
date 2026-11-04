// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {RecordExecuteUnderlyingNaming} from "../../script/20261021-execute-underlying-naming.s.sol";

/// @dev Exposes the script's hooks and gives each test its own artifact path.
contract RecordExecuteUnderlyingNamingHarness is RecordExecuteUnderlyingNaming {
    string internal sArtifactTag;

    /// @param artifactTag Suffixes this instance's artifact path.
    constructor(string memory artifactTag) {
        sArtifactTag = artifactTag;
    }

    /// @inheritdoc RecordExecuteUnderlyingNaming
    function artifactPath() internal view override returns (string memory) {
        return string.concat(
            "out/20261021-execute-underlying-naming-record-", vm.toString(block.chainid), "-", sArtifactTag, ".json"
        );
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

    function callAssertPostState() external view {
        assertPostState();
    }
}

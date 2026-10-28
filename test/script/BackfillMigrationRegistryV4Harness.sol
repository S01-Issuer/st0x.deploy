// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.27/src/lib/LibSafeTx.sol";

import {BackfillMigrationRegistryV4} from "../../script/20261022-backfill-migration-registry-v4.s.sol";

/// @dev Exposes the script's hooks, with a per-instance artifact path because
/// tests run in parallel.
contract BackfillMigrationRegistryV4Harness is BackfillMigrationRegistryV4 {
    string internal sArtifactTag;

    constructor(string memory artifactTag) {
        sArtifactTag = artifactTag;
    }

    /// @inheritdoc BackfillMigrationRegistryV4
    function artifactPath() internal view override returns (string memory) {
        return string.concat(
            "out/20261022-backfill-migration-registry-v4-", vm.toString(block.chainid), "-", sArtifactTag, ".json"
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

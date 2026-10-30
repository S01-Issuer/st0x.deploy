// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.29/src/lib/LibSafeTx.sol";

import {BackfillMigrationRegistryV5} from "../../script/20261030-backfill-migration-registry-v5.s.sol";

/// @dev Exposes the script's hooks, with a per-instance artifact path because
/// tests run in parallel.
contract BackfillMigrationRegistryV5Harness is BackfillMigrationRegistryV5 {
    string internal sArtifactTag;

    constructor(string memory artifactTag) {
        sArtifactTag = artifactTag;
    }

    /// @inheritdoc BackfillMigrationRegistryV5
    function artifactPath() internal view override returns (string memory) {
        return string.concat(
            "out/20261030-backfill-migration-registry-v5-", vm.toString(block.chainid), "-", sArtifactTag, ".json"
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

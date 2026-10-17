// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.18/src/lib/LibSafeTx.sol";

import {MigrateMultisigThreshold} from "../../script/MigrateMultisigThreshold.s.sol";

/// @dev Exposes the script's hooks, with an artifact path per instance.
contract MigrateMultisigThresholdHarness is MigrateMultisigThreshold {
    string internal sArtifactTag;

    /// @param artifactTag Suffixes this instance's artifact path.
    constructor(string memory artifactTag) {
        sArtifactTag = artifactTag;
    }

    /// @inheritdoc MigrateMultisigThreshold
    function artifactPath() internal view override returns (string memory) {
        return string.concat("out/MigrateMultisigThreshold-", vm.toString(block.chainid), "-", sArtifactTag, ".json");
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
}

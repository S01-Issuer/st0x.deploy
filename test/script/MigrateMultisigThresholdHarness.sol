// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.22/src/lib/LibSafeTx.sol";

import {MigrateMultisigThreshold} from "../../script/20260619-migrate-multisig-threshold.s.sol";

contract MigrateMultisigThresholdHarness is MigrateMultisigThreshold {
    string internal sArtifactTag;

    constructor(string memory artifactTag) {
        sArtifactTag = artifactTag;
    }

    function artifactPath() internal view override returns (string memory) {
        return string.concat(
            "out/20260619-migrate-multisig-threshold-", vm.toString(block.chainid), "-", sArtifactTag, ".json"
        );
    }

    function callArtifactPath() external view returns (string memory) {
        return artifactPath();
    }

    function callAuthorBundle() external view returns (SafeTx[] memory) {
        return authorBundle();
    }
}

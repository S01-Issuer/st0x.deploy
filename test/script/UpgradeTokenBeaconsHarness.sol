// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.20/src/lib/LibSafeTx.sol";

import {UpgradeTokenBeacons} from "../../script/20261022-upgrade-token-beacons.s.sol";

/// @dev Exposes the script's hooks so the tests can drive them directly, and
/// gives each test its own artifact path: `run()` removes and rewrites the
/// artifact, and tests run in parallel.
contract UpgradeTokenBeaconsHarness is UpgradeTokenBeacons {
    string internal sArtifactTag;

    /// @param artifactTag Suffixes this instance's artifact path.
    constructor(string memory artifactTag) {
        sArtifactTag = artifactTag;
    }

    /// @inheritdoc UpgradeTokenBeacons
    function artifactPath() internal view override returns (string memory) {
        return
            string.concat("out/20261022-upgrade-token-beacons-", vm.toString(block.chainid), "-", sArtifactTag, ".json");
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

    function callBatch() external view returns (address[] memory, uint256[] memory, bytes[] memory) {
        return batch();
    }

    function callOperationId() external view returns (bytes32) {
        return operationId();
    }
}

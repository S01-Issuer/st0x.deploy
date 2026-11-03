// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {HandWmtMcDisToTimelock} from "../../script/20261103-hand-wmt-mc-dis-to-timelock.s.sol";

/// @dev Exposes the script's hooks so the tests can drive them directly, and
/// gives each test its own artifact path: `run()` removes and rewrites the
/// artifact, and tests run in parallel.
contract HandWmtMcDisToTimelockHarness is HandWmtMcDisToTimelock {
    string internal sArtifactTag;

    /// @param artifactTag Suffixes this instance's artifact path.
    constructor(string memory artifactTag) {
        sArtifactTag = artifactTag;
    }

    /// @inheritdoc HandWmtMcDisToTimelock
    function artifactPath() internal view override returns (string memory) {
        return string.concat(
            "out/20261103-hand-wmt-mc-dis-to-timelock-", vm.toString(block.chainid), "-", sArtifactTag, ".json"
        );
    }

    function callPreflight() external view {
        preflight();
    }

    function callAuthorBundle() external pure returns (SafeTx[] memory) {
        return authorBundle();
    }

    function callArtifactPath() external view returns (string memory) {
        return artifactPath();
    }

    function callHandoverVaults() external pure returns (address[] memory) {
        return handoverVaults();
    }

    function callAssertPostState() external view {
        assertPostState();
    }

    function callProveGovernance() external {
        proveGovernance();
    }

    function callAssertReversible() external {
        assertReversible();
    }

    function callScriptArtifactPath() external view returns (string memory) {
        return HandWmtMcDisToTimelock.artifactPath();
    }

    function callBundleName() external pure returns (string memory) {
        return bundleName();
    }

    function callBeaconOf(address proxy) external view returns (address) {
        return beaconOf(proxy);
    }
}

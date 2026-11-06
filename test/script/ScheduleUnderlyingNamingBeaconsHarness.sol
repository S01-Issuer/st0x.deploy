// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {ScheduleUnderlyingNamingBeacons} from "../../script/20261021-schedule-underlying-naming-beacons.s.sol";
import {SafeBundleScriptHooks} from "../lib/SafeBundleScriptHooks.sol";

contract ScheduleUnderlyingNamingBeaconsHarness is ScheduleUnderlyingNamingBeacons, SafeBundleScriptHooks {
    constructor(string memory artifactTag) SafeBundleScriptHooks(artifactTag) {}

    /// @inheritdoc ScheduleUnderlyingNamingBeacons
    function artifactPath() internal view override returns (string memory) {
        return tagged(super.artifactPath());
    }

    function callPreflight() external view override {
        preflight();
    }

    function callAuthorBundle() external view override returns (SafeTx[] memory) {
        return authorBundle();
    }

    function callAssertPostState() external view override {
        assertPostState();
    }

    function callArtifactPath() external view override returns (string memory) {
        return artifactPath();
    }

    /// @inheritdoc ScheduleUnderlyingNamingBeacons
    /// @dev The tests exercise the rollout against the planted candidate
    /// implementations, as if they were the frozen release.
    function releaseFrozen() internal pure override returns (bool) {
        return true;
    }
}

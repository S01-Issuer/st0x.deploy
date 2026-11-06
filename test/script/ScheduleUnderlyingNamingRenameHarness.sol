// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {ScheduleUnderlyingNamingRename} from "../../script/20261021-schedule-underlying-naming-rename.s.sol";
import {SafeBundleScriptHooks} from "../lib/SafeBundleScriptHooks.sol";

contract ScheduleUnderlyingNamingRenameHarness is ScheduleUnderlyingNamingRename, SafeBundleScriptHooks {
    constructor(string memory artifactTag) SafeBundleScriptHooks(artifactTag) {}

    /// @inheritdoc ScheduleUnderlyingNamingRename
    function artifactPath() internal view override returns (string memory) {
        return tagged(super.artifactPath());
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

    function callAssertRenamed(uint256 chainId) external view {
        assertRenamed(chainId);
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {ScheduleUnderlyingNamingRename} from "../../script/20261021-schedule-underlying-naming-rename.s.sol";
import {FrozenReleaseRenameHarness} from "./FrozenReleaseRenameHarness.sol";

/// @dev The frozen-release rename script with the downstream flag unset, so
/// the downstream gate stays covered now that the repo sets it.
contract DownstreamNotReadyRenameHarness is FrozenReleaseRenameHarness {
    /// @inheritdoc ScheduleUnderlyingNamingRename
    function downstreamReady() internal pure override returns (bool) {
        return false;
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {ScheduleUnderlyingNamingRename} from "../../script/20261021-schedule-underlying-naming-rename.s.sol";

/// @dev The rename script as dispatched once the release is frozen, with the
/// downstream flag left as the repo sets it.
contract FrozenReleaseRenameHarness is ScheduleUnderlyingNamingRename {
    /// @inheritdoc ScheduleUnderlyingNamingRename
    function releaseFrozen() internal pure override returns (bool) {
        return true;
    }

    function callPreflight() external view {
        preflight();
    }
}

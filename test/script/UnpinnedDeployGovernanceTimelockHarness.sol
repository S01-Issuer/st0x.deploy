// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployGovernanceTimelockHarness} from "./DeployGovernanceTimelockHarness.sol";

/// @title UnpinnedDeployGovernanceTimelockHarness
/// @notice Overrides the deploy script's pin resolution to zero, simulating
/// a reverted or never-hydrated chain arm, so the pre-flight's refusal of a
/// zero pin has a discriminating test. Production dispatch always reads the
/// `LibTimelockInvariants` pin.
contract UnpinnedDeployGovernanceTimelockHarness is DeployGovernanceTimelockHarness {
    function pinnedTimelock() internal view override returns (address) {
        return address(0);
    }
}

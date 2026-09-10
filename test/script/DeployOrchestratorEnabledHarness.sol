// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {DeployOrchestratorEnabled} from "../../script/20260910-deploy-orchestrator-enabled.s.sol";

/// @title DeployOrchestratorEnabledHarness
/// @notice Exposes the script's internal pre-flight gates so each refusal
/// can be driven directly from a test.
contract DeployOrchestratorEnabledHarness is DeployOrchestratorEnabled {
    function assertClosureReady() external view {
        _assertClosureReady();
    }

    function assertNoInstanceYet(address setDeployer) external view {
        _assertNoInstanceYet(setDeployer);
    }

    function assertFleetUpgraded() external view {
        _assertFleetUpgraded();
    }
}

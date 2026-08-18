// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {DeployOrchestrator} from "../../script/20260818-deploy-orchestrator.s.sol";

/// @dev Exposes the script's internals so the guard tests can drive them
/// directly.
contract DeployOrchestratorHarness is DeployOrchestrator {
    /// @notice The script's `_assertClosureReady()`, externally callable.
    function assertClosureReady() external view {
        _assertClosureReady();
    }

    /// @notice The script's `_assertNoInstanceYet()`, externally callable.
    /// @param setDeployer The beacon-set deployer to inspect.
    function assertNoInstanceYet(address setDeployer) external view {
        _assertNoInstanceYet(setDeployer);
    }
}

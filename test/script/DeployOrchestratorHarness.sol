// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployOrchestrator} from "../../script/20260817-deploy-orchestrator.s.sol";

/// @title DeployOrchestratorHarness
/// @notice Subclass of the orchestrator deploy script that exposes its
/// `internal` steps as `external` so tests can drive them and
/// `vm.expectRevert` can intercept the typed errors they raise. Mirrors the
/// `DeployGovernanceTimelockHarness` pattern — `run()` creates its own fork
/// per network and state written inside those forks is not visible to a fork
/// the test creates afterwards, so per-chain tests drive
/// `callDeployOnActiveChain` directly on their own fork.
contract DeployOrchestratorHarness is DeployOrchestrator {
    function callDeployOnActiveChain() external returns (address orchestrator, address setDeployer) {
        return _deployOnActiveChain();
    }

    /// @notice The network list `run()` iterates.
    function callNetworks() external pure returns (string[] memory) {
        return networks();
    }

    /// @notice Exposes the post-state assertion so tests can drive it
    /// against perturbed state (e.g. a beacon whose ownership moved to an
    /// unrecognised address).
    function callAssertPostState(address orchestrator, address setDeployer, address timelock) external view {
        _assertPostState(orchestrator, setDeployer, timelock);
    }
}

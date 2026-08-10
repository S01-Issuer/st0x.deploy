// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployGovernanceTimelock} from "../../script/20260729-deploy-governance-timelock.s.sol";

/// @title DeployGovernanceTimelockHarness
/// @notice Subclass of the governance-timelock deploy script that exposes
/// its `internal` post-state assertion as `external` so `vm.expectRevert`
/// can intercept the typed errors it raises. Mirrors the
/// `DeployV4AuthoriserCloneHarness` pattern — `run()` itself broadcasts, and
/// `vm.startBroadcast` is mutually exclusive with `vm.prank` in
/// `forge test`, so the post-state assertion is driven directly against a
/// timelock the test already deployed.
contract DeployGovernanceTimelockHarness is DeployGovernanceTimelock {
    function callAssertPostState(address timelock, address safe, address deployer) external view {
        _assertPostState(timelock, safe, deployer);
    }

    /// @notice Deploy on whichever fork the TEST has selected. `run()` creates
    /// its own fork per network, and state written inside those forks is not
    /// visible to a fork the test creates afterwards — so per-chain tests
    /// drive this step directly on their own fork instead.
    function callDeployOnActiveChain() external {
        _deployOnActiveChain();
    }

    /// @notice The network list `run()` iterates.
    function callNetworks() external pure returns (string[] memory) {
        return networks();
    }
}

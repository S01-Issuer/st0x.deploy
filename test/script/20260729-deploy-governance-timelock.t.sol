// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {
    DeployGovernanceTimelock,
    TimelockAlreadyDeployed,
    DeployerHoldsTimelockRole
} from "../../script/20260729-deploy-governance-timelock.s.sol";
import {LibSafeInvariants, UnsupportedChainForTokenOwnerSafe} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @title DeployGovernanceTimelockHarness
/// @notice Exposes the script's internal post-state assertion so
/// `vm.expectRevert` can intercept its typed errors.
contract DeployGovernanceTimelockHarness is DeployGovernanceTimelock {
    function callAssertPostState(address timelock, address safe, address deployer) external view {
        _assertPostState(timelock, safe, deployer);
    }
}

/// @title DeployGovernanceTimelockTest
/// @notice Live-fork coverage for the governance-timelock deploy broadcast.
/// The script is deterministic (Zoltu CREATE2 over pinned init code), so the
/// tests drive the full `run()` against Base and Ethereum head forks and
/// assert the landed timelock at the derived address carries the pinned
/// configuration — the same assertion the production broadcast makes.
/// @dev Unpinned head forks: the pre-flight asserts live Safe policy, so any
/// production drift trips here before a real dispatch would hit it.
contract DeployGovernanceTimelockTest is Test {
    /// @notice Drive the full deploy on the active fork and return the
    /// landed timelock address.
    function runDeploy() internal returns (address) {
        DeployGovernanceTimelock script = new DeployGovernanceTimelock();
        script.run();
        return LibTimelockInvariants.expectedTimelockAddress(LibSafeInvariants.safeForChainId(block.chainid));
    }

    /// @notice The deploy lands at the derived address on Base and the
    /// timelock carries the full pinned configuration.
    function testRunDeploysOnBaseFork() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address timelock = runDeploy();
        assertGt(timelock.code.length, 0);
        LibTimelockInvariants.assertTimelockState(timelock, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
    }

    /// @notice The deploy lands at the derived address on Ethereum. The
    /// address differs from Base's by construction (the constructor embeds
    /// the chain's Safe).
    function testRunDeploysOnEthereumFork() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        address timelock = runDeploy();
        assertGt(timelock.code.length, 0);
        LibTimelockInvariants.assertTimelockState(timelock, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM);
        assertNotEq(timelock, LibTimelockInvariants.expectedTimelockAddress(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE));
    }

    /// @notice A second dispatch on the same chain refuses at pre-flight:
    /// the derived address already has code (deploy landed, pin PR
    /// outstanding).
    function testRunRefusesSecondDispatch() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address timelock = runDeploy();
        DeployGovernanceTimelock second = new DeployGovernanceTimelock();
        vm.expectRevert(abi.encodeWithSelector(TimelockAlreadyDeployed.selector, timelock));
        second.run();
    }

    /// @notice The script refuses to run on a chain without a pinned
    /// token-owner Safe rather than falling back to another chain's Safe.
    function testRunRefusesUnsupportedChain() external {
        // Local test chain id (31337) — no Safe pin exists.
        DeployGovernanceTimelock script = new DeployGovernanceTimelock();
        vm.expectRevert(abi.encodeWithSelector(UnsupportedChainForTokenOwnerSafe.selector, uint256(31337)));
        script.run();
    }

    /// @notice The holds-nothing post-state check trips on any principal
    /// that holds a timelock role — exercised with the Safe itself (which
    /// holds proposer by construction), proving the check reads live role
    /// state rather than vacuously passing.
    function testAssertPostStateRejectsRoleHolder() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        address timelock = runDeploy();
        DeployGovernanceTimelockHarness harness = new DeployGovernanceTimelockHarness();

        // The actual broadcast sender holds nothing.
        harness.callAssertPostState(timelock, safe, address(this));

        // A principal that DOES hold a role (the Safe holds proposer) trips
        // the deployer check.
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployerHoldsTimelockRole.selector, LibTimelockInvariants.TIMELOCK_PROPOSER_ROLE, safe
            )
        );
        harness.callAssertPostState(timelock, safe, safe);
    }
}

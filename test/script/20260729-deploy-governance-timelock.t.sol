// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {DeployerHoldsTimelockRole} from "../../script/20260729-deploy-governance-timelock.s.sol";
import {DeployGovernanceTimelockHarness} from "./DeployGovernanceTimelockHarness.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @title DeployGovernanceTimelockTest
/// @notice Live-fork coverage for the governance-timelock deploy broadcast.
/// The deploy is deterministic (Zoltu CREATE2 over pinned init code) and
/// idempotent per chain, so each chain is driven on its own fork and asserted
/// with the same checks the production broadcast makes.
/// @dev Per-chain rather than through `run()`: `run()` creates its own fork
/// per network, and deployments written inside those forks are not visible to
/// a fork a test creates afterwards. The tests therefore select a fork and
/// drive the per-chain step directly; `run()`'s own coverage is that it
/// iterates exactly `networks()`.
/// Unpinned head forks: the pre-flight asserts live Safe policy, so any
/// production drift trips here before a real dispatch would hit it.
contract DeployGovernanceTimelockTest is Test {
    /// @notice Deploy on the selected fork and return the derived address.
    /// @param safe The active chain's token-owner Safe.
    /// @return timelock The chain's derived timelock address.
    function deployOnSelectedFork(address safe) internal returns (address timelock) {
        new DeployGovernanceTimelockHarness().callDeployOnActiveChain();
        timelock = LibTimelockInvariants.expectedTimelockAddress(safe);
        assertGt(timelock.code.length, 0, "timelock must be deployed after the run");
        LibTimelockInvariants.assertTimelockState(timelock, safe);
    }

    /// @notice `run()` covers every chain that carries production tokens, so
    /// one dispatch is the whole rollout. Pins the list rather than the loop
    /// body, which the per-chain tests below exercise.
    function testNetworksCoversEveryProductionChain() external {
        string[] memory nets = new DeployGovernanceTimelockHarness().callNetworks();
        assertEq(nets.length, 3);
        assertEq(nets[0], LibRainDeploy.BASE);
        assertEq(nets[1], LibStoxDeployNetworks.ETHEREUM);
        assertEq(nets[2], LibStoxDeployNetworks.HYPEREVM);
    }

    /// @notice The deploy lands at the derived address on Base.
    function testDeploysOnBaseFork() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        deployOnSelectedFork(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
    }

    /// @notice The deploy lands at the derived address on Ethereum.
    function testDeploysOnEthereumFork() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        deployOnSelectedFork(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM);
    }

    /// @notice The deploy lands at the derived address on HyperEVM, which
    /// carries 29 live production tokens and is governed on the same terms as
    /// Base and Ethereum.
    function testDeploysOnHyperevmFork() external {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        deployOnSelectedFork(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_HYPEREVM);
    }

    /// @notice A chain that already carries the timelock is verified and
    /// skipped rather than redeployed or reverted — the property that makes a
    /// re-dispatch a safe no-op and lets a partial rollout finish in one run.
    function testSkipsAChainThatIsAlreadyDeployed() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        address first = deployOnSelectedFork(safe);

        // Second pass over the same chain: no revert, same address, same state.
        address second = deployOnSelectedFork(safe);
        assertEq(second, first, "a re-run must not move the timelock");
    }

    /// @notice HyperEVM shares Ethereum's token-owner Safe, and the
    /// constructor embeds only that Safe, so the two chains derive the SAME
    /// timelock address. Asserted so the equality is a recorded expectation
    /// rather than a surprise at pin time.
    function testEthereumAndHyperevmShareADerivedAddress() external pure {
        assertEq(
            LibTimelockInvariants.expectedTimelockAddress(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_HYPEREVM),
            LibTimelockInvariants.expectedTimelockAddress(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM)
        );
        assertNotEq(
            LibTimelockInvariants.expectedTimelockAddress(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE),
            LibTimelockInvariants.expectedTimelockAddress(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM)
        );
    }

    /// @notice The holds-nothing post-state check trips on any principal that
    /// holds a timelock role — exercised with the Safe itself (which holds
    /// proposer by construction), proving the check reads live role state
    /// rather than vacuously passing.
    function testAssertPostStateRejectsRoleHolder() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        address timelock = deployOnSelectedFork(safe);
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

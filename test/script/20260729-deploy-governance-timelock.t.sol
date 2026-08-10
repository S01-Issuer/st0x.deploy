// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {
    DeployGovernanceTimelock,
    DeployerHoldsTimelockRole
} from "../../script/20260729-deploy-governance-timelock.s.sol";
import {DeployGovernanceTimelockHarness} from "./DeployGovernanceTimelockHarness.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @title DeployGovernanceTimelockTest
/// @notice Live-fork coverage for the governance-timelock deploy broadcast.
/// The script forks every supported chain itself and is deterministic (Zoltu
/// CREATE2 over pinned init code), so a single `run()` covers the whole
/// rollout: these tests drive that one call and then assert each chain
/// independently, the same assertion the production broadcast makes.
/// @dev Unpinned head forks: the pre-flight asserts live Safe policy, so any
/// production drift trips here before a real dispatch would hit it.
contract DeployGovernanceTimelockTest is Test {
    /// @notice Every chain `run()` covers, paired with the Safe whose
    /// address derives that chain's timelock.
    /// @return nets The network aliases.
    /// @return safes The token-owner Safe per network, index-aligned.
    function chains() internal pure returns (string[] memory nets, address[] memory safes) {
        nets = new string[](3);
        safes = new address[](3);
        nets[0] = LibRainDeploy.BASE;
        safes[0] = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        nets[1] = LibStoxDeployNetworks.ETHEREUM;
        safes[1] = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM;
        nets[2] = LibStoxDeployNetworks.HYPEREVM;
        safes[2] = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_HYPEREVM;
    }

    /// @notice Assert every chain carries its derived timelock in the pinned
    /// configuration.
    function assertAllChainsDeployed() internal {
        (string[] memory nets, address[] memory safes) = chains();
        for (uint256 i = 0; i < nets.length; i++) {
            vm.createSelectFork(nets[i]);
            address timelock = LibTimelockInvariants.expectedTimelockAddress(safes[i]);
            assertGt(timelock.code.length, 0, "timelock must be deployed on every chain");
            LibTimelockInvariants.assertTimelockState(timelock, safes[i]);
        }
    }

    /// @notice One dispatch deploys (or verifies) the timelock on every
    /// supported chain. This is the whole rollout in a single run — the
    /// property that lets a partial rollout finish without a per-chain
    /// dispatch.
    function testRunDeploysOnAllChains() external {
        new DeployGovernanceTimelock().run();
        assertAllChainsDeployed();
    }

    /// @notice The deploy is idempotent per chain: a second dispatch skips
    /// every already-deployed chain instead of reverting or redeploying, so
    /// re-running is always safe.
    function testRunIsIdempotentAcrossChains() external {
        new DeployGovernanceTimelock().run();
        new DeployGovernanceTimelock().run();
        assertAllChainsDeployed();
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

    /// @notice The holds-nothing post-state check trips on any principal
    /// that holds a timelock role — exercised with the Safe itself (which
    /// holds proposer by construction), proving the check reads live role
    /// state rather than vacuously passing.
    function testAssertPostStateRejectsRoleHolder() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        address timelock = LibTimelockInvariants.expectedTimelockAddress(safe);
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

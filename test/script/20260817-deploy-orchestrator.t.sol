// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/UpgradeableBeacon.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {
    DeployedCodehashMismatch,
    UnexpectedBeaconOwner,
    ZoltuFactoryCodehashMismatch,
    ZoltuFactoryNotDeployed
} from "../../script/20260817-deploy-orchestrator.s.sol";
import {DeployOrchestratorHarness} from "./DeployOrchestratorHarness.sol";
import {ST0xOrchestratorBeaconSetDeployer} from "../../src/concrete/deploy/ST0xOrchestratorBeaconSetDeployer.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants, UnsupportedChainForGovernanceTimelock} from "../../src/lib/LibTimelockInvariants.sol";

/// @title DeployOrchestratorTest
/// @notice Live-fork coverage for the orchestrator-singletons deploy
/// broadcast. The deploy is deterministic (Zoltu CREATE2 over the candidate
/// creation bytecode) and idempotent per chain, so each chain is driven on
/// its own fork and asserted with the same checks the production broadcast
/// makes.
/// @dev Per-chain rather than through `run()`: `run()` creates its own fork
/// per network, and deployments written inside those forks are not visible to
/// a fork a test creates afterwards. The tests therefore select a fork and
/// drive the per-chain step directly; `run()`'s own coverage is that it
/// iterates exactly `networks()`.
contract DeployOrchestratorTest is Test {
    /// @notice Deploy on the selected fork and assert both singletons landed
    /// at their candidate pins with the pinned runtimes, wired through the
    /// beacon.
    /// @return orchestrator The orchestrator implementation's pinned address.
    /// @return setDeployer The beacon-set deployer's pinned address.
    function deployOnSelectedFork() internal returns (address orchestrator, address setDeployer) {
        (orchestrator, setDeployer) = new DeployOrchestratorHarness().callDeployOnActiveChain();
        assertEq(orchestrator, LibProdDeployV4.ST0X_ORCHESTRATOR_CANDIDATE, "impl landed off-pin");
        assertEq(
            setDeployer, LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CANDIDATE, "deployer landed off-pin"
        );
        assertEq(orchestrator.codehash, LibProdDeployV4.ST0X_ORCHESTRATOR_CODEHASH_CANDIDATE, "impl codehash off-pin");
        assertEq(
            setDeployer.codehash,
            LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CODEHASH_CANDIDATE,
            "deployer codehash off-pin"
        );
        UpgradeableBeacon beacon =
            UpgradeableBeacon(address(ST0xOrchestratorBeaconSetDeployer(setDeployer).iOrchestratorBeacon()));
        assertEq(beacon.implementation(), orchestrator, "beacon not pointing at the impl pin");
        assertEq(beacon.owner(), LibProdDeployV4.BEACON_INITIAL_OWNER, "beacon owner is not the initial owner");
    }

    /// @notice `run()` covers every chain that carries production tokens, so
    /// one dispatch is the whole rollout. Pins the list rather than the loop
    /// body, which the per-chain tests below exercise.
    function testNetworksCoversEveryProductionChain() external {
        string[] memory nets = new DeployOrchestratorHarness().callNetworks();
        assertEq(nets.length, 3);
        assertEq(nets[0], LibRainDeploy.BASE);
        assertEq(nets[1], LibStoxDeployNetworks.ETHEREUM);
        assertEq(nets[2], LibStoxDeployNetworks.HYPEREVM);
    }

    /// @notice A chain outside the allowlist refuses at pre-flight — the
    /// chain's governance timelock is resolved before anything else, so a
    /// chain with no timelock pin cannot reach the broadcast machinery at
    /// all. Driven on the local EVM (chainid 31337), which is exactly such a
    /// chain.
    function testDeployRefusesUnsupportedChain() external {
        DeployOrchestratorHarness harness = new DeployOrchestratorHarness();
        vm.expectRevert(abi.encodeWithSelector(UnsupportedChainForGovernanceTimelock.selector, uint256(31337)));
        harness.callDeployOnActiveChain();
    }

    /// @notice The deploy lands both singletons at their candidate pins on
    /// Base.
    function testDeploysOnBaseFork() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        deployOnSelectedFork();
    }

    /// @notice The deploy lands both singletons at their candidate pins on
    /// Ethereum.
    function testDeploysOnEthereumFork() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        deployOnSelectedFork();
    }

    /// @notice The deploy lands both singletons at their candidate pins on
    /// HyperEVM.
    function testDeploysOnHyperevmFork() external {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        deployOnSelectedFork();
    }

    /// @notice A chain that already carries both singletons is
    /// codehash-asserted and skipped rather than redeployed or reverted —
    /// the property that makes a re-dispatch a safe no-op and lets a partial
    /// rollout finish in one run.
    function testSkipsAChainThatIsAlreadyDeployed() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        (address firstOrchestrator, address firstSetDeployer) = deployOnSelectedFork();

        // Second pass over the same chain: no revert, same addresses.
        (address secondOrchestrator, address secondSetDeployer) = deployOnSelectedFork();
        assertEq(secondOrchestrator, firstOrchestrator, "a re-run must not move the impl");
        assertEq(secondSetDeployer, firstSetDeployer, "a re-run must not move the deployer");
    }

    /// @notice A partial rollout — implementation landed, set deployer not —
    /// finishes on the next pass: the deployed pin is codehash-asserted and
    /// skipped, the missing one is deployed. The partial state is simulated
    /// by etching the candidate runtime at the impl pin (as if a prior
    /// dispatch landed it) rather than by stripping a deployed contract,
    /// whose leftover nonce and already-created beacon would make a CREATE2
    /// re-deploy collide in a way no real partial rollout does.
    function testFinishesAPartialRollout() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        vm.etch(LibProdDeployV4.ST0X_ORCHESTRATOR_CANDIDATE, LibProdDeployV4.ST0X_ORCHESTRATOR_RUNTIME_CODE_CANDIDATE);

        (, address setDeployer) = deployOnSelectedFork();
        assertGt(setDeployer.code.length, 0, "set deployer must be deployed on the finishing pass");
    }

    /// @notice Pre-flight refuses a pin that carries code with a codehash
    /// other than the candidate pin — a ref/deployment mismatch is a
    /// contradiction to surface, never a state to deploy over.
    function testRejectsCodehashDriftAtImplPin() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address impl = LibProdDeployV4.ST0X_ORCHESTRATOR_CANDIDATE;
        bytes memory bogusCode = hex"60016000526001601ff3";
        vm.etch(impl, bogusCode);
        DeployOrchestratorHarness harness = new DeployOrchestratorHarness();
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployedCodehashMismatch.selector,
                impl,
                LibProdDeployV4.ST0X_ORCHESTRATOR_CODEHASH_CANDIDATE,
                keccak256(bogusCode)
            )
        );
        harness.callDeployOnActiveChain();
    }

    /// @notice Pre-flight refuses codehash drift at the set deployer's pin on
    /// the same grounds.
    function testRejectsCodehashDriftAtSetDeployerPin() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address setDeployer = LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CANDIDATE;
        bytes memory bogusCode = hex"60016000526001601ff3";
        vm.etch(setDeployer, bogusCode);
        DeployOrchestratorHarness harness = new DeployOrchestratorHarness();
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployedCodehashMismatch.selector,
                setDeployer,
                LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CODEHASH_CANDIDATE,
                keccak256(bogusCode)
            )
        );
        harness.callDeployOnActiveChain();
    }

    /// @notice Pre-flight refuses a missing Zoltu factory — nothing may be
    /// deployed without the canonical machinery.
    function testRejectsMissingZoltuFactory() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        vm.etch(LibRainDeploy.ZOLTU_FACTORY, "");
        DeployOrchestratorHarness harness = new DeployOrchestratorHarness();
        vm.expectRevert(abi.encodeWithSelector(ZoltuFactoryNotDeployed.selector, LibRainDeploy.ZOLTU_FACTORY));
        harness.callDeployOnActiveChain();
    }

    /// @notice Pre-flight refuses a Zoltu factory whose codehash drifts from
    /// the rain-deploy pin — whatever lives there is not the canonical
    /// factory.
    function testRejectsZoltuFactoryCodehashDrift() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        bytes memory bogusCode = hex"60016000526001601ff3";
        vm.etch(LibRainDeploy.ZOLTU_FACTORY, bogusCode);
        DeployOrchestratorHarness harness = new DeployOrchestratorHarness();
        vm.expectRevert(
            abi.encodeWithSelector(
                ZoltuFactoryCodehashMismatch.selector,
                LibRainDeploy.ZOLTU_FACTORY,
                LibRainDeploy.ZOLTU_FACTORY_CODEHASH,
                keccak256(bogusCode)
            )
        );
        harness.callDeployOnActiveChain();
    }

    /// @notice The post-state owner check accepts the two recognised owners
    /// — the pinned initial owner (fresh deploy) and the chain's governance
    /// timelock (post-migration) — and refuses anything else.
    function testAssertPostStateOwnerAllowlist() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        (address orchestrator, address setDeployer) = deployOnSelectedFork();
        DeployOrchestratorHarness harness = new DeployOrchestratorHarness();
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        UpgradeableBeacon beacon =
            UpgradeableBeacon(address(ST0xOrchestratorBeaconSetDeployer(setDeployer).iOrchestratorBeacon()));

        // Fresh deploy: initial owner passes.
        harness.callAssertPostState(orchestrator, setDeployer, timelock);

        // Ownership migrated to the chain's governance timelock: passes.
        vm.prank(LibProdDeployV4.BEACON_INITIAL_OWNER);
        beacon.transferOwnership(timelock);
        harness.callAssertPostState(orchestrator, setDeployer, timelock);

        // Ownership moved anywhere else: refused.
        address stranger = makeAddr("stranger");
        vm.prank(timelock);
        beacon.transferOwnership(stranger);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedBeaconOwner.selector, address(beacon), stranger));
        harness.callAssertPostState(orchestrator, setDeployer, timelock);
    }
}

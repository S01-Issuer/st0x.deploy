// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/UpgradeableBeacon.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {ST0xOrchestratorBeaconSetDeployer} from "../src/concrete/deploy/ST0xOrchestratorBeaconSetDeployer.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibStoxDeployNetworks} from "../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @notice The canonical Zoltu deterministic-deployment factory is not
/// deployed on this network. Without it the pinned address is unreachable.
/// @param factory The pinned factory address with no code.
error ZoltuFactoryNotDeployed(address factory);

/// @notice The Zoltu factory's runtime codehash does not match the
/// rain-deploy pin. The contract at the pinned address is not the canonical
/// factory, so nothing may be deployed through it.
/// @param factory The factory address inspected.
/// @param expected The pinned factory codehash.
/// @param actual The codehash observed on-chain.
error ZoltuFactoryCodehashMismatch(address factory, bytes32 expected, bytes32 actual);

/// @notice An orchestrator pin already carries code, but its runtime codehash
/// does not match the candidate pin this script was compiled with. Either the
/// dispatch checked out a ref whose candidate snapshot differs from the one
/// that deployed the chain, or something else entirely lives at the pin.
/// Never a state to deploy over — the Zoltu address is a pure function of the
/// creation code, so a codehash mismatch at the pinned address is a
/// contradiction to surface, not to route around.
/// @param target The pinned address inspected.
/// @param expected The candidate codehash pin.
/// @param actual The codehash observed on-chain.
error DeployedCodehashMismatch(address target, bytes32 expected, bytes32 actual);

/// @notice The address the Zoltu factory returned does not match the
/// candidate pin. Should be unreachable behind the factory codehash guard —
/// tripping means the generated pointer snapshot has drifted from the
/// creation bytecode actually shipped.
/// @param expected The pinned candidate address.
/// @param actual The address the factory deployed to.
error DeployedAddressMismatch(address expected, address actual);

/// @notice The beacon the set deployer constructed does not point at the
/// pinned orchestrator implementation.
/// @param beacon The beacon inspected.
/// @param expected The pinned orchestrator implementation.
/// @param actual The implementation the beacon points at.
error BeaconImplementationMismatch(address beacon, address expected, address actual);

/// @notice The orchestrator beacon's owner is neither the pinned initial
/// owner multisig nor the chain's governance timelock. Ownership has moved
/// somewhere this script does not recognise.
/// @param beacon The beacon inspected.
/// @param owner The owner observed on-chain.
error UnexpectedBeaconOwner(address beacon, address owner);

/// @title DeployOrchestrator
/// @notice **PENDING.** Broadcast script that deploys the two orchestrator
/// Zoltu singletons on every production chain in a single dispatch:
///
///   1. `ST0xOrchestrator` — the orchestrator implementation
///      (`_disableInitializers` in the constructor; only ever used behind a
///      beacon proxy).
///   2. `ST0xOrchestratorBeaconSetDeployer` — whose constructor creates the
///      shared `UpgradeableBeacon` pointing at the implementation, owned by
///      `LibProdDeployV4.BEACON_INITIAL_OWNER`. Deployed second: the beacon
///      constructor refuses a code-less implementation.
///
/// Both ship the CANDIDATE creation bytecode stored in the checked-out
/// commit's generated pointer snapshot (`LibProdDeployV4.*_CANDIDATE`) — the
/// orchestrator has no frozen numbered snapshot yet (it postdates the audited
/// 0.1.1 set `script/DeployProdV4_0_1_1.sol` ships), and
/// `testCandidateSelfConsistent` pins the candidate snapshot to current
/// source, so a dispatch deploys exactly what the dispatched ref compiles to.
/// Dispatch from the intended release ref, and re-dispatch from the SAME ref:
/// pre-flight asserts any already-deployed pin against this compile's
/// candidate codehash, so a later ref whose candidate has drifted refuses
/// rather than reporting a stale deployment as current.
///
/// The Zoltu deploy is deterministic and idempotent per chain: a chain that
/// already carries a contract is codehash-asserted and skipped, never
/// redeployed, so a re-dispatch is a safe no-op and a partial rollout
/// finishes in one run. One dispatch covers every chain in `networks()`
/// (Base, Ethereum, HyperEVM) regardless of the workflow's selected network.
///
/// This script does NOT create the orchestrator proxy instance
/// (`ST0xOrchestratorBeaconSetDeployer.deploy(owner)`): the orchestrator's
/// vault-logic version lock makes `initialize` refuse until the production
/// vault + receipt beacons point at the `LibProdDeployCurrent`
/// implementations this source was built against, so instance creation is a
/// separate, later operational step sequenced with the vault-logic rollout.
///
/// Dispatched via `.github/workflows/manual-broadcast.yaml` with
/// `script = 20260817-deploy-orchestrator`, broadcasting as the CI deploy
/// key (`secrets.PRIVATE_KEY`). The deploy key is never granted anything:
/// both contracts are constructor-configured, and the beacon's owner is
/// baked in as the owner multisig.
contract DeployOrchestrator is Script {
    /// @notice Where `run()` writes the per-chain deployed addresses and
    /// contract paths, so a verification step can target every chain without
    /// re-deriving them — including on a re-dispatch, where every chain is
    /// skipped and no broadcast artifact exists to read them from.
    string internal constant DEPLOYMENTS_PATH = "out/20260817-orchestrator-deployments.json";

    /// @notice Fully qualified source path of the orchestrator
    /// implementation, as the verification step passes to
    /// `forge verify-contract`.
    string internal constant ORCHESTRATOR_CONTRACT_PATH = "src/concrete/ST0xOrchestrator.sol:ST0xOrchestrator";

    /// @notice Fully qualified source path of the beacon-set deployer.
    string internal constant SET_DEPLOYER_CONTRACT_PATH =
        "src/concrete/deploy/ST0xOrchestratorBeaconSetDeployer.sol:ST0xOrchestratorBeaconSetDeployer";

    /// @notice Every chain the orchestrator singletons are deployed to, in a
    /// fixed order. One dispatch covers all of them: the deploy is
    /// deterministic and idempotent per chain, so a chain that already
    /// carries the contracts is verified and skipped rather than redeployed.
    /// @return nets The network names, matching `foundry.toml`'s
    /// `[rpc_endpoints]` aliases.
    function networks() internal pure returns (string[] memory nets) {
        nets = new string[](3);
        nets[0] = LibRainDeploy.BASE;
        nets[1] = LibStoxDeployNetworks.ETHEREUM;
        nets[2] = LibStoxDeployNetworks.HYPEREVM;
    }

    /// @notice Deploy the orchestrator singletons across every chain in
    /// `networks()` in a single dispatch, skipping any chain that already
    /// carries them, then write the verification manifest.
    function run() external {
        string[] memory nets = networks();
        string memory manifest = "";
        for (uint256 i = 0; i < nets.length; i++) {
            // The fork id is unused; bind it so the unused-return lint stays
            // satisfied, matching `LibRainDeploy.deployToNetworks`.
            uint256 forkId = vm.createSelectFork(nets[i]);
            (forkId);
            console2.log("==== NETWORK:", nets[i]);
            (address orchestrator, address setDeployer) = _deployOnActiveChain();
            manifest = string.concat(
                manifest,
                i == 0 ? "" : ",",
                manifestEntry(nets[i], orchestrator, ORCHESTRATOR_CONTRACT_PATH),
                ",",
                manifestEntry(nets[i], setDeployer, SET_DEPLOYER_CONTRACT_PATH)
            );
        }

        vm.writeFile(DEPLOYMENTS_PATH, string.concat("[", manifest, "]"));
        console2.log("Deployments manifest:", DEPLOYMENTS_PATH);
    }

    /// @notice One manifest entry for the verification step: which contract
    /// landed where, on which chain.
    /// @param network The active chain's `foundry.toml` rpc alias.
    /// @param deployed The deployed (or skipped-as-already-deployed) address.
    /// @param contractPath The fully qualified source path to verify against.
    /// @return entry The JSON object, unseparated.
    function manifestEntry(string memory network, address deployed, string memory contractPath)
        internal
        view
        returns (string memory entry)
    {
        entry = string.concat(
            "{\"network\":\"",
            network,
            "\",\"chainId\":",
            vm.toString(block.chainid),
            ",\"address\":\"",
            vm.toString(deployed),
            "\",\"contract\":\"",
            contractPath,
            "\"}"
        );
    }

    /// @notice Deploy (or codehash-assert and skip) both singletons on
    /// whichever chain is currently selected. Pre-flight covers the chain
    /// allowlist, the state of anything already at the pins, and the Zoltu
    /// factory; post-state proves both pins carry the candidate runtime and
    /// the beacon is wired to the pinned implementation under a recognised
    /// owner.
    /// @return orchestrator The orchestrator implementation's pinned address.
    /// @return setDeployer The beacon-set deployer's pinned address.
    function _deployOnActiveChain() internal returns (address orchestrator, address setDeployer) {
        // Chain allowlist: resolving the chain's governance timelock reverts
        // `UnsupportedChainForGovernanceTimelock` on any chain outside the
        // production set, and the resolved address feeds the post-state
        // beacon-owner check (ownership may legitimately have been migrated
        // from the initial owner multisig to the timelock).
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);

        orchestrator = LibProdDeployV4.ST0X_ORCHESTRATOR_CANDIDATE;
        setDeployer = LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CANDIDATE;

        bool needOrchestrator = _needsDeploy(orchestrator, LibProdDeployV4.ST0X_ORCHESTRATOR_CODEHASH_CANDIDATE);
        bool needSetDeployer =
            _needsDeploy(setDeployer, LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CODEHASH_CANDIDATE);

        if (needOrchestrator || needSetDeployer) {
            // The canonical Zoltu factory is deployed with the pinned
            // codehash. A missing or replaced factory would either revert or
            // deploy through attacker-controlled machinery.
            address factory = LibRainDeploy.ZOLTU_FACTORY;
            if (factory.code.length == 0) revert ZoltuFactoryNotDeployed(factory);
            bytes32 factoryCodehash = factory.codehash;
            if (factoryCodehash != LibRainDeploy.ZOLTU_FACTORY_CODEHASH) {
                revert ZoltuFactoryCodehashMismatch(factory, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, factoryCodehash);
            }

            vm.startBroadcast();

            // Implementation first: the set deployer's constructor creates an
            // `UpgradeableBeacon` over it, and OZ's beacon constructor
            // refuses an implementation with no code.
            if (needOrchestrator) {
                address deployed = LibRainDeploy.deployZoltu(LibProdDeployV4.ST0X_ORCHESTRATOR_CREATION_CODE_CANDIDATE);
                if (deployed != orchestrator) revert DeployedAddressMismatch(orchestrator, deployed);
            } else {
                console2.log(" - Orchestrator impl already deployed, skipping:", vm.toString(orchestrator));
            }

            if (needSetDeployer) {
                address deployed = LibRainDeploy.deployZoltu(
                    LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CREATION_CODE_CANDIDATE
                );
                if (deployed != setDeployer) revert DeployedAddressMismatch(setDeployer, deployed);
            } else {
                console2.log(" - Beacon-set deployer already deployed, skipping:", vm.toString(setDeployer));
            }

            vm.stopBroadcast();
        } else {
            console2.log(" - Both singletons already deployed, skipping chain");
        }

        _assertPostState(orchestrator, setDeployer, timelock);

        console2.log("==== ORCHESTRATOR SINGLETONS ====");
        console2.log("Chain:", block.chainid);
        console2.log("Orchestrator impl:", vm.toString(orchestrator));
        console2.log("Beacon-set deployer:", vm.toString(setDeployer));
        console2.log(
            "Beacon:", vm.toString(address(ST0xOrchestratorBeaconSetDeployer(setDeployer).iOrchestratorBeacon()))
        );
        console2.log("=================================");
    }

    /// @notice Whether `target` still needs its Zoltu deploy. No code means
    /// yes; code with the pinned candidate codehash means no (idempotent
    /// skip); code with any other codehash is a contradiction and reverts.
    /// @param target The pinned candidate address.
    /// @param expectedCodehash The pinned candidate codehash.
    /// @return needsDeploy True when nothing is deployed at `target` yet.
    function _needsDeploy(address target, bytes32 expectedCodehash) internal view returns (bool needsDeploy) {
        if (target.code.length == 0) {
            return true;
        }
        bytes32 actual = target.codehash;
        if (actual != expectedCodehash) {
            revert DeployedCodehashMismatch(target, expectedCodehash, actual);
        }
        return false;
    }

    /// @notice Post-state assertion invoked after the deploy-or-skip pass:
    /// both pins carry the candidate runtime, the set deployer's beacon
    /// points at the pinned implementation, and the beacon's owner is either
    /// the pinned initial owner multisig or the chain's governance timelock
    /// (where ownership migrates post-deploy). Split from the deploy step so
    /// tests can drive it against perturbed state.
    /// @param orchestrator The orchestrator implementation's pinned address.
    /// @param setDeployer The beacon-set deployer's pinned address.
    /// @param timelock The active chain's governance timelock.
    function _assertPostState(address orchestrator, address setDeployer, address timelock) internal view {
        bytes32 orchestratorCodehash = orchestrator.codehash;
        if (orchestratorCodehash != LibProdDeployV4.ST0X_ORCHESTRATOR_CODEHASH_CANDIDATE) {
            revert DeployedCodehashMismatch(
                orchestrator, LibProdDeployV4.ST0X_ORCHESTRATOR_CODEHASH_CANDIDATE, orchestratorCodehash
            );
        }
        bytes32 setDeployerCodehash = setDeployer.codehash;
        if (setDeployerCodehash != LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CODEHASH_CANDIDATE) {
            revert DeployedCodehashMismatch(
                setDeployer,
                LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CODEHASH_CANDIDATE,
                setDeployerCodehash
            );
        }

        UpgradeableBeacon beacon =
            UpgradeableBeacon(address(ST0xOrchestratorBeaconSetDeployer(setDeployer).iOrchestratorBeacon()));
        address implementation = beacon.implementation();
        if (implementation != orchestrator) {
            revert BeaconImplementationMismatch(address(beacon), orchestrator, implementation);
        }
        address owner = beacon.owner();
        if (owner != LibProdDeployV4.BEACON_INITIAL_OWNER && owner != timelock) {
            revert UnexpectedBeaconOwner(address(beacon), owner);
        }
    }
}

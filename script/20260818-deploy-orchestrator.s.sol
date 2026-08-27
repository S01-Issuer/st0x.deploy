// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibOrchestratorInvariants} from "../src/lib/LibOrchestratorInvariants.sol";
import {IST0xOrchestratorBeaconSetDeployerV1} from "../src/interface/IST0xOrchestratorBeaconSetDeployerV1.sol";

/// @notice Pre-flight failed: a contract of the audited 0.1.30 orchestrator
/// closure has no runtime code at its pinned address on the active chain.
/// Ship the closure first via `manual-sol-artifacts-0-1-30.yaml`.
/// @param pinned The pinned closure address that is missing.
error ClosureNotDeployed(address pinned);

/// @notice Pre-flight failed: a closure contract's runtime codehash does not
/// match its 0.1.30 pin — something other than the audited bytecode sits at
/// the pinned address.
/// @param pinned The pinned closure address inspected.
/// @param expected The pinned 0.1.30 codehash.
/// @param actual The codehash read from the chain.
error ClosureCodehashMismatch(address pinned, bytes32 expected, bytes32 actual);

/// @notice The pinned orchestrator instance already has code on this chain —
/// the production instance exists and there is nothing to deploy. This is
/// also what makes a re-dispatch a refusal rather than a duplicate.
/// @param instance The pinned instance address.
error OrchestratorAlreadyDeployed(address instance);

/// @notice The beacon-set deployer's account nonce is not the fresh-deploy
/// value, yet the pinned instance has no code. Someone has driven the
/// deployer onto a state this script does not understand (an unpinned
/// instance, or worse) — resolve manually rather than deploying a second
/// instance at an unpinned address.
/// @param setDeployer The beacon-set deployer inspected.
/// @param nonce The account nonce read from the chain.
error UnexpectedSetDeployerNonce(address setDeployer, uint64 nonce);

/// @notice `deploy()` returned an address other than the pinned instance.
/// The pin's nonce-2 derivation and the live deploy disagree — nothing about
/// the deployed contract should be trusted.
/// @param expected The pinned instance address.
/// @param actual The address `deploy()` returned.
error InstanceAddressMismatch(address expected, address actual);

/// @notice The CI deploy key ended up holding `DEFAULT_ADMIN_ROLE` on the
/// deployed instance. `deploy(safe)` grants the Safe alone, so this firing
/// means the instance was initialised with the wrong owner.
/// @param instance The orchestrator instance inspected.
/// @param deployer The deploy key that must NOT hold the role.
error DeployKeyHoldsAdmin(address instance, address deployer);

/// @title DeployOrchestrator
/// @notice **PENDING.** Deploys the production `ST0xOrchestrator` instance on
/// whichever chain this is dispatched against and lands its
/// `DEFAULT_ADMIN_ROLE` on that chain's token-owner Safe — one deploy-key
/// broadcast, no Safe signature.
///
/// @dev Dispatch via `Actions → manual-broadcast` with
/// `script = 20260818-deploy-orchestrator` and `network` set to the target
/// chain (`base` / `ethereum` / `hyperevm`). One dispatch covers one chain.
/// Pre-requisite per chain: the audited 0.1.30 orchestrator closure must be
/// live (`manual-sol-artifacts-0-1-30.yaml`) — pre-flight enforces it by
/// codehash, and `initialize`'s vault-logic version lock would revert the
/// deploy anyway if the OARV beacon-set deployer were absent.
///
/// Unlike the token deploys (`20260807-deploy-missing-tokens`), no transient
/// deploy-key ownership window exists: token vaults need the deploy key as
/// `initialAdmin` to call the owner-gated `setAuthorizer` before handing
/// ownership to the Safe, but the orchestrator has no owner-gated wiring
/// step, so the Safe is passed straight to `deploy(owner)` and the deploy
/// key never holds `DEFAULT_ADMIN_ROLE` at all (asserted after the deploy).
/// Operational role grants (`MINT_ROLE` / `BURN_ROLE` for the issuance bot's
/// signer) are Safe transactions performed later per the issuance-side
/// onboarding runbook — deliberately not this script's business.
///
/// The instance address is deterministic and pinned UP FRONT
/// (`LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE`): the first
/// `deploy()` is the beacon-set deployer's `CREATE` at account nonce 2, and
/// the deployer itself is a Zoltu deploy, so the same instance address lands
/// on every chain. The nonce guard refuses to broadcast against a deployer
/// that has already served a `deploy()` — the pin, not event discovery, is
/// the source of truth (`deploy` is permissionless, so an attacker can emit
/// lookalike `Deployment` events; see the interface's event NatSpec).
contract DeployOrchestrator is Script {
    /// @notice Assert one closure contract is live at its pin with the
    /// audited 0.1.30 codehash.
    /// @param pinned The pinned closure address.
    /// @param codehash The pinned 0.1.30 codehash.
    function _assertClosureContract(address pinned, bytes32 codehash) internal view {
        if (pinned.code.length == 0) {
            revert ClosureNotDeployed(pinned);
        }
        if (pinned.codehash != codehash) {
            revert ClosureCodehashMismatch(pinned, codehash, pinned.codehash);
        }
    }

    /// @notice Assert the full audited 0.1.30 orchestrator closure is live on
    /// the active chain, by codehash, in dependency order.
    function _assertClosureReady() internal view {
        _assertClosureContract(
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_30,
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CODEHASH_0_1_30
        );
        _assertClosureContract(LibProdDeployV4.STOX_RECEIPT_0_1_30, LibProdDeployV4.STOX_RECEIPT_CODEHASH_0_1_30);
        _assertClosureContract(
            LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30, LibProdDeployV4.STOX_RECEIPT_VAULT_CODEHASH_0_1_30
        );
        _assertClosureContract(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_30,
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH_0_1_30
        );
        _assertClosureContract(
            LibProdDeployV4.ST0X_ORCHESTRATOR_0_1_30, LibProdDeployV4.ST0X_ORCHESTRATOR_CODEHASH_0_1_30
        );
        _assertClosureContract(
            LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30,
            LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CODEHASH_0_1_30
        );
    }

    /// @notice Assert the beacon-set deployer is in the fresh-deploy state
    /// the instance pin's nonce-2 derivation assumes: no code at the pinned
    /// instance and the deployer's account nonce still at 2 (its constructor
    /// `CREATE`d the beacon at nonce 1).
    /// @param setDeployer The beacon-set deployer to inspect.
    function _assertNoInstanceYet(address setDeployer) internal view {
        address instance = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;
        if (instance.code.length != 0) {
            revert OrchestratorAlreadyDeployed(instance);
        }
        uint64 nonce = vm.getNonce(setDeployer);
        if (nonce != 2) {
            revert UnexpectedSetDeployerNonce(setDeployer, nonce);
        }
    }

    /// @notice Assert the deployed instance landed exactly as pinned: at the
    /// pinned address, beacon set intact, Safe holding `DEFAULT_ADMIN_ROLE`,
    /// vault-logic lock passing, and the deploy key holding nothing.
    /// @dev Public so the failure modes can be driven directly from a test —
    /// an assertion reachable only from inside a broadcast cannot be shown to
    /// fire. Mirrors `20260807-deploy-missing-tokens.assertHandoffLanded`.
    /// @param instance The address `deploy()` returned.
    /// @param safe The chain's token-owner Safe that must hold admin.
    /// @param deployer The deploy key that must hold nothing.
    function assertDeployLanded(address instance, address safe, address deployer) public view {
        if (instance != LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE) {
            revert InstanceAddressMismatch(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE, instance);
        }
        LibOrchestratorInvariants.assertBeaconSet();
        LibOrchestratorInvariants.assertInstance(safe);
        if (IAccessControl(instance).hasRole(bytes32(0), deployer)) {
            revert DeployKeyHoldsAdmin(instance, deployer);
        }
    }

    /// @notice Deploy the production orchestrator instance on the active
    /// chain, owned by its token-owner Safe, and assert the pinned end state.
    function run() external {
        _assertClosureReady();
        LibOrchestratorInvariants.assertBeaconSet();
        address safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);

        address setDeployer = LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30;
        _assertNoInstanceYet(setDeployer);

        vm.startBroadcast();

        // Deployer identity — inside `vm.startBroadcast()` msg.sender
        // resolves to the broadcast address (`--private-key` in production).
        address deployer = msg.sender;

        console2.log("Deploying ST0xOrchestrator instance on chain id", block.chainid);
        console2.log("beacon-set deployer:", setDeployer);
        console2.log("deploy key (holds no role):", deployer);
        console2.log("DEFAULT_ADMIN_ROLE (token-owner Safe):", safe);

        address instance = IST0xOrchestratorBeaconSetDeployerV1(setDeployer).deploy(safe);
        assertDeployLanded(instance, safe, deployer);

        vm.stopBroadcast();

        console2.log("==== ORCHESTRATOR DEPLOYED ====");
        console2.log("instance:", vm.toString(instance));
        console2.log("Admin is the token-owner Safe; the deploy key holds no role.");
    }
}

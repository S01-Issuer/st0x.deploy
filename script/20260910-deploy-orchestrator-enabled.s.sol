// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../src/lib/LibBeaconInvariants.sol";
import {LibClosureInvariants} from "../src/lib/LibClosureInvariants.sol";
import {LibOrchestratorInvariants} from "../src/lib/LibOrchestratorInvariants.sol";
import {IST0xOrchestratorBeaconSetDeployerV1} from "../src/interface/IST0xOrchestratorBeaconSetDeployerV1.sol";
import {
    OrchestratorAlreadyDeployed,
    UnexpectedSetDeployerNonce,
    InstanceAddressMismatch
} from "./20260818-deploy-orchestrator.s.sol";
import {FleetNotUpgraded} from "./20260831-enable-orchestrator-roles.s.sol";

/// @notice The CI deploy key still holds a role on the deployed instance
/// after the hand-off. The deploy key is the transient admin ONLY for the
/// grants inside this broadcast; anything left on it afterwards means the
/// hand-off did not land and the instance is not in the pinned end state.
/// @param instance The orchestrator instance inspected.
/// @param role The role the deploy key unexpectedly holds.
/// @param deployer The deploy key that must hold nothing.
error DeployKeyHoldsRole(address instance, bytes32 role, address deployer);

/// @notice The service signer does not hold one of the orchestrator's
/// operational roles after the broadcast — the enabled end state this
/// script exists to land.
/// @param instance The orchestrator instance inspected.
/// @param role The missing operational role.
error SignerMissingOrchestratorRole(address instance, bytes32 role);

/// @title DeployOrchestratorEnabled
/// @notice Deploys the production `ST0xOrchestrator` instance on a freshly
/// bootstrapped chain AND lands it in the enabled end state — the service
/// signer holding `MINT_ROLE` / `BURN_ROLE` on it, the chain's token-owner
/// Safe holding `DEFAULT_ADMIN_ROLE` — in one deploy-key broadcast, with no
/// Safe signature.
///
/// The successor of `20260818-deploy-orchestrator` +
/// `20260831-enable-orchestrator-roles` for chains that bootstrap AFTER the
/// orchestrator shipped. On Base / Ethereum / HyperEVM the instance was
/// deployed with the Safe as admin from birth, so the operational grants
/// had to be a Safe-signed bundle. On a fresh chain the same end state is
/// reachable through the deploy-then-hand-off ceremony the V4 authoriser
/// clone already uses (`20260619-deploy-v4-authoriser-clone`): the deploy
/// key is passed to `deploy(owner)` as the transient `DEFAULT_ADMIN_ROLE`
/// holder, performs the two signer grants, grants admin to the Safe, and
/// renounces its own admin — all inside one broadcast, with the post-state
/// proving the key holds nothing afterwards.
///
/// The instance address is unchanged by the ceremony: it is the beacon-set
/// deployer's `CREATE` at account nonce 2, a function of the (Zoltu) deployer
/// alone, never of the `owner` argument — so the same
/// `LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE` pin lands on every
/// chain, and the authoriser ceremony can (and does) grant that address its
/// vault roles before the instance exists.
///
/// The authoriser half of the enable bundle needs no action here: the V4
/// authoriser ceremony mirrors the canonical grant map
/// (`LibAuthoriserInvariants.expectedGrants`), which carries the
/// orchestrator's `DEPOSIT` / `WITHDRAW` rows, so on a fresh chain the
/// orchestrator is vault-authorised from the ceremony. Pre-flight asserts
/// the full map holds, and the post-state re-asserts it, so nothing about
/// the authoriser moves in this broadcast.
///
/// @dev Dispatch via `Actions → manual-broadcast` with
/// `script = 20260910-deploy-orchestrator-enabled` and `network` set to the
/// target chain. One dispatch covers one chain. Pre-requisites per chain, in
/// order: the audited 0.1.30 closure live (`manual-sol-artifacts-0-1-30`);
/// the V4 authoriser clone deployed AND its pin hydrated; the token beacons
/// upgraded to 0.1.30 and Safe-owned
/// (`20260909-upgrade-and-migrate-token-beacons`). Pre-flight enforces each
/// by codehash / live read, refuses a chain whose instance already exists
/// (`OrchestratorAlreadyDeployed` — the existing chains keep their
/// Safe-signed history and are never re-run through this script), and
/// carries the RAI-2125 interlock: the fleet must serve 0.1.30 before the
/// orchestrator gains a mint path, which the orchestrator's own vault-logic
/// lock cannot see on the in-use beacons.
///
/// After this script, `20260831-enable-orchestrator-roles` refuses the
/// chain (`OrchestratorRolesAlreadyEnabled`) — every item it would author
/// already holds — and the chain is at parity with the three existing
/// chains' executed enable bundles.
contract DeployOrchestratorEnabled is Script {
    /// @notice The service signer that mints/burns THROUGH the orchestrator.
    address internal constant SERVICE_SIGNER = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;

    /// @notice The orchestrator's operational roles (audited 0.1.30 source).
    bytes32 internal constant ORCHESTRATOR_MINT_ROLE = keccak256("MINT");
    bytes32 internal constant ORCHESTRATOR_BURN_ROLE = keccak256("BURN");
    bytes32 internal constant ORCHESTRATOR_EMERGENCY_ROLE = keccak256("EMERGENCY");

    /// @notice Assert the full audited 0.1.30 orchestrator closure is live on
    /// the active chain, by codehash, in dependency order. Mirrors
    /// `20260818-deploy-orchestrator`.
    function _assertClosureReady() internal view {
        LibClosureInvariants.assertClosureContract(
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_30,
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CODEHASH_0_1_30
        );
        LibClosureInvariants.assertClosureContract(
            LibProdDeployV4.STOX_RECEIPT_0_1_30, LibProdDeployV4.STOX_RECEIPT_CODEHASH_0_1_30
        );
        LibClosureInvariants.assertClosureContract(
            LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30, LibProdDeployV4.STOX_RECEIPT_VAULT_CODEHASH_0_1_30
        );
        LibClosureInvariants.assertClosureContract(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_30,
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH_0_1_30
        );
        LibClosureInvariants.assertClosureContract(
            LibProdDeployV4.ST0X_ORCHESTRATOR_0_1_30, LibProdDeployV4.ST0X_ORCHESTRATOR_CODEHASH_0_1_30
        );
        LibClosureInvariants.assertClosureContract(
            LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30,
            LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CODEHASH_0_1_30
        );
    }

    /// @notice Assert the beacon-set deployer is in the fresh-deploy state
    /// the instance pin's nonce-2 derivation assumes: no code at the pinned
    /// instance and the deployer's account nonce still at 2. Mirrors
    /// `20260818-deploy-orchestrator`.
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

    /// @notice The RAI-2125 interlock: the chain's in-use receipt and
    /// receipt-vault beacons must already serve the audited 0.1.30 impls
    /// before the orchestrator gains a mint path. Mirrors
    /// `20260831-enable-orchestrator-roles`; on a fresh chain this is what
    /// `20260909-upgrade-and-migrate-token-beacons` lands.
    function _assertFleetUpgraded() internal view {
        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        address receiptImpl = IBeacon(beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX]).implementation();
        if (receiptImpl != LibProdDeployV4.STOX_RECEIPT_0_1_30) {
            revert FleetNotUpgraded(
                beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX], LibProdDeployV4.STOX_RECEIPT_0_1_30, receiptImpl
            );
        }
        address vaultImpl = IBeacon(beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX]).implementation();
        if (vaultImpl != LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30) {
            revert FleetNotUpgraded(
                beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX],
                LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30,
                vaultImpl
            );
        }
    }

    /// @notice Assert the enabled end state landed exactly as pinned: the
    /// instance at its pin, beacon set intact, the Safe holding
    /// `DEFAULT_ADMIN_ROLE`, the vault-logic lock passing, the service signer
    /// holding `MINT_ROLE` + `BURN_ROLE`, the deploy key holding NO role,
    /// and the chain's authoriser still on the canonical grant map (which
    /// carries the orchestrator's vault access).
    /// @dev Public so the failure modes can be driven directly from a test —
    /// an assertion reachable only from inside a broadcast cannot be shown to
    /// fire. Mirrors `20260818-deploy-orchestrator.assertDeployLanded` plus
    /// `20260831-enable-orchestrator-roles.assertPostEnableState`.
    /// @param instance The address `deploy()` returned.
    /// @param safe The chain's token-owner Safe that must hold admin.
    /// @param authoriser The chain's V4 authoriser clone.
    /// @param deployer The deploy key that must hold nothing.
    function assertEnabledLanded(address instance, address safe, address authoriser, address deployer) public view {
        if (instance != LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE) {
            revert InstanceAddressMismatch(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE, instance);
        }
        LibOrchestratorInvariants.assertBeaconSet(safe);
        LibOrchestratorInvariants.assertInstance(safe);

        IAccessControl orch = IAccessControl(instance);
        bytes32[4] memory roles =
            [bytes32(0), ORCHESTRATOR_MINT_ROLE, ORCHESTRATOR_BURN_ROLE, ORCHESTRATOR_EMERGENCY_ROLE];
        for (uint256 i = 0; i < roles.length; i++) {
            if (orch.hasRole(roles[i], deployer)) {
                revert DeployKeyHoldsRole(instance, roles[i], deployer);
            }
        }
        if (!orch.hasRole(ORCHESTRATOR_MINT_ROLE, SERVICE_SIGNER)) {
            revert SignerMissingOrchestratorRole(instance, ORCHESTRATOR_MINT_ROLE);
        }
        if (!orch.hasRole(ORCHESTRATOR_BURN_ROLE, SERVICE_SIGNER)) {
            revert SignerMissingOrchestratorRole(instance, ORCHESTRATOR_BURN_ROLE);
        }

        // The authoriser half: untouched by this broadcast, and the
        // canonical map (orchestrator DEPOSIT / WITHDRAW included) holds.
        LibAuthoriserInvariants.assertExpectedGrants(authoriser, safe);
    }

    /// @notice Deploy the production orchestrator instance on the active
    /// chain with the deploy key as transient admin, grant the service
    /// signer its operational roles, hand `DEFAULT_ADMIN_ROLE` to the
    /// token-owner Safe, renounce the deploy key's, and assert the enabled
    /// end state.
    function run() external {
        // --- Pre-flight ---------------------------------------------------

        _assertClosureReady();
        address safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibOrchestratorInvariants.assertBeaconSet(safe);

        address setDeployer = LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30;
        _assertNoInstanceYet(setDeployer);

        _assertFleetUpgraded();

        // The authoriser is live at its hydrated pin and on the canonical
        // map BEFORE the orchestrator exists — the orchestrator's vault
        // access is the ceremony's, not this script's.
        address authoriser = LibAuthoriserInvariants.activeChainAuthoriser();
        LibAuthoriserInvariants.assertExpectedGrants(authoriser, safe);

        // --- Broadcast ----------------------------------------------------

        vm.startBroadcast();

        // Deployer identity — inside `vm.startBroadcast()` msg.sender
        // resolves to the broadcast address (`--private-key` in production).
        address deployer = msg.sender;

        console2.log("Deploying ST0xOrchestrator instance (enabled) on chain id", block.chainid);
        console2.log("beacon-set deployer:", setDeployer);
        console2.log("deploy key (transient admin, holds nothing after):", deployer);
        console2.log("DEFAULT_ADMIN_ROLE hand-off target (token-owner Safe):", safe);
        console2.log("MINT/BURN grantee (service signer):", SERVICE_SIGNER);

        // Step 1: deploy with the deploy key as the transient admin.
        address instance = IST0xOrchestratorBeaconSetDeployerV1(setDeployer).deploy(deployer);
        IAccessControl orch = IAccessControl(instance);

        // Step 2: the operational grants the enable bundle would author.
        orch.grantRole(ORCHESTRATOR_MINT_ROLE, SERVICE_SIGNER);
        orch.grantRole(ORCHESTRATOR_BURN_ROLE, SERVICE_SIGNER);

        // Step 3: hand admin to the Safe, then drop the deploy key's copy.
        orch.grantRole(bytes32(0), safe);
        orch.renounceRole(bytes32(0), deployer);

        assertEnabledLanded(instance, safe, authoriser, deployer);

        vm.stopBroadcast();

        console2.log("==== ORCHESTRATOR DEPLOYED + ENABLED ====");
        console2.log("instance:", vm.toString(instance));
        console2.log("Admin is the token-owner Safe; the service signer holds MINT/BURN; the deploy key holds no role.");
    }
}

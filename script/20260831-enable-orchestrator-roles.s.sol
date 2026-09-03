// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";

import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {IST0xOrchestratorV1} from "../src/interface/IST0xOrchestratorV1.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../src/lib/LibBeaconInvariants.sol";
import {LibOrchestratorInvariants} from "../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeOps, SafeTx} from "../src/lib/LibSafeOps.sol";

/// @notice Dispatched against a chain without a hydrated authoriser pin.
/// @param chainId The active chain id.
error UnsupportedChainForEnable(uint256 chainId);

/// @notice The active chain's V4 authoriser is not ready (unpinned, no code,
/// or the wrong codehash).
/// @param authoriser The authoriser address inspected.
error AuthoriserNotReadyForEnable(address authoriser);

/// @notice The chain's production token beacons do not point at the audited
/// 0.1.30 implementations the orchestrator was built for. The fleet upgrade
/// must execute BEFORE the orchestrator gains vault access — the
/// orchestrator's own vault-logic lock cannot see these beacons (RAI-2125),
/// so this pre-flight is the interlock that rule lives in.
/// @param beacon The production beacon inspected.
/// @param expectedImpl The 0.1.30 implementation it must point at.
/// @param actualImpl The implementation it points at.
error FleetNotUpgraded(address beacon, address expectedImpl, address actualImpl);

/// @notice The Safe does not hold the `_ADMIN` role needed to move an
/// authoriser grant in the bundle.
/// @param adminRole The missing `_ADMIN` role.
error SafeMissingRoleAdminForEnable(bytes32 adminRole);

/// @notice The Safe does not hold `DEFAULT_ADMIN_ROLE` on the orchestrator
/// instance, so it cannot grant the operational roles.
/// @param orchestrator The orchestrator instance inspected.
error SafeNotOrchestratorAdmin(address orchestrator);

/// @notice Every enable item already holds on the active chain — the
/// orchestrator has vault access and the signer holds the orchestrator's
/// operational roles. Nothing left to author; re-dispatch cannot
/// double-execute.
error OrchestratorRolesAlreadyEnabled();

/// @title EnableOrchestratorRoles
/// @notice **PENDING.** Authors the per-chain Safe Tx Builder bundle that
/// ENABLES the orchestrator mint/burn path, as ONE atomic MultiSend:
///
///  1. authoriser `grantRole(DEPOSIT, orchestrator)` and
///     `grantRole(WITHDRAW, orchestrator)` — the orchestrator becomes a
///     vault-authorised principal;
///  2. orchestrator `grantRole(MINT_ROLE, service signer)` and
///     `grantRole(BURN_ROLE, service signer)` — the signer can mint/burn
///     THROUGH the orchestrator (recipient-auth, receipt custody, nonce
///     discipline).
///
/// The signer's DIRECT vault roles are deliberately LEFT IN PLACE: both
/// paths run in parallel for a burn-in window so an off-chain issue with
/// the orchestrator has an immediate fallback. The sibling
/// `20260831-retire-direct-signer-roles` authors the revokes once the
/// orchestrator has proven itself — that split is the point, not an
/// oversight. Also untouched: the signer's `CERTIFY` (the orchestrator has
/// no certify surface) and the Safe's own three direct action roles (the
/// break-glass path).
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20260831-enable-orchestrator-roles` per chain; sign and
/// execute the emitted artifact in the Safe UI. Pre-flight refuses to
/// author until, on the active chain: the 0.1.30 orchestrator instance is
/// live at its pin with the Safe as admin, AND the production token beacons
/// point at the 0.1.30 implementations (`FleetNotUpgraded`) — the
/// orchestrator's own vault-logic lock cannot see the in-use beacons
/// (RAI-2125), so the "fleet upgrade first, roles after" rule is enforced
/// HERE rather than by runbook. Self-scoping: only items not yet live are
/// authored, and a fully-enabled chain refuses
/// (`OrchestratorRolesAlreadyEnabled`).
///
/// The post-execution pin PR ADDS the orchestrator's DEPOSIT/WITHDRAW rows
/// to the authoriser grant map (nothing is removed — the signer's rows
/// stay until the retire script executes) and retires this script's
/// fixtures.
contract EnableOrchestratorRoles is Script {
    /// @notice The service signer whose direct vault access moves behind
    /// the orchestrator.
    address internal constant SERVICE_SIGNER = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;

    /// @notice The orchestrator's operational roles (pinned to the audited
    /// 0.1.30 source: `MINT_ROLE = keccak256("MINT")`,
    /// `BURN_ROLE = keccak256("BURN")`).
    bytes32 internal constant ORCHESTRATOR_MINT_ROLE = keccak256("MINT");
    bytes32 internal constant ORCHESTRATOR_BURN_ROLE = keccak256("BURN");

    /// @notice Signer-visible `meta.name` for the emitted bundle.
    string internal constant BUNDLE_NAME =
        "ST0x enable: orchestrator vault access + service signer MINT/BURN via orchestrator";

    /// @notice Chain-suffixed artifact path — three chains dispatch in one
    /// operational window; a shared path would let one chain's bundle
    /// silently overwrite another's.
    /// @return path The artifact path for the ACTIVE chain.
    function artifactPath() internal view virtual returns (string memory path) {
        path = string.concat("out/20260831-enable-orchestrator-roles-", vm.toString(block.chainid), ".json");
    }

    /// @notice The active chain's hydrated V4 authoriser, asserted deployed
    /// with the shared EIP-1167 codehash.
    /// @return authoriser The validated authoriser address.
    function activeChainAuthoriser() internal view returns (address authoriser) {
        if (block.chainid == LibSafeInvariants.BASE_CHAIN_ID) {
            authoriser = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        } else if (block.chainid == LibSafeInvariants.ETHEREUM_CHAIN_ID) {
            authoriser = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM;
        } else if (block.chainid == LibSafeInvariants.HYPEREVM_CHAIN_ID) {
            authoriser = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM;
        } else {
            revert UnsupportedChainForEnable(block.chainid);
        }
        if (
            authoriser == address(0) || authoriser.code.length == 0
                || authoriser.codehash != LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH
        ) {
            revert AuthoriserNotReadyForEnable(authoriser);
        }
    }

    /// @notice The fleet-upgrade interlock: the active chain's in-use
    /// production receipt + receipt-vault beacons must point at the audited
    /// 0.1.30 implementations the orchestrator was built for. The
    /// orchestrator's own vault-logic lock reads its release set-deployer's
    /// beacons, not these (RAI-2125), so this pre-flight carries the rule.
    function assertFleetUpgraded() internal view {
        // The wrapped-token-vault beacon is not part of the orchestrator's
        // surface and is not gated here.
        address[3] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
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

    /// @notice Pre-flight the principals and self-scope the bundle: one tx
    /// per enable item not yet live on-chain, in the fixed order (grant
    /// orchestrator vault roles, grant signer orchestrator roles). Refuses
    /// when the grant map has drifted, when the Safe lacks an `_ADMIN` it
    /// needs, when it lacks orchestrator admin, or when every item already
    /// holds (`OrchestratorRolesAlreadyEnabled`).
    /// @param authoriser The chain's authoriser clone.
    /// @param orchestrator The orchestrator instance.
    /// @param safeAddr The chain's token-owner Safe.
    /// @return txs The self-scoped enable transactions.
    function authorBundle(address authoriser, address orchestrator, address safeAddr)
        internal
        view
        returns (SafeTx[] memory txs)
    {
        IAccessControl acl = IAccessControl(authoriser);
        IAccessControl orch = IAccessControl(orchestrator);

        // The canonical map must hold exactly before it is mutated — a
        // drifted authoriser never gets the orchestrator granted onto it.
        LibAuthoriserInvariants.assertExpectedGrants(authoriser, safeAddr);

        // The Safe admins both authoriser roles being moved, and the
        // orchestrator's roles via DEFAULT_ADMIN_ROLE.
        if (!acl.hasRole(keccak256("DEPOSIT_ADMIN"), safeAddr)) {
            revert SafeMissingRoleAdminForEnable(keccak256("DEPOSIT_ADMIN"));
        }
        if (!acl.hasRole(keccak256("WITHDRAW_ADMIN"), safeAddr)) {
            revert SafeMissingRoleAdminForEnable(keccak256("WITHDRAW_ADMIN"));
        }
        if (!orch.hasRole(bytes32(0), safeAddr)) {
            revert SafeNotOrchestratorAdmin(orchestrator);
        }

        // Self-scope: author only the items not already live. The signer's
        // direct roles are NOT touched — the retire script owns those.
        SafeTx[] memory candidates = new SafeTx[](4);
        uint256 count = 0;
        if (!acl.hasRole(keccak256("DEPOSIT"), orchestrator)) {
            candidates[count++] = SafeTx({
                to: authoriser,
                value: 0,
                data: abi.encodeCall(IAccessControl.grantRole, (keccak256("DEPOSIT"), orchestrator)),
                operation: 0
            });
        }
        if (!acl.hasRole(keccak256("WITHDRAW"), orchestrator)) {
            candidates[count++] = SafeTx({
                to: authoriser,
                value: 0,
                data: abi.encodeCall(IAccessControl.grantRole, (keccak256("WITHDRAW"), orchestrator)),
                operation: 0
            });
        }
        if (!orch.hasRole(ORCHESTRATOR_MINT_ROLE, SERVICE_SIGNER)) {
            candidates[count++] = SafeTx({
                to: orchestrator,
                value: 0,
                data: abi.encodeCall(IAccessControl.grantRole, (ORCHESTRATOR_MINT_ROLE, SERVICE_SIGNER)),
                operation: 0
            });
        }
        if (!orch.hasRole(ORCHESTRATOR_BURN_ROLE, SERVICE_SIGNER)) {
            candidates[count++] = SafeTx({
                to: orchestrator,
                value: 0,
                data: abi.encodeCall(IAccessControl.grantRole, (ORCHESTRATOR_BURN_ROLE, SERVICE_SIGNER)),
                operation: 0
            });
        }
        if (count == 0) {
            revert OrchestratorRolesAlreadyEnabled();
        }
        txs = new SafeTx[](count);
        for (uint256 i = 0; i < count; i++) {
            txs[i] = candidates[i];
        }
    }

    /// @notice Assert the post-enable state on the active fork: the
    /// orchestrator holds both vault roles, the signer holds both
    /// orchestrator roles AND still holds its direct vault roles — the
    /// parallel burn-in state; `20260831-retire-direct-signer-roles`
    /// removes the direct roles once the orchestrator has proven itself.
    /// Nothing is removed here, so the ENTIRE canonical map must still
    /// hold, and the orchestrator's vault-logic lock must still pass.
    /// @param acl The authoriser's access-control surface.
    /// @param orchestrator The orchestrator instance.
    /// @param safeAddr The chain's token-owner Safe.
    function assertPostEnableState(IAccessControl acl, address orchestrator, address safeAddr) internal view {
        require(
            acl.hasRole(keccak256("DEPOSIT"), orchestrator) && acl.hasRole(keccak256("WITHDRAW"), orchestrator),
            "EnableOrchestratorRoles: orchestrator did not gain vault access"
        );
        IAccessControl orch = IAccessControl(orchestrator);
        require(
            orch.hasRole(ORCHESTRATOR_MINT_ROLE, SERVICE_SIGNER)
                && orch.hasRole(ORCHESTRATOR_BURN_ROLE, SERVICE_SIGNER),
            "EnableOrchestratorRoles: service signer lacks orchestrator MINT/BURN"
        );
        require(
            acl.hasRole(keccak256("DEPOSIT"), SERVICE_SIGNER) && acl.hasRole(keccak256("WITHDRAW"), SERVICE_SIGNER),
            "EnableOrchestratorRoles: the signer's parallel fallback path was disturbed"
        );
        // Nothing is removed: the entire canonical map still holds.
        LibAuthoriserInvariants.assertExpectedGrants(address(acl), safeAddr);
        require(
            IST0xOrchestratorV1(orchestrator).vaultLogicIsExpected(),
            "EnableOrchestratorRoles: orchestrator vault-logic lock does not pass"
        );
    }

    /// @notice Author the enable bundle for the active chain: see the
    /// contract-level flow. Does not broadcast — execution happens via the
    /// Safe UI using the emitted artifact.
    function run() external {
        // --- Pre-flight ---------------------------------------------------

        address safeAddr = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        IGnosisSafe safe = IGnosisSafe(safeAddr);
        address authoriser = activeChainAuthoriser();
        IAccessControl acl = IAccessControl(authoriser);

        // The 0.1.30 orchestrator world must be live at its pins, with the
        // Safe as instance admin...
        LibOrchestratorInvariants.assertBeaconSet(safeAddr);
        LibOrchestratorInvariants.assertInstance(safeAddr);
        address orchestrator = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;

        // ...and the FLEET must already run the 0.1.30 impls — the interlock
        // the orchestrator's own lock cannot provide (RAI-2125).
        assertFleetUpgraded();

        // --- Build the bundle ----------------------------------------------

        SafeTx[] memory txs = authorBundle(authoriser, orchestrator, safeAddr);

        uint256 nonce = safe.nonce();
        bytes32 bundleSafeTxHash = LibSafeOps.computeMultiSendSafeTxHash(safe, txs, nonce);

        // --- Simulate -----------------------------------------------------

        for (uint256 i = 0; i < txs.length; i++) {
            LibSafeOps.simulateExternalCall(safe, txs[i].to, txs[i].data);
        }

        // --- Post-state ---------------------------------------------------

        assertPostEnableState(acl, orchestrator, safeAddr);
        LibSafeInvariants.assertImmutableInvariants(safe);
        LibSafeInvariants.assertThreshold(safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);

        // --- Artifact -----------------------------------------------------

        string memory json = LibSafeOps.emitTxBuilderJson(safeAddr, block.chainid, BUNDLE_NAME, txs);
        vm.writeFile(artifactPath(), json);

        console2.log("==== TX BUILDER JSON BEGIN ====");
        console2.log(json);
        console2.log("==== TX BUILDER JSON END ====");
        console2.log("Bundle MultiSend SafeTxHash:", vm.toString(bundleSafeTxHash));
        console2.log("Nonce:", nonce);
        console2.log("Bundle item count:", txs.length);
        console2.log("Chain:", block.chainid);
        console2.log("Authoriser:", authoriser);
        console2.log("Orchestrator instance:", orchestrator);
        console2.log("Service signer:", SERVICE_SIGNER);

        // --- n+1 reversal proof --------------------------------------------

        // The enable is fully reversible under roles the Safe holds. Prove
        // the reversal path clears the live threshold: revoke the
        // orchestrator's DEPOSIT through the Safe's exec, then re-grant so
        // the fork ends enabled.
        LibSafeOps.simulateNPlus1(
            safe,
            authoriser,
            abi.encodeCall(IAccessControl.revokeRole, (keccak256("DEPOSIT"), orchestrator)),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD
        );
        require(
            !acl.hasRole(keccak256("DEPOSIT"), orchestrator),
            "EnableOrchestratorRoles: n+1 revoke did not remove the role"
        );
        LibSafeOps.simulateExternalCall(
            safe, authoriser, abi.encodeCall(IAccessControl.grantRole, (keccak256("DEPOSIT"), orchestrator))
        );
        console2.log("n+1 reversal check passed: the Safe can disable (and re-enable) under the live threshold");
    }

    /// @notice Signer-side integrity check for a CI-authored enable
    /// artifact, run LOCALLY against a live fork before signing: re-runs the
    /// pre-flight, re-derives the bundle from CURRENT live state, asserts
    /// the artifact at `jsonPath` matches it byte-exactly, and logs the
    /// canonical MultiSend `SafeTxHash` at the live nonce for the Safe-UI
    /// cross-check. Deliberately NOT in the run-script dispatcher: it takes
    /// a local path and runs on the signer's machine.
    /// @param jsonPath Filesystem path to the downloaded Tx Builder JSON.
    function verify(string calldata jsonPath) external view {
        address safeAddr = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        IGnosisSafe safe = IGnosisSafe(safeAddr);
        address authoriser = activeChainAuthoriser();
        LibOrchestratorInvariants.assertBeaconSet(safeAddr);
        LibOrchestratorInvariants.assertInstance(safeAddr);
        assertFleetUpgraded();

        SafeTx[] memory expected =
            authorBundle(authoriser, LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE, safeAddr);
        LibSafeOps.assertParsedTxsMatch(expected, jsonPath);

        uint256 nonce = safe.nonce();
        console2.log("Artifact verified against live state.");
        console2.log(
            "Bundle MultiSend SafeTxHash:", vm.toString(LibSafeOps.computeMultiSendSafeTxHash(safe, expected, nonce))
        );
        console2.log("Nonce:", nonce);
    }
}

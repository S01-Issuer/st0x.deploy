// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";

import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibOrchestratorInvariants} from "../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeOps, SafeTx} from "../src/lib/LibSafeOps.sol";

/// @dev Unix timestamp (2026-10-15T00:00:00Z) by which the retirement must
/// have executed on every chain. Deliberately TWO WEEKS after the
/// fleet/enable deadline: the whole point of the enable/retire split is a
/// burn-in window where the orchestrator path and the signer's direct path
/// run in parallel, so the direct path can serve as an emergency fallback
/// while the orchestrator proves itself off-chain.
uint256 constant RETIRE_DEADLINE = 1_792_022_400;

/// @notice Dispatched against a chain without a hydrated authoriser pin.
/// @param chainId The active chain id.
error UnsupportedChainForRetire(uint256 chainId);

/// @notice The active chain's V4 authoriser is not ready (unpinned, no code,
/// or the wrong codehash).
/// @param authoriser The authoriser address inspected.
error AuthoriserNotReadyForRetire(address authoriser);

/// @notice The orchestrator mint/burn path is not fully enabled on this
/// chain — retiring the signer's direct roles now would leave NO working
/// mint/burn path. Execute `20260831-enable-orchestrator-roles` (and give
/// the orchestrator its burn-in) first.
/// @param holder The principal missing a role.
/// @param role The role it must hold before retirement can be authored.
error OrchestratorPathNotEnabled(address holder, bytes32 role);

/// @notice The Safe does not hold the `_ADMIN` role needed to revoke a
/// grant in the bundle.
/// @param adminRole The missing `_ADMIN` role.
error SafeMissingRoleAdminForRetire(bytes32 adminRole);

/// @notice The signer holds neither direct vault role — the retirement has
/// executed on this chain and a re-dispatch has nothing to author.
error DirectSignerRolesAlreadyRetired();

/// @title RetireDirectSignerRoles
/// @notice **PENDING.** Authors the per-chain Safe Tx Builder bundle that
/// closes the parallel burn-in window opened by
/// `20260831-enable-orchestrator-roles`: revoke the service signer's DIRECT
/// `DEPOSIT` and `WITHDRAW` on the authoriser, leaving the orchestrator as
/// the only mint/burn path the signer can drive. Run this ONLY once the
/// orchestrator has proven itself in production — the split from the
/// enable bundle exists precisely so this step can wait.
///
/// Deliberately untouched: the signer's `CERTIFY` (the orchestrator has no
/// certify surface) and the Safe's own three direct action roles (the
/// break-glass path).
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20260831-retire-direct-signer-roles` per chain; sign and
/// execute the artifact in the Safe UI. Pre-flight refuses to author unless
/// the orchestrator path is FULLY enabled on the chain — the orchestrator
/// holds both vault roles and the signer holds `MINT`/`BURN` on it
/// (`OrchestratorPathNotEnabled`) — so the retirement can never strand a
/// chain with no working mint path. Self-scoping; a retired chain refuses
/// (`DirectSignerRolesAlreadyRetired`).
///
/// The post-execution pin PR removes the signer's `DEPOSIT`/`WITHDRAW`
/// rows from the canonical grant map, pins their absence (the
/// Fireblocks-revocation lifecycle), and retires this script's fixtures.
contract RetireDirectSignerRoles is Script {
    /// @notice The service signer whose direct vault access retires.
    address internal constant SERVICE_SIGNER = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;

    /// @notice The orchestrator's operational roles (audited 0.1.30 source).
    bytes32 internal constant ORCHESTRATOR_MINT_ROLE = keccak256("MINT");
    bytes32 internal constant ORCHESTRATOR_BURN_ROLE = keccak256("BURN");

    /// @notice Signer-visible `meta.name` for the emitted bundle.
    string internal constant BUNDLE_NAME = "ST0x retire: service signer's direct vault roles (orchestrator proven)";

    /// @notice Chain-suffixed artifact path.
    /// @return path The artifact path for the ACTIVE chain.
    function artifactPath() internal view virtual returns (string memory path) {
        path = string.concat("out/20260831-retire-direct-signer-roles-", vm.toString(block.chainid), ".json");
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
            revert UnsupportedChainForRetire(block.chainid);
        }
        if (
            authoriser == address(0) || authoriser.code.length == 0
                || authoriser.codehash != LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH
        ) {
            revert AuthoriserNotReadyForRetire(authoriser);
        }
    }

    /// @notice The burn-in gate: the orchestrator path must be FULLY enabled
    /// before the direct path retires — the orchestrator holds both vault
    /// roles on the authoriser and the signer holds both operational roles
    /// on the orchestrator. Reverts `OrchestratorPathNotEnabled` naming the
    /// first missing (holder, role).
    /// @param acl The authoriser's access-control surface.
    /// @param orchestrator The orchestrator instance.
    function assertOrchestratorPathEnabled(IAccessControl acl, address orchestrator) internal view {
        if (!acl.hasRole(keccak256("DEPOSIT"), orchestrator)) {
            revert OrchestratorPathNotEnabled(orchestrator, keccak256("DEPOSIT"));
        }
        if (!acl.hasRole(keccak256("WITHDRAW"), orchestrator)) {
            revert OrchestratorPathNotEnabled(orchestrator, keccak256("WITHDRAW"));
        }
        IAccessControl orch = IAccessControl(orchestrator);
        if (!orch.hasRole(ORCHESTRATOR_MINT_ROLE, SERVICE_SIGNER)) {
            revert OrchestratorPathNotEnabled(SERVICE_SIGNER, ORCHESTRATOR_MINT_ROLE);
        }
        if (!orch.hasRole(ORCHESTRATOR_BURN_ROLE, SERVICE_SIGNER)) {
            revert OrchestratorPathNotEnabled(SERVICE_SIGNER, ORCHESTRATOR_BURN_ROLE);
        }
    }

    /// @notice Pre-flight the principals and self-scope the bundle: one
    /// `revokeRole` per direct role the signer still holds. Refuses when
    /// the Safe lacks an `_ADMIN` it needs or when nothing remains
    /// (`DirectSignerRolesAlreadyRetired`).
    /// @param authoriser The chain's authoriser clone.
    /// @param safeAddr The chain's token-owner Safe.
    /// @return txs The self-scoped revoke transactions.
    function authorBundle(address authoriser, address safeAddr) internal view returns (SafeTx[] memory txs) {
        IAccessControl acl = IAccessControl(authoriser);

        if (!acl.hasRole(keccak256("DEPOSIT_ADMIN"), safeAddr)) {
            revert SafeMissingRoleAdminForRetire(keccak256("DEPOSIT_ADMIN"));
        }
        if (!acl.hasRole(keccak256("WITHDRAW_ADMIN"), safeAddr)) {
            revert SafeMissingRoleAdminForRetire(keccak256("WITHDRAW_ADMIN"));
        }

        SafeTx[] memory candidates = new SafeTx[](2);
        uint256 count = 0;
        bytes32[2] memory roles = [keccak256("DEPOSIT"), keccak256("WITHDRAW")];
        for (uint256 i = 0; i < roles.length; i++) {
            if (acl.hasRole(roles[i], SERVICE_SIGNER)) {
                candidates[count++] = SafeTx({
                    to: authoriser,
                    value: 0,
                    data: abi.encodeCall(IAccessControl.revokeRole, (roles[i], SERVICE_SIGNER)),
                    operation: 0
                });
            }
        }
        if (count == 0) {
            revert DirectSignerRolesAlreadyRetired();
        }
        txs = new SafeTx[](count);
        for (uint256 i = 0; i < count; i++) {
            txs[i] = candidates[i];
        }
    }

    /// @notice Assert the post-retirement state on the active fork: the
    /// signer holds neither direct vault role, its `CERTIFY` and every
    /// other canonical row survive, and the orchestrator path is intact.
    /// @dev The map-wide `assertExpectedGrants` cannot be used: the map
    /// pins what production IS until this bundle executes (the signer's
    /// rows are still in it). Row-by-row with the retired rows negated;
    /// the post-execution pin PR moves this shape into the invariant lib.
    /// @param acl The authoriser's access-control surface.
    /// @param orchestrator The orchestrator instance.
    /// @param safeAddr The chain's token-owner Safe.
    function assertPostRetireState(IAccessControl acl, address orchestrator, address safeAddr) internal view {
        require(
            !acl.hasRole(keccak256("DEPOSIT"), SERVICE_SIGNER) && !acl.hasRole(keccak256("WITHDRAW"), SERVICE_SIGNER),
            "RetireDirectSignerRoles: signer still holds a direct vault role"
        );
        RoleGrant[] memory all = LibAuthoriserInvariants.expectedGrants(safeAddr);
        for (uint256 i = 0; i < all.length; i++) {
            bool retiredRow = all[i].grantee == SERVICE_SIGNER
                && (all[i].role == keccak256("DEPOSIT") || all[i].role == keccak256("WITHDRAW"));
            if (retiredRow) continue;
            require(
                acl.hasRole(all[i].role, all[i].grantee),
                "RetireDirectSignerRoles: retirement disturbed an unrelated grant"
            );
        }
        assertOrchestratorPathEnabled(acl, orchestrator);
    }

    /// @notice Author the retirement bundle for the active chain: see the
    /// contract-level flow. Does not broadcast — execution happens via the
    /// Safe UI using the emitted artifact.
    function run() external {
        // --- Pre-flight ---------------------------------------------------

        address safeAddr = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        IGnosisSafe safe = IGnosisSafe(safeAddr);
        address authoriser = activeChainAuthoriser();
        IAccessControl acl = IAccessControl(authoriser);

        LibOrchestratorInvariants.assertBeaconSet(safeAddr);
        LibOrchestratorInvariants.assertInstance(safeAddr);
        address orchestrator = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;

        // The burn-in gate: no retirement without a fully-enabled
        // orchestrator path.
        assertOrchestratorPathEnabled(acl, orchestrator);

        // The canonical map must hold exactly before rows leave it.
        LibAuthoriserInvariants.assertExpectedGrants(authoriser, safeAddr);

        // --- Build the bundle ----------------------------------------------

        SafeTx[] memory txs = authorBundle(authoriser, safeAddr);

        uint256 nonce = safe.nonce();
        bytes32 bundleSafeTxHash = LibSafeOps.computeMultiSendSafeTxHash(safe, txs, nonce);

        // --- Simulate -----------------------------------------------------

        for (uint256 i = 0; i < txs.length; i++) {
            LibSafeOps.simulateExternalCall(safe, txs[i].to, txs[i].data);
        }

        // --- Post-state ---------------------------------------------------

        assertPostRetireState(acl, orchestrator, safeAddr);
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
        console2.log("Service signer:", SERVICE_SIGNER);

        // --- n+1 reversal proof --------------------------------------------

        // The retirement is fully reversible under the `_ADMIN`s the Safe
        // holds: prove the re-grant clears the live threshold, then
        // re-revoke so the fork ends retired.
        LibSafeOps.simulateNPlus1(
            safe,
            authoriser,
            abi.encodeCall(IAccessControl.grantRole, (keccak256("DEPOSIT"), SERVICE_SIGNER)),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD
        );
        require(
            acl.hasRole(keccak256("DEPOSIT"), SERVICE_SIGNER),
            "RetireDirectSignerRoles: n+1 re-grant did not restore the role"
        );
        LibSafeOps.simulateExternalCall(
            safe, authoriser, abi.encodeCall(IAccessControl.revokeRole, (keccak256("DEPOSIT"), SERVICE_SIGNER))
        );
        console2.log(
            "n+1 reversal check passed: the Safe can restore (and re-retire) the fallback under the live threshold"
        );
    }

    /// @notice Signer-side integrity check for a CI-authored retirement
    /// artifact, run LOCALLY against a live fork before signing.
    /// Deliberately NOT in the run-script dispatcher: it takes a local path
    /// and runs on the signer's machine.
    /// @param jsonPath Filesystem path to the downloaded Tx Builder JSON.
    function verify(string calldata jsonPath) external view {
        address safeAddr = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        IGnosisSafe safe = IGnosisSafe(safeAddr);
        address authoriser = activeChainAuthoriser();
        LibOrchestratorInvariants.assertBeaconSet(safeAddr);
        LibOrchestratorInvariants.assertInstance(safeAddr);
        assertOrchestratorPathEnabled(IAccessControl(authoriser), LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE);

        SafeTx[] memory expected = authorBundle(authoriser, safeAddr);
        LibSafeOps.assertParsedTxsMatch(expected, jsonPath);

        uint256 nonce = safe.nonce();
        console2.log("Artifact verified against live state.");
        console2.log(
            "Bundle MultiSend SafeTxHash:", vm.toString(LibSafeOps.computeMultiSendSafeTxHash(safe, expected, nonce))
        );
        console2.log("Nonce:", nonce);
    }
}

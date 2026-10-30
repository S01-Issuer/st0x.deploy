// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibOrchestratorInvariants} from "../src/lib/LibOrchestratorInvariants.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {LibSafeTx, SafeTx} from "rain-deploy-0.1.29/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.29/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.29/src/lib/LibSafeTxBuilderJson.sol";
import {LibSafe} from "rain-deploy-0.1.29/src/lib/LibSafe.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.29/src/interface/deprecated/IMigrationRegistryV3.sol";
import {IStoxScript, MigrationWriter, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibRbacMigration} from "../src/lib/LibRbacMigration.sol";

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

/// @notice This script's declaration: the timelock's first `st0x.rbac`
/// record, the service signer's direct roles retired.
/// @return The declaration.
function retireDirectSignerRolesDeclaration() pure returns (ScriptDeclaration memory) {
    return LibStoxMigrations.migrationOnto(
        MigrationWriter.Timelock,
        LibRbacMigration.STOX_RBAC_NAMESPACE,
        LibRbacMigration.SERVICE_SIGNER_DIRECT_ROLES_RETIRED,
        MIGRATION_HEAD_GENESIS,
        false
    );
}

/// @title RetireDirectSignerRoles
/// @notice Authors the per-chain Safe Tx Builder bundle that
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
/// **SUPERSEDED.** The revokes need the vault `_ADMIN`s, and
/// `20260729-migrate-governance-to-timelock` moved them to the timelock on
/// every chain before this script was dispatched, so it now refuses
/// (`SafeMissingRoleAdminForRetire`) everywhere. The retirement has to be
/// authored as a timelock operation (Safe schedules the same two revokes,
/// 48h, execute) in a new dated script. This one stays registered so its
/// refusal can be re-derived.
contract RetireDirectSignerRoles is Script, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return retireDirectSignerRolesDeclaration();
    }

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
    /// @return The self-scoped revoke transactions.
    function authorBundle(address authoriser, address safeAddr) internal view returns (SafeTx[] memory) {
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
                    operation: Enum.Operation.Call
                });
            }
        }
        if (count == 0) {
            revert DirectSignerRolesAlreadyRetired();
        }
        SafeTx[] memory txs = new SafeTx[](count);
        for (uint256 i = 0; i < count; i++) {
            txs[i] = candidates[i];
        }
        return txs;
    }

    /// @notice Assert the post-retirement state on the active fork: the
    /// signer holds neither direct vault role, its `CERTIFY` and every
    /// other canonical row survive, and the orchestrator path is intact.
    /// @param acl The authoriser's access-control surface.
    /// @param orchestrator The orchestrator instance.
    /// @param safeAddr The chain's token-owner Safe.
    function assertPostRetireState(IAccessControl acl, address orchestrator, address safeAddr) internal view {
        require(
            !acl.hasRole(keccak256("DEPOSIT"), SERVICE_SIGNER) && !acl.hasRole(keccak256("WITHDRAW"), SERVICE_SIGNER),
            "RetireDirectSignerRoles: signer still holds a direct vault role"
        );
        RoleGrant[] memory all =
            LibAuthoriserInvariants.expectedGrants(safeAddr, LibTimelockInvariants.timelockForChainId(block.chainid));
        for (uint256 i = 0; i < all.length; i++) {
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
        Safe safe = Safe(payable(safeAddr));
        address authoriser = LibAuthoriserInvariants.activeChainAuthoriser();
        IAccessControl acl = IAccessControl(authoriser);

        LibOrchestratorInvariants.assertBeaconSet();
        LibOrchestratorInvariants.assertInstance();
        address orchestrator = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;

        // The burn-in gate: no retirement without a fully-enabled
        // orchestrator path.
        assertOrchestratorPathEnabled(acl, orchestrator);

        LibAuthoriserInvariants.assertExpectedGrants(
            authoriser, safeAddr, LibTimelockInvariants.timelockForChainId(block.chainid)
        );

        // --- Build the bundle ----------------------------------------------

        SafeTx[] memory txs = authorBundle(authoriser, safeAddr);

        uint256 nonce = safe.nonce();
        bytes32 bundleSafeTxHash = LibSafeTx.multiSendSafeTxHash(safe, txs, nonce);

        // --- Simulate -----------------------------------------------------

        for (uint256 i = 0; i < txs.length; i++) {
            LibSafeFork.simulateCall(vm, safe, txs[i].to, txs[i].data);
        }

        // --- Post-state ---------------------------------------------------

        assertPostRetireState(acl, orchestrator, safeAddr);
        LibSafe.assertLockedDown(safe);
        LibSafe.assertThreshold(safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);

        // --- Artifact -----------------------------------------------------

        string memory json = LibSafeTxBuilderJson.toJson(vm, safeAddr, block.chainid, BUNDLE_NAME, txs);
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
        LibSafeFork.simulateNPlus1(
            vm, safe, authoriser, abi.encodeCall(IAccessControl.grantRole, (keccak256("DEPOSIT"), SERVICE_SIGNER))
        );
        require(
            acl.hasRole(keccak256("DEPOSIT"), SERVICE_SIGNER),
            "RetireDirectSignerRoles: n+1 re-grant did not restore the role"
        );
        LibSafeFork.simulateCall(
            vm, safe, authoriser, abi.encodeCall(IAccessControl.revokeRole, (keccak256("DEPOSIT"), SERVICE_SIGNER))
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
        Safe safe = Safe(payable(safeAddr));
        address authoriser = LibAuthoriserInvariants.activeChainAuthoriser();
        LibOrchestratorInvariants.assertBeaconSet();
        LibOrchestratorInvariants.assertInstance();
        assertOrchestratorPathEnabled(IAccessControl(authoriser), LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE);

        LibAuthoriserInvariants.assertExpectedGrants(
            authoriser, safeAddr, LibTimelockInvariants.timelockForChainId(block.chainid)
        );
        SafeTx[] memory expected = authorBundle(authoriser, safeAddr);
        LibSafeTxBuilderJson.requireMatches(vm, vm.readFile(jsonPath), safeAddr, expected);

        uint256 nonce = safe.nonce();
        console2.log("Artifact verified against live state.");
        console2.log("Bundle MultiSend SafeTxHash:", vm.toString(LibSafeTx.multiSendSafeTxHash(safe, expected, nonce)));
        console2.log("Nonce:", nonce);
    }
}

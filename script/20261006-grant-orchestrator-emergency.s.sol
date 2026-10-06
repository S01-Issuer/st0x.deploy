// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {IMigrationRegistryV2} from "rain-deploy-0.1.12/src/interface/IMigrationRegistryV2.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.12/src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.12/src/lib/LibMigrationRegistryDeploy.sol";

import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {LibOrchestratorInvariants} from "../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx} from "../src/lib/LibSafeOps.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @notice The Safe's line in the migration registry is not where this
/// script applies: it has recorded something, so either this bundle has
/// already executed on the chain or a migration this script does not know
/// about has.
/// @param head The line's head.
error UnexpectedMigrationLine(bytes32 head);

/// @notice The Safe already holds `EMERGENCY_ROLE` without the record this
/// script writes: it was granted outside a recorded migration.
error EmergencyAlreadyGranted();

/// @title GrantOrchestratorEmergency
/// @notice Authors the per-chain Safe Tx Builder bundle that grants the
/// chain's token-owner Safe `EMERGENCY_ROLE` on the orchestrator, and starts
/// the Safe's line in `rain-deploy`'s `MigrationRegistry`. Three calls, one
/// atomic MultiSend:
///
/// 1. `orchestrator.grantRole(EMERGENCY, safe)`.
/// 2. `registry.applyMigrationHistory(GOVERNANCE_TIMELOCK, executedAt,
///    [genesis])`: the governance-timelock migration ran before anything
///    was recorded, so it is recorded with the moment it executed on this
///    chain (`LibStoxMigrations.governanceTimelockExecution`). Recording it
///    first keeps the line in the order the migrations ran; once anything
///    later is recorded, the registry refuses an earlier moment.
/// 3. `registry.applyMigration(ORCHESTRATOR_EMERGENCY, [GOVERNANCE_TIMELOCK])`:
///    the grant's own record, stamped with the block it lands in.
///
/// `EMERGENCY_ROLE` is administered by `DEFAULT_ADMIN_ROLE`, which the Safe
/// holds, so the grant is immediate. The admin move to the timelock is
/// `20261006-orchestrator-admin-to-timelock`, which waits on this record.
///
/// `LibOrchestratorInvariants.assertInstance` reads the record: before it,
/// the Safe must not hold `EMERGENCY_ROLE`; after it, the Safe must.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20261006-grant-orchestrator-emergency` per chain. Refuses once
/// the Safe's line has moved off genesis (`UnexpectedMigrationLine`).
contract GrantOrchestratorEmergency is Script {
    /// @notice Signer-visible `meta.name` for the emitted bundle.
    string internal constant BUNDLE_NAME = "ST0x orchestrator: grant EMERGENCY_ROLE to the token-owner Safe";

    /// @notice Chain-suffixed artifact path.
    /// @return path The artifact path for the ACTIVE chain.
    function artifactPath() internal view virtual returns (string memory path) {
        path = string.concat("out/20261006-grant-orchestrator-emergency-", vm.toString(block.chainid), ".json");
    }

    /// @notice Pre-flight live state: the Safe, the timelock and the
    /// orchestrator are what this repo pins, the Safe's registry line is at
    /// genesis, and the Safe does not yet hold `EMERGENCY_ROLE`.
    /// @return safe The chain's token-owner Safe.
    function preflight() internal view returns (address safe) {
        safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock, safe);
        LibOrchestratorInvariants.assertBeaconSet();

        bytes32 head = LibStoxMigrations.head(safe);
        if (head != LibStoxMigrations.genesis()) {
            revert UnexpectedMigrationLine(head);
        }
        if (IAccessControl(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE)
                .hasRole(LibOrchestratorInvariants.EMERGENCY_ROLE, safe)) {
            revert EmergencyAlreadyGranted();
        }
        // With the line at genesis, this asserts the pre-grant state exactly.
        LibOrchestratorInvariants.assertInstance(safe);
    }

    /// @notice The bundle for the active chain.
    /// @param safe The chain's token-owner Safe.
    /// @return txs The grant, then the two records.
    function authorBundle(address safe) internal view returns (SafeTx[] memory txs) {
        (uint256 executedAt,) = LibStoxMigrations.governanceTimelockExecution(block.chainid);
        address registry = LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS;

        txs = new SafeTx[](3);
        txs[0] = SafeTx({
            to: LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE,
            value: 0,
            data: abi.encodeCall(IAccessControl.grantRole, (LibOrchestratorInvariants.EMERGENCY_ROLE, safe)),
            operation: 0
        });
        txs[1] = SafeTx({
            to: registry,
            value: 0,
            data: abi.encodeCall(
                IMigrationRegistryV2.applyMigrationHistory,
                (
                    LibStoxMigrations.NAMESPACE,
                    LibStoxMigrations.GOVERNANCE_TIMELOCK,
                    executedAt,
                    LibStoxMigrations.onto(safe, LibStoxMigrations.genesis())
                )
            ),
            operation: 0
        });
        txs[2] = SafeTx({
            to: registry,
            value: 0,
            data: abi.encodeCall(
                IMigrationRegistryV2.applyMigration,
                (
                    LibStoxMigrations.NAMESPACE,
                    LibStoxMigrations.ORCHESTRATOR_EMERGENCY,
                    LibStoxMigrations.onto(safe, LibStoxMigrations.GOVERNANCE_TIMELOCK)
                )
            ),
            operation: 0
        });
    }

    /// @notice Assert the post-bundle state on the active fork: the records
    /// are exactly the two this bundle writes, and the orchestrator's roles
    /// are what they imply.
    /// @param safe The chain's token-owner Safe.
    function assertPostState(address safe) internal view {
        (uint256 executedAt,) = LibStoxMigrations.governanceTimelockExecution(block.chainid);
        require(
            LibStoxMigrations.applied(safe, LibStoxMigrations.GOVERNANCE_TIMELOCK) == executedAt,
            "GrantOrchestratorEmergency: governance-timelock record"
        );
        // The registry stamps the block the record lands in, which on the
        // fork is this block: an equality with a known value, not a window.
        require(
            // forge-lint: disable-next-line(block-timestamp)
            LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_EMERGENCY) == block.timestamp,
            "GrantOrchestratorEmergency: emergency record"
        );
        require(
            LibStoxMigrations.head(safe) == LibStoxMigrations.ORCHESTRATOR_EMERGENCY,
            "GrantOrchestratorEmergency: line head"
        );
        LibOrchestratorInvariants.assertInstance(safe);
    }

    /// @notice Author the bundle for the active chain. Does not broadcast:
    /// execution happens in the Safe UI from the emitted artifact.
    function run() external {
        // --- Pre-flight ---------------------------------------------------

        address safeAddr = preflight();
        IGnosisSafe safe = IGnosisSafe(safeAddr);

        // --- Build the bundle ----------------------------------------------

        SafeTx[] memory txs = authorBundle(safeAddr);
        uint256 nonce = safe.nonce();
        bytes32 bundleSafeTxHash = LibSafeOps.computeMultiSendSafeTxHash(safe, txs, nonce);

        // --- Simulate -----------------------------------------------------

        for (uint256 i = 0; i < txs.length; i++) {
            LibSafeOps.simulateExternalCall(safe, txs[i].to, txs[i].data);
        }

        // --- Post-state ---------------------------------------------------

        assertPostState(safeAddr);
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

        // --- n+1 proof ----------------------------------------------------

        // The Safe can still take the role back under the live threshold, so
        // a mistaken grant is reversible without the timelock. Re-grant so
        // the fork ends in the post-bundle state.
        LibSafeOps.simulateNPlus1(
            safe,
            LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE,
            abi.encodeCall(IAccessControl.revokeRole, (LibOrchestratorInvariants.EMERGENCY_ROLE, safeAddr)),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD
        );
        require(
            !IAccessControl(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE)
                .hasRole(LibOrchestratorInvariants.EMERGENCY_ROLE, safeAddr),
            "GrantOrchestratorEmergency: n+1 revoke did not remove the role"
        );
        LibSafeOps.simulateExternalCall(safe, txs[0].to, txs[0].data);
        console2.log("n+1 check passed: the Safe can revoke (and re-grant) EMERGENCY under the live threshold");
    }

    /// @notice Signer-side integrity check for a CI-authored artifact, run
    /// LOCALLY against a live fork before signing: re-derives the bundle
    /// from current chain state, asserts the artifact matches it exactly,
    /// and prints the MultiSend `SafeTxHash` at the live nonce.
    /// @param jsonPath Filesystem path to the downloaded Tx Builder JSON.
    function verify(string calldata jsonPath) external view {
        address safeAddr = preflight();
        IGnosisSafe safe = IGnosisSafe(safeAddr);
        LibMigrationRegistry.checkCodeHash();

        SafeTx[] memory expected = authorBundle(safeAddr);
        LibSafeOps.assertParsedTxsMatch(expected, jsonPath);

        uint256 nonce = safe.nonce();
        console2.log("Artifact verified against live state.");
        console2.log(
            "Bundle MultiSend SafeTxHash:", vm.toString(LibSafeOps.computeMultiSendSafeTxHash(safe, expected, nonce))
        );
        console2.log("Nonce:", nonce);
    }
}

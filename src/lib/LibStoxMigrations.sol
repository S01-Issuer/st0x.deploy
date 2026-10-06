// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {LibMigrationRegistry} from "rain-deploy-0.1.12/src/lib/LibMigrationRegistry.sol";
import {MIGRATION_HEAD_GENESIS, Prerequisite} from "rain-deploy-0.1.12/src/interface/IMigrationRegistryV2.sol";

import {LibSafeInvariants} from "./LibSafeInvariants.sol";

/// @notice No execution moment is pinned for the governance-timelock
/// migration on this chain.
/// @param chainId The chain asked about.
error NoGovernanceTimelockMigrationOnChain(uint256 chainId);

/// @title LibStoxMigrations
/// @notice The ids under which this repo's operational scripts record what
/// they applied in `rain-deploy`'s `MigrationRegistry`, and the reads the
/// invariants branch on.
///
/// A migration recorded with its change is recorded by the account that
/// performs it, as the last call of the same transaction, so the record and
/// the change land atomically:
///
/// - a migration the chain's token-owner Safe performs directly records
///   under the Safe, in the Safe's MultiSend (both orchestrator ids here);
/// - a migration executed through the governance timelock records under the
///   timelock, as the last call of the scheduled batch, so it lands
///   atomically whoever executes the matured operation. Its invariant reads
///   the timelock's line.
///
/// The exception is a migration that ran before anything was recorded: it
/// is recorded later as history, with the moment it executed
/// (`GOVERNANCE_TIMELOCK`, written by the orchestrator EMERGENCY bundle).
/// Until that record lands, `applied` answering zero does NOT mean it has
/// not run, so no invariant branches on `GOVERNANCE_TIMELOCK`'s record.
///
/// For every id recorded with its change, an invariant asserts exactly the
/// state the recorded migrations imply: `applied` answering zero means the
/// migration has not run on this chain, and the pre-migration state must
/// hold exactly.
///
/// The records live in ONE registry instance: the address and code hash
/// `LibMigrationRegistryDeploy` carries in the imported rain-deploy. A
/// rain-deploy bump that moves the registry would read an empty line and
/// fail every role invariant closed; `LibStoxMigrationsTest` pins the
/// instance so such a bump fails there first.
///
/// The registry is an index, not proof. It says which state an invariant must
/// assert; the invariant still reads that state from the chain.
library LibStoxMigrations {
    /// @notice The namespace every st0x.deploy record is written in.
    bytes32 internal constant NAMESPACE = keccak256("st0x.deploy");

    /// @notice `script/20260729-migrate-governance-to-timelock.s.sol`: vault
    /// and beacon ownership plus the authoriser `_ADMIN` roles to the
    /// governance timelock. Ran before anything was recorded, so it is
    /// recorded as history with the moment it executed.
    bytes32 internal constant GOVERNANCE_TIMELOCK = keccak256("script/20260729-migrate-governance-to-timelock.s.sol");

    /// @notice `script/20261006-grant-orchestrator-emergency.s.sol`: the
    /// chain's Safe is granted `EMERGENCY_ROLE` on the orchestrator.
    bytes32 internal constant ORCHESTRATOR_EMERGENCY = keccak256("script/20261006-grant-orchestrator-emergency.s.sol");

    /// @notice `script/20261006-orchestrator-admin-to-timelock.s.sol`: the
    /// orchestrator's `DEFAULT_ADMIN_ROLE` moves from the chain's Safe to the
    /// governance timelock.
    bytes32 internal constant ORCHESTRATOR_ADMIN_TO_TIMELOCK =
        keccak256("script/20261006-orchestrator-admin-to-timelock.s.sol");

    /// @notice The block timestamp of the Safe transaction that executed the
    /// governance-timelock migration on `chainId`: the block in which the
    /// orchestrator beacon's `OwnershipTransferred(safe, timelock)` was
    /// emitted.
    /// @param chainId The chain id.
    /// @return appliedAt The execution moment, unix seconds.
    /// @return blockNumber The block the migration executed in.
    function governanceTimelockExecution(uint256 chainId)
        internal
        pure
        returns (uint256 appliedAt, uint256 blockNumber)
    {
        if (chainId == LibSafeInvariants.ETHEREUM_CHAIN_ID) {
            return (1_791_056_759, 26_113_992);
        }
        if (chainId == LibSafeInvariants.HYPEREVM_CHAIN_ID) return (1_791_062_016, 47_585_501);
        if (chainId == LibSafeInvariants.BSC_CHAIN_ID) return (1_791_109_807, 125_660_540);
        if (chainId == LibSafeInvariants.ROBINHOOD_CHAIN_ID) return (1_791_131_389, 80_078_305);
        if (chainId == LibSafeInvariants.BASE_CHAIN_ID) return (1_791_142_369, 52_176_511);
        revert NoGovernanceTimelockMigrationOnChain(chainId);
    }

    /// @notice When `writer` recorded `migration` in this repo's namespace, or
    /// zero if it never did. Verifies the registry's code hash first.
    /// @param writer The account that performed the migration: the chain's
    /// Safe for a Safe-executed migration, its timelock for a
    /// timelock-executed one.
    /// @param migration The migration id.
    /// @return The recorded moment, or zero.
    function applied(address writer, bytes32 migration) internal view returns (uint256) {
        return LibMigrationRegistry.applied(writer, NAMESPACE, migration);
    }

    /// @notice The migration `writer`'s line in this repo's namespace was last
    /// applied onto, or `MIGRATION_HEAD_GENESIS` if it has recorded nothing.
    /// @param writer The account whose line to read.
    /// @return The head.
    function head(address writer) internal view returns (bytes32) {
        return LibMigrationRegistry.head(writer, NAMESPACE);
    }

    /// @notice The prerequisite list for a migration applied onto
    /// `headMigration` that waits on nothing outside the writer's own line.
    /// @param writer The account writing the record.
    /// @param headMigration The head the migration is applied onto.
    /// @return prerequisites The single-entry list naming the head.
    function onto(address writer, bytes32 headMigration) internal pure returns (Prerequisite[] memory prerequisites) {
        prerequisites = new Prerequisite[](1);
        prerequisites[0] = Prerequisite({writer: writer, namespace: NAMESPACE, migration: headMigration});
    }

    /// @notice The genesis head, re-exported so consumers need not import
    /// the registry interface for it.
    /// @return `MIGRATION_HEAD_GENESIS`.
    function genesis() internal pure returns (bytes32) {
        return MIGRATION_HEAD_GENESIS;
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {LibMigrationRegistry} from "rain-deploy-0.1.18/src/lib/LibMigrationRegistry.sol";
import {MIGRATION_HEAD_GENESIS, Prerequisite} from "rain-deploy-0.1.18/src/interface/IMigrationRegistryV2.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";

import {LibRbacMigration} from "./LibRbacMigration.sol";
import {LibSafeInvariants} from "./LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "./LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "./LibTimelockInvariants.sol";

/// @notice The account that records a migration, by role: its address
/// differs per chain.
enum MigrationWriter {
    Safe,
    Timelock
}

/// @notice `Prerequisite` with the writer named by role.
struct MigrationPrerequisite {
    MigrationWriter writer;
    bytes32 namespace;
    bytes32 migration;
}

/// @notice A migration a script in this repo performs. `namespace` and `id`
/// are zero for one the registry holds no record of.
struct Migration {
    string script;
    bytes32 namespace;
    bytes32 id;
    MigrationWriter writer;
    MigrationPrerequisite[] prerequisites;
}

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

    /// @notice Every migration a script in `script/` performs, in path order.
    /// @return The migrations.
    function migrations() internal pure returns (Migration[] memory) {
        Migration[] memory list = new Migration[](6);
        list[0] = safeOnto(
            "script/20260729-migrate-governance-to-timelock.s.sol",
            NAMESPACE,
            GOVERNANCE_TIMELOCK,
            MIGRATION_HEAD_GENESIS
        );
        list[1] = unrecorded("script/20260831-retire-direct-signer-roles.s.sol");
        list[2] = safeOnto(
            "script/20261006-grant-eu-authoriser-roles.s.sol",
            LibRbacMigration.STOX_RBAC_NAMESPACE,
            LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER,
            MIGRATION_HEAD_GENESIS
        );
        list[3] = safeOnto(
            "script/20261006-grant-orchestrator-emergency.s.sol", NAMESPACE, ORCHESTRATOR_EMERGENCY, GOVERNANCE_TIMELOCK
        );
        list[4] = safeOnto(
            "script/20261006-orchestrator-admin-to-timelock.s.sol",
            NAMESPACE,
            ORCHESTRATOR_ADMIN_TO_TIMELOCK,
            ORCHESTRATOR_EMERGENCY
        );
        list[5] = unrecorded("script/MigrateMultisigThreshold.s.sol");
        return list;
    }

    function safeOnto(string memory script, bytes32 namespace, bytes32 id, bytes32 headMigration)
        private
        pure
        returns (Migration memory)
    {
        MigrationPrerequisite[] memory prerequisites = new MigrationPrerequisite[](1);
        prerequisites[0] =
            MigrationPrerequisite({writer: MigrationWriter.Safe, namespace: namespace, migration: headMigration});
        return Migration({
            script: script, namespace: namespace, id: id, writer: MigrationWriter.Safe, prerequisites: prerequisites
        });
    }

    function unrecorded(string memory script) private pure returns (Migration memory) {
        return Migration({
            script: script,
            namespace: bytes32(0),
            id: bytes32(0),
            writer: MigrationWriter.Safe,
            prerequisites: new MigrationPrerequisite[](0)
        });
    }

    /// @notice The address `writer` is on `chainId`.
    /// @param writer The role.
    /// @param chainId The chain id.
    /// @return The address.
    function writerForChainId(MigrationWriter writer, uint256 chainId) internal pure returns (address) {
        if (writer == MigrationWriter.Timelock) return LibTimelockInvariants.timelockForChainId(chainId);
        return LibSafeInvariants.safeForChainId(chainId);
    }

    /// @notice What `migration` is recorded after on `chainId`, as its write
    /// takes the list.
    /// @param migration The migration.
    /// @param chainId The chain id.
    /// @return The prerequisites.
    function prerequisitesForChainId(Migration memory migration, uint256 chainId)
        internal
        pure
        returns (Prerequisite[] memory)
    {
        Prerequisite[] memory prerequisites = new Prerequisite[](migration.prerequisites.length);
        for (uint256 i = 0; i < prerequisites.length; i++) {
            prerequisites[i] = Prerequisite({
                writer: writerForChainId(migration.prerequisites[i].writer, chainId),
                namespace: migration.prerequisites[i].namespace,
                migration: migration.prerequisites[i].migration
            });
        }
        return prerequisites;
    }

    /// @notice When a migration recorded as history executed on `chainId`;
    /// zero for one recorded with its change, whose record is the moment.
    /// @param migration The migration id.
    /// @param chainId The chain id.
    /// @return The moment, unix seconds, or zero.
    function historyMoment(bytes32 migration, uint256 chainId) internal pure returns (uint256) {
        if (migration != GOVERNANCE_TIMELOCK) return 0;
        (uint256 executedAt,) = governanceTimelockExecution(chainId);
        return executedAt;
    }

    /// @notice The block timestamp of the Safe transaction that executed the
    /// governance-timelock migration on `chainId`: the block in which the
    /// orchestrator beacon's `OwnershipTransferred(safe, timelock)` was
    /// emitted.
    ///
    /// `chainId` resolves to a network through `rain-deploy`'s catalogue
    /// entries for `LibStoxDeployNetworks.deploymentNetworks()`, so chain ids
    /// are stated once, in the catalogue; the moments are pinned per network
    /// name.
    /// @param chainId The chain id.
    /// @return The execution moment, unix seconds.
    /// @return The block the migration executed in.
    function governanceTimelockExecution(uint256 chainId) internal pure returns (uint256, uint256) {
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        for (uint256 i = 0; i < networks.length; i++) {
            if (networks[i].chainId == chainId) {
                bytes32 name = keccak256(bytes(networks[i].name));
                if (name == keccak256(bytes(LibRainDeploy.ETHEREUM))) return (1_791_056_759, 26_113_992);
                if (name == keccak256(bytes(LibRainDeploy.HYPEREVM))) return (1_791_062_016, 47_585_501);
                if (name == keccak256(bytes(LibRainDeploy.BSC))) return (1_791_109_807, 125_660_540);
                if (name == keccak256(bytes(LibRainDeploy.ROBINHOOD))) return (1_791_131_389, 80_078_305);
                if (name == keccak256(bytes(LibRainDeploy.BASE))) return (1_791_142_369, 52_176_511);
            }
        }
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

    /// @notice The registry call that records `migration` under the caller
    /// in this repo's namespace, after `prerequisites`: the `to` and `data`
    /// of a Safe bundle entry. Verifies the registry's code hash first.
    /// @param migration The migration id.
    /// @param prerequisites What it is applied after.
    /// @return The registry.
    /// @return The calldata.
    function applyMigrationCall(bytes32 migration, Prerequisite[] memory prerequisites)
        internal
        view
        returns (address, bytes memory)
    {
        (address registry, bytes memory data) =
            LibMigrationRegistry.applyMigrationCall(NAMESPACE, migration, prerequisites);
        return (registry, data);
    }

    /// @notice The registry call that records `migration` under the caller
    /// in this repo's namespace as history, at `appliedAt`, after
    /// `prerequisites`. Verifies the registry's code hash first.
    /// @param migration The migration id.
    /// @param appliedAt When the migration executed, unix seconds.
    /// @param prerequisites What it is applied after.
    /// @return The registry.
    /// @return The calldata.
    function applyMigrationHistoryCall(bytes32 migration, uint256 appliedAt, Prerequisite[] memory prerequisites)
        internal
        view
        returns (address, bytes memory)
    {
        (address registry, bytes memory data) =
            LibMigrationRegistry.applyMigrationHistoryCall(NAMESPACE, migration, appliedAt, prerequisites);
        return (registry, data);
    }

    /// @notice The prerequisite list for a migration applied onto
    /// `headMigration` that waits on nothing outside the writer's own line.
    /// @param writer The account writing the record.
    /// @param headMigration The head the migration is applied onto.
    /// @return The single-entry list naming the head.
    function onto(address writer, bytes32 headMigration) internal pure returns (Prerequisite[] memory) {
        return LibMigrationRegistry.onto(writer, NAMESPACE, headMigration);
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {LibMigrationRegistry} from "rain-deploy-0.1.22/src/lib/LibMigrationRegistry.sol";
import {Prerequisite} from "rain-deploy-0.1.22/src/interface/IMigrationRegistryV3.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.22/src/lib/LibRainDeploy.sol";

import {MigrationPrerequisite, MigrationWriter, ScriptDeclaration} from "../interface/IStoxScript.sol";
import {LibSafeInvariants} from "./LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "./LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "./LibTimelockInvariants.sol";

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

    /// @notice A migration `writer` records in `namespace`, applied onto
    /// `headMigration` in `writer`'s own line of that namespace.
    /// @param writer The account that records it, by role.
    /// @param namespace The record's namespace.
    /// @param id The record's id.
    /// @param headMigration What it is applied onto.
    /// @param history Whether it is recorded later as history.
    /// @return The declaration.
    function migrationOnto(MigrationWriter writer, bytes32 namespace, bytes32 id, bytes32 headMigration, bool history)
        internal
        pure
        returns (ScriptDeclaration memory)
    {
        MigrationPrerequisite[] memory prerequisites = new MigrationPrerequisite[](1);
        prerequisites[0] = MigrationPrerequisite({writer: writer, namespace: namespace, migration: headMigration});
        return ScriptDeclaration({
            migration: true,
            namespace: namespace,
            id: id,
            writer: writer,
            prerequisites: prerequisites,
            history: history
        });
    }

    /// @notice `migrationOnto` with the Safe as the writer.
    /// @param namespace The record's namespace.
    /// @param id The record's id.
    /// @param headMigration What it is applied onto.
    /// @param history Whether it is recorded later as history.
    /// @return The declaration.
    function safeMigrationOnto(bytes32 namespace, bytes32 id, bytes32 headMigration, bool history)
        internal
        pure
        returns (ScriptDeclaration memory)
    {
        return migrationOnto(MigrationWriter.Safe, namespace, id, headMigration, history);
    }

    /// @notice A script that writes no record.
    /// @return The declaration.
    function notAMigration() internal pure returns (ScriptDeclaration memory) {
        return ScriptDeclaration({
            migration: false,
            namespace: bytes32(0),
            id: bytes32(0),
            writer: MigrationWriter.Safe,
            prerequisites: new MigrationPrerequisite[](0),
            history: false
        });
    }

    /// @notice The address `writer` is, given the chain's Safe and timelock.
    /// @param writer The role.
    /// @param safe The Safe.
    /// @param timelock The timelock.
    /// @return The address.
    function writerFor(MigrationWriter writer, address safe, address timelock) internal pure returns (address) {
        return writer == MigrationWriter.Timelock ? timelock : safe;
    }

    /// @notice The address `writer` is on `chainId`.
    /// @param writer The role.
    /// @param chainId The chain id.
    /// @return The address.
    function writerForChainId(MigrationWriter writer, uint256 chainId) internal pure returns (address) {
        if (writer == MigrationWriter.Timelock) return LibTimelockInvariants.timelockForChainId(chainId);
        return LibSafeInvariants.safeForChainId(chainId);
    }

    /// @notice What `declared` is recorded after, as its write takes the list.
    /// @param declared The declaration.
    /// @param safe The Safe.
    /// @param timelock The timelock.
    /// @return The prerequisites.
    function prerequisitesFor(ScriptDeclaration memory declared, address safe, address timelock)
        internal
        pure
        returns (Prerequisite[] memory)
    {
        Prerequisite[] memory prerequisites = new Prerequisite[](declared.prerequisites.length);
        for (uint256 i = 0; i < prerequisites.length; i++) {
            prerequisites[i] = Prerequisite({
                writer: writerFor(declared.prerequisites[i].writer, safe, timelock),
                namespace: declared.prerequisites[i].namespace,
                migration: declared.prerequisites[i].migration
            });
        }
        return prerequisites;
    }

    /// @notice `prerequisitesFor` with `chainId`'s pinned Safe and timelock.
    /// @param declared The declaration.
    /// @param chainId The chain id.
    /// @return The prerequisites.
    function prerequisitesForChainId(ScriptDeclaration memory declared, uint256 chainId)
        internal
        pure
        returns (Prerequisite[] memory)
    {
        return prerequisitesFor(
            declared, LibSafeInvariants.safeForChainId(chainId), LibTimelockInvariants.timelockForChainId(chainId)
        );
    }

    /// @notice The registry call that writes `declared`'s record. Verifies the
    /// registry's code hash first.
    /// @param declared The declaration.
    /// @param safe The Safe.
    /// @param timelock The timelock.
    /// @return The registry.
    /// @return The calldata.
    function recordCall(ScriptDeclaration memory declared, address safe, address timelock)
        internal
        view
        returns (address, bytes memory)
    {
        (address registry, bytes memory data) = LibMigrationRegistry.applyMigrationV3Call(
            writerFor(declared.writer, safe, timelock),
            declared.namespace,
            declared.id,
            prerequisitesFor(declared, safe, timelock)
        );
        return (registry, data);
    }

    /// @notice The registry call that writes `declared`'s record as history,
    /// at `appliedAt`. Verifies the registry's code hash first.
    /// @param declared The declaration.
    /// @param appliedAt When it executed, unix seconds.
    /// @param safe The Safe.
    /// @param timelock The timelock.
    /// @return The registry.
    /// @return The calldata.
    function historyCall(ScriptDeclaration memory declared, uint256 appliedAt, address safe, address timelock)
        internal
        view
        returns (address, bytes memory)
    {
        (address registry, bytes memory data) = LibMigrationRegistry.applyMigrationHistoryV3Call(
            writerFor(declared.writer, safe, timelock),
            declared.namespace,
            declared.id,
            appliedAt,
            prerequisitesFor(declared, safe, timelock)
        );
        return (registry, data);
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
        return LibMigrationRegistry.appliedV3(writer, NAMESPACE, migration);
    }

    /// @notice The migration `writer`'s line in this repo's namespace was last
    /// applied onto, or `MIGRATION_HEAD_GENESIS` if it has recorded nothing.
    /// @param writer The account whose line to read.
    /// @return The head.
    function head(address writer) internal view returns (bytes32) {
        return LibMigrationRegistry.headV3(writer, NAMESPACE);
    }

    /// @notice The prerequisite list for a migration applied onto
    /// `headMigration` that waits on nothing outside the writer's own line.
    /// @param writer The line's writer.
    /// @param headMigration The head the migration is applied onto.
    /// @return The single-entry list naming the head.
    function onto(address writer, bytes32 headMigration) internal pure returns (Prerequisite[] memory) {
        return LibMigrationRegistry.onto(writer, NAMESPACE, headMigration);
    }
}

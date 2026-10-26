// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {LibMigrationRegistry} from "rain-deploy-0.1.22/src/lib/LibMigrationRegistry.sol";
import {Prerequisite} from "rain-deploy-0.1.22/src/interface/IMigrationRegistryV3.sol";

import {ScriptDeclaration} from "../interface/IStoxScript.sol";

/// @title LibStoxMigrations
/// @notice The ids under which this repo's operational scripts record what
/// they applied in `rain-deploy`'s `MigrationRegistry`, and the calls that
/// write and read those records.
///
/// Every record is in ONE line per chain: `WRITER`'s, in `NAMESPACE`. The
/// account that performs a migration writes its record as `WRITER`'s approved
/// delegate, as the last call of the same transaction, so the record and the
/// change land atomically:
///
/// - a migration the chain's token-owner Safe performs directly is recorded by
///   the Safe, in its MultiSend;
/// - a migration executed through the governance timelock is recorded by the
///   timelock, as the last call of the scheduled batch, so it lands
///   atomically whoever executes the matured operation.
///
/// The line starts empty. A change in force before it, such as the Safe's
/// orchestrator `EMERGENCY_ROLE`, is not recorded.
///
/// The records live in ONE registry instance: the address and code hash
/// `LibMigrationRegistryDeploy` carries in the imported rain-deploy.
/// `LibStoxMigrationsTest` pins the instance so a rain-deploy bump that
/// moves the registry fails there first.
library LibStoxMigrations {
    /// @notice The namespace every st0x.deploy record is written in.
    bytes32 internal constant NAMESPACE = keccak256("st0x.deploy");

    /// @notice The writer of every st0x.deploy record: the root authority, the
    /// same account on every chain, which approves each chain's Safe and
    /// governance timelock to write its line in `NAMESPACE`.
    address internal constant WRITER = address(0x0b300013CD54a8F1aC40981f80FaaA18b8Cc1E4c);

    /// @notice `script/20261006-orchestrator-admin-to-timelock.s.sol`: the
    /// orchestrator's `DEFAULT_ADMIN_ROLE` moves from the chain's Safe to the
    /// governance timelock.
    bytes32 internal constant ORCHESTRATOR_ADMIN_TO_TIMELOCK =
        keccak256("script/20261006-orchestrator-admin-to-timelock.s.sol");

    /// @notice A migration recorded as `id`, applied onto `headMigration`.
    /// @param id The record's id.
    /// @param headMigration What it is applied onto.
    /// @return The declaration.
    function migrationOnto(bytes32 id, bytes32 headMigration) internal pure returns (ScriptDeclaration memory) {
        return ScriptDeclaration({migration: true, id: id, onto: headMigration});
    }

    /// @notice A script that writes no record.
    /// @return The declaration.
    function notAMigration() internal pure returns (ScriptDeclaration memory) {
        return ScriptDeclaration({migration: false, id: bytes32(0), onto: bytes32(0)});
    }

    /// @notice The registry call that writes `declared`'s record: the `to` and
    /// `data` of a bundle entry, made by an approved delegate. Verifies the
    /// registry's code hash first.
    /// @param declared The declaration.
    /// @return The registry.
    /// @return The calldata.
    function recordCall(ScriptDeclaration memory declared) internal view returns (address, bytes memory) {
        (address registry, bytes memory data) =
            LibMigrationRegistry.applyMigrationV3Call(WRITER, NAMESPACE, declared.id, onto(declared.onto));
        return (registry, data);
    }

    /// @notice When `migration` was recorded in this repo's line, or zero if
    /// it never was. Verifies the registry's code hash first.
    /// @param migration The migration id.
    /// @return The recorded moment, or zero.
    function applied(bytes32 migration) internal view returns (uint256) {
        return LibMigrationRegistry.appliedV3(WRITER, NAMESPACE, migration);
    }

    /// @notice The migration this repo's line was last applied onto, or
    /// `MIGRATION_HEAD_GENESIS` if it has recorded nothing.
    /// @return The head.
    function head() internal view returns (bytes32) {
        return LibMigrationRegistry.headV3(WRITER, NAMESPACE);
    }

    /// @notice Whether `delegate` may write this repo's line.
    /// @param delegate The account asked about: a chain's Safe or timelock.
    /// @return `WRITER`'s approval of it for `NAMESPACE`.
    function approved(address delegate) internal view returns (bool) {
        return LibMigrationRegistry.approvedV3(WRITER, NAMESPACE, delegate);
    }

    /// @notice The prerequisite list for a migration applied onto
    /// `headMigration`.
    /// @param headMigration The head the migration is applied onto.
    /// @return The single-entry list naming the head.
    function onto(bytes32 headMigration) internal pure returns (Prerequisite[] memory) {
        return LibMigrationRegistry.onto(WRITER, NAMESPACE, headMigration);
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

/// @notice What a script in `script/` does. Only a `Migration` changes the
/// ownership, roles or configuration of live contracts, and only a
/// `Migration` carries a registry record.
enum ScriptKind {
    Migration,
    Deployment,
    TimelockRehearsal,
    TimelockExecutor
}

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

/// @notice What a script declares about itself. For a `Migration`: the
/// registry record its bundle writes, the writer by role, what it is recorded
/// after, and whether it is recorded later as history (`IStoxHistoryMigration`
/// gives when it ran). Every other kind declares no record.
struct ScriptDeclaration {
    ScriptKind kind;
    bytes32 namespace;
    bytes32 id;
    MigrationWriter writer;
    MigrationPrerequisite[] prerequisites;
    bool history;
}

/// @notice Every `script/*.s.sol` implements this; `BuildMigrations` reads it
/// and reverts on a script that does not, or whose declaration is invalid.
interface IStoxScript {
    /// @return The script's declaration.
    function declaration() external pure returns (ScriptDeclaration memory);
}

/// @notice A migration that ran before its record could be written.
interface IStoxHistoryMigration {
    /// @param chainId The chain id.
    /// @return When the migration executed on `chainId`, unix seconds.
    function executedAt(uint256 chainId) external pure returns (uint256);
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

/// @notice What a script declares about itself: whether it is a migration, one that
/// changes the ownership, roles or configuration of live contracts. For a migration: the
/// id of the record its bundle writes in `LibStoxMigrations`' line, and the
/// record it is applied onto (`MIGRATION_HEAD_GENESIS` for the line's first).
/// Every other kind declares no record.
struct ScriptDeclaration {
    bool migration;
    bytes32 id;
    bytes32 onto;
}

/// @notice Every `script/*.s.sol` implements this; `BuildMigrations` reads it
/// and reverts on a script that does not, or whose declaration is invalid.
interface IStoxScript {
    /// @return The script's declaration.
    function declaration() external pure returns (ScriptDeclaration memory);
}

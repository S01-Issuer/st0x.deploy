// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.26/src/interface/deprecated/IMigrationRegistryV3.sol";

import {MigrationPrerequisite, ScriptDeclaration} from "../interface/IStoxScript.sol";
import {LibStoxMigrations} from "./LibStoxMigrations.sol";

/// @notice A migration declares no namespace, no id, or the genesis id: it is
/// in no line.
/// @param script The script's path.
error MigrationWithoutRecord(string script);

/// @notice A migration declares nothing it is recorded after.
/// @param script The script's path.
error MigrationWithoutPrerequisite(string script);

/// @notice A script that is not a migration declares part of a record.
/// @param script The script's path.
error RecordOnNonMigration(string script);

/// @notice A record in this repo's namespace is not keyed by its script path.
/// @param script The script's path.
error IdNotScriptPath(string script);

/// @notice Two scripts declare the same id in one namespace. `migrations.json`
/// keys its rows by namespace and id, so an id names one migration whatever
/// its writer.
/// @param script The later script's path.
/// @param other The earlier script's path.
error DuplicateRecord(string script, string other);

/// @notice A migration's first prerequisite is not in its own line: the
/// registry takes it as the line's head, so it must be the migration's own
/// writer and namespace.
/// @param script The script's path.
error NotOntoOwnLine(string script);

/// @notice A prerequisite after the first is in the migration's own line,
/// which the registry refuses (`OwnPrerequisite`).
/// @param script The script's path.
/// @param index The prerequisite's index.
error OwnLinePrerequisite(string script, uint256 index);

/// @notice A prerequisite names no record another script declares under that
/// writer: not genesis as the head, and not a declared migration.
/// @param script The script's path.
/// @param index The prerequisite's index.
error UnknownPrerequisite(string script, uint256 index);

/// @notice Two migrations in one line are applied onto the same head, so at
/// most one of them can ever be recorded.
/// @param script The later script's path.
/// @param other The earlier script's path.
error ForkedLine(string script, string other);

/// @notice Following prerequisites from a migration comes back to it, so the
/// registry can never record any migration on that cycle.
/// @param script The path of the first script found on the cycle.
error PrerequisiteCycle(string script);

/// @notice `paths` and `declarations` differ in length.
error DeclarationCountMismatch();

/// @title LibScriptDeclarations
/// @notice The rules every script's declaration must satisfy, over all of
/// `script/` at once: each migration is a record the registry would accept,
/// in a line that starts at genesis and never forks, and no migration waits on
/// itself through any chain of prerequisites. `BuildMigrations` reverts
/// on the first violation, so a script that is not in a line fails CI rather
/// than reaching `migrations.json`.
library LibScriptDeclarations {
    /// @dev What `indexOf` returns for a prerequisite no declared migration is.
    uint256 internal constant NOT_FOUND = type(uint256).max;

    /// @dev A migration `visit` has entered and not yet left.
    uint256 private constant VISITING = 1;

    /// @dev A migration `visit` has left: nothing it waits on cycles.
    uint256 private constant VISITED = 2;

    /// @notice Revert on the first rule `declarations` break.
    /// @param paths Each script's path.
    /// @param declarations Each script's declaration, by index.
    function validate(string[] memory paths, ScriptDeclaration[] memory declarations) internal pure {
        if (paths.length != declarations.length) revert DeclarationCountMismatch();
        for (uint256 i = 0; i < declarations.length; i++) {
            ScriptDeclaration memory declared = declarations[i];
            if (declared.migration) {
                validateRecord(paths[i], declared);
            } else if (
                declared.namespace != 0 || declared.id != 0 || declared.prerequisites.length != 0 || declared.history
            ) {
                revert RecordOnNonMigration(paths[i]);
            }
        }
        for (uint256 i = 0; i < declarations.length; i++) {
            if (!declarations[i].migration) continue;
            validatePrerequisites(paths, declarations, i);
            validateAgainstEarlier(paths, declarations, i);
        }
        uint256[] memory states = new uint256[](declarations.length);
        for (uint256 i = 0; i < declarations.length; i++) {
            if (declarations[i].migration) visit(paths, declarations, states, i);
        }
    }

    /// @dev The record key and the first prerequisite's line.
    function validateRecord(string memory path, ScriptDeclaration memory declared) private pure {
        if (declared.namespace == 0 || declared.id == 0 || declared.id == MIGRATION_HEAD_GENESIS) {
            revert MigrationWithoutRecord(path);
        }
        if (declared.namespace == LibStoxMigrations.NAMESPACE && declared.id != keccak256(bytes(path))) {
            revert IdNotScriptPath(path);
        }
        if (declared.prerequisites.length == 0) revert MigrationWithoutPrerequisite(path);
        if (
            declared.prerequisites[0].writer != declared.writer
                || declared.prerequisites[0].namespace != declared.namespace
        ) {
            revert NotOntoOwnLine(path);
        }
    }

    /// @dev The head is genesis or a declared migration in the line; every
    /// later prerequisite is a declared migration outside the line.
    function validatePrerequisites(string[] memory paths, ScriptDeclaration[] memory declarations, uint256 i)
        private
        pure
    {
        ScriptDeclaration memory declared = declarations[i];
        if (
            declared.prerequisites[0].migration != MIGRATION_HEAD_GENESIS
                && indexOf(declarations, i, declared.prerequisites[0]) == NOT_FOUND
        ) {
            revert UnknownPrerequisite(paths[i], 0);
        }
        for (uint256 index = 1; index < declared.prerequisites.length; index++) {
            MigrationPrerequisite memory prerequisite = declared.prerequisites[index];
            if (prerequisite.writer == declared.writer && prerequisite.namespace == declared.namespace) {
                revert OwnLinePrerequisite(paths[i], index);
            }
            if (indexOf(declarations, i, prerequisite) == NOT_FOUND) revert UnknownPrerequisite(paths[i], index);
        }
    }

    /// @dev No earlier migration declares the same record, or the same head in
    /// the same line.
    function validateAgainstEarlier(string[] memory paths, ScriptDeclaration[] memory declarations, uint256 i)
        private
        pure
    {
        ScriptDeclaration memory declared = declarations[i];
        for (uint256 j = 0; j < i; j++) {
            ScriptDeclaration memory other = declarations[j];
            if (other.namespace != declared.namespace) continue;
            if (other.id == declared.id) revert DuplicateRecord(paths[i], paths[j]);
            if (
                other.writer == declared.writer
                    && other.prerequisites[0].migration == declared.prerequisites[0].migration
            ) {
                revert ForkedLine(paths[i], paths[j]);
            }
        }
    }

    /// @dev Depth-first over every prerequisite naming a declared migration;
    /// reaching one still `VISITING` closes a cycle. With no cycle, each line's
    /// heads end at genesis, since every head is genesis or a declared migration.
    function visit(string[] memory paths, ScriptDeclaration[] memory declarations, uint256[] memory states, uint256 i)
        private
        pure
    {
        if (states[i] == VISITED) return;
        if (states[i] == VISITING) revert PrerequisiteCycle(paths[i]);
        states[i] = VISITING;
        MigrationPrerequisite[] memory prerequisites = declarations[i].prerequisites;
        for (uint256 index = 0; index < prerequisites.length; index++) {
            uint256 at = indexOf(declarations, i, prerequisites[index]);
            if (at != NOT_FOUND) visit(paths, declarations, states, at);
        }
        states[i] = VISITED;
    }

    /// @dev The migration other than `i` that `prerequisite` names, or
    /// `NOT_FOUND`.
    function indexOf(ScriptDeclaration[] memory declarations, uint256 i, MigrationPrerequisite memory prerequisite)
        private
        pure
        returns (uint256)
    {
        for (uint256 j = 0; j < declarations.length; j++) {
            if (
                j != i && declarations[j].migration && declarations[j].namespace == prerequisite.namespace
                    && declarations[j].id == prerequisite.migration && declarations[j].writer == prerequisite.writer
            ) {
                return j;
            }
        }
        return NOT_FOUND;
    }
}

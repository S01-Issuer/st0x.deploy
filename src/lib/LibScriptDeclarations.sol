// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.18/src/interface/IMigrationRegistryV2.sol";

import {ScriptDeclaration, ScriptKind} from "../interface/IStoxScript.sol";
import {LibStoxMigrations} from "./LibStoxMigrations.sol";

/// @notice A migration declares no namespace or no id: it is in no line.
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

/// @notice Two scripts declare the same record.
/// @param script The later script's path.
/// @param other The earlier script's path.
error DuplicateRecord(string script, string other);

/// @notice A prerequisite is neither genesis nor a record another script
/// declares, under the writer that declares it.
/// @param script The script's path.
/// @param index The prerequisite's index.
error UnknownPrerequisite(string script, uint256 index);

/// @notice `paths` and `declarations` differ in length.
error DeclarationCountMismatch();

/// @title LibScriptDeclarations
/// @notice The rules every script's declaration must satisfy, over all of
/// `script/` at once. `BuildMigrations` reverts on the first violation, so a
/// script that is not in a line fails CI rather than reaching
/// `migrations.json`.
library LibScriptDeclarations {
    /// @notice Revert on the first rule `declarations` break.
    /// @param paths Each script's path.
    /// @param declarations Each script's declaration, by index.
    function validate(string[] memory paths, ScriptDeclaration[] memory declarations) internal pure {
        if (paths.length != declarations.length) revert DeclarationCountMismatch();
        for (uint256 i = 0; i < declarations.length; i++) {
            ScriptDeclaration memory d = declarations[i];
            if (d.kind != ScriptKind.Migration) {
                if (d.namespace != 0 || d.id != 0 || d.prerequisites.length != 0 || d.history) {
                    revert RecordOnNonMigration(paths[i]);
                }
                continue;
            }
            if (d.namespace == 0 || d.id == 0) revert MigrationWithoutRecord(paths[i]);
            if (d.prerequisites.length == 0) revert MigrationWithoutPrerequisite(paths[i]);
            if (d.namespace == LibStoxMigrations.NAMESPACE && d.id != keccak256(bytes(paths[i]))) {
                revert IdNotScriptPath(paths[i]);
            }
            for (uint256 j = 0; j < i; j++) {
                if (
                    declarations[j].kind == ScriptKind.Migration && declarations[j].namespace == d.namespace
                        && declarations[j].id == d.id
                ) {
                    revert DuplicateRecord(paths[i], paths[j]);
                }
            }
            for (uint256 p = 0; p < d.prerequisites.length; p++) {
                if (!declared(declarations, i, p)) revert UnknownPrerequisite(paths[i], p);
            }
        }
    }

    /// @dev Genesis, or another script's migration record under its writer.
    function declared(ScriptDeclaration[] memory declarations, uint256 i, uint256 p) private pure returns (bool) {
        ScriptDeclaration memory d = declarations[i];
        if (d.prerequisites[p].namespace == 0) return false;
        if (d.prerequisites[p].migration == MIGRATION_HEAD_GENESIS) return true;
        for (uint256 j = 0; j < declarations.length; j++) {
            if (
                j != i && declarations[j].kind == ScriptKind.Migration
                    && declarations[j].namespace == d.prerequisites[p].namespace
                    && declarations[j].id == d.prerequisites[p].migration
                    && declarations[j].writer == d.prerequisites[p].writer
            ) {
                return true;
            }
        }
        return false;
    }
}

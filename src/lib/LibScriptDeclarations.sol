// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.22/src/interface/IMigrationRegistryV3.sol";

import {ScriptDeclaration} from "../interface/IStoxScript.sol";

/// @notice A migration declares no id, or the genesis id: it is no record.
/// @param script The script's path.
error MigrationWithoutRecord(string script);

/// @notice A script that is not a migration declares part of a record.
/// @param script The script's path.
error RecordOnNonMigration(string script);

/// @notice A record is not keyed by its script path.
/// @param script The script's path.
error IdNotScriptPath(string script);

/// @notice A migration is applied onto neither genesis nor a record another
/// script declares.
/// @param script The script's path.
error UnknownHead(string script);

/// @notice Two migrations are applied onto the same head, so at most one of
/// them can ever be recorded.
/// @param script The later script's path.
/// @param other The earlier script's path.
error ForkedLine(string script, string other);

/// @notice Following heads from a migration comes back to it, so the registry
/// can never record any migration on that cycle.
/// @param script The path of the first script found on the cycle.
error HeadCycle(string script);

/// @notice `paths` and `declarations` differ in length.
error DeclarationCountMismatch();

/// @title LibScriptDeclarations
/// @notice The rules every script's declaration must satisfy, over all of
/// `script/` at once: each migration is a record keyed by its script path, in
/// the one line that starts at genesis and never forks. `BuildMigrations`
/// reverts on the first violation, so a script that is not in the line fails
/// CI rather than reaching `migrations.json`.
library LibScriptDeclarations {
    /// @dev What `indexOf` returns for a head no declared migration is.
    uint256 internal constant NOT_FOUND = type(uint256).max;

    /// @notice Revert on the first rule `declarations` break.
    /// @param paths Each script's path.
    /// @param declarations Each script's declaration, by index.
    function validate(string[] memory paths, ScriptDeclaration[] memory declarations) internal pure {
        if (paths.length != declarations.length) revert DeclarationCountMismatch();
        validateRecords(paths, declarations);
        validateHeads(paths, declarations);
        validateNoCycle(paths, declarations);
    }

    /// @dev Each migration is keyed by its script path; a non-migration
    /// carries no part of a record.
    function validateRecords(string[] memory paths, ScriptDeclaration[] memory declarations) private pure {
        for (uint256 i = 0; i < declarations.length; i++) {
            ScriptDeclaration memory declared = declarations[i];
            if (declared.migration) {
                if (declared.id == 0 || declared.id == MIGRATION_HEAD_GENESIS) revert MigrationWithoutRecord(paths[i]);
                if (declared.id != keccak256(bytes(paths[i]))) revert IdNotScriptPath(paths[i]);
            } else if (declared.id != 0 || declared.onto != 0) {
                revert RecordOnNonMigration(paths[i]);
            }
        }
    }

    /// @dev Each head is genesis or a declared migration, and no two
    /// migrations share one.
    function validateHeads(string[] memory paths, ScriptDeclaration[] memory declarations) private pure {
        for (uint256 i = 0; i < declarations.length; i++) {
            if (!declarations[i].migration) continue;
            if (
                declarations[i].onto != MIGRATION_HEAD_GENESIS
                    && indexOf(declarations, declarations[i].onto) == NOT_FOUND
            ) {
                revert UnknownHead(paths[i]);
            }
            for (uint256 j = 0; j < i; j++) {
                if (declarations[j].migration && declarations[j].onto == declarations[i].onto) {
                    revert ForkedLine(paths[i], paths[j]);
                }
            }
        }
    }

    /// @dev Every head is genesis or a declared migration (`validateHeads`), so
    /// following heads from any migration either reaches genesis or revisits
    /// one; more steps than there are migrations means it revisited.
    function validateNoCycle(string[] memory paths, ScriptDeclaration[] memory declarations) private pure {
        for (uint256 i = 0; i < declarations.length; i++) {
            if (!declarations[i].migration) continue;
            uint256 at = i;
            for (uint256 steps = 0; declarations[at].onto != MIGRATION_HEAD_GENESIS; steps++) {
                if (steps == declarations.length) revert HeadCycle(paths[i]);
                at = indexOf(declarations, declarations[at].onto);
            }
        }
    }

    /// @dev The declared migration recorded as `id`, or `NOT_FOUND`. Ids are
    /// script paths, so at most one migration has any id.
    function indexOf(ScriptDeclaration[] memory declarations, bytes32 id) private pure returns (uint256) {
        for (uint256 j = 0; j < declarations.length; j++) {
            if (declarations[j].migration && declarations[j].id == id) return j;
        }
        return NOT_FOUND;
    }
}

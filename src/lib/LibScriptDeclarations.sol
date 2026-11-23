// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";

import {ScriptDeclaration} from "../interface/IStoxScript.sol";

/// @notice A migration declares no id, or the genesis id.
/// @param script The script's path.
error MigrationWithoutRecord(string script);

/// @notice A record is not keyed by its script path.
/// @param script The script's path.
error IdNotScriptPath(string script);

/// @notice Two scripts declare the same id.
/// @param script The later script's path.
/// @param other The earlier script's path.
error DuplicateRecord(string script, string other);

/// @notice A migration's head is neither genesis nor a declared migration.
/// @param script The script's path.
error UnknownPrerequisite(string script);

/// @notice Two migrations are applied onto the same head, genesis included,
/// so at most one of them can ever be recorded.
/// @param script The later script's path.
/// @param other The earlier script's path.
error ForkedLine(string script, string other);

/// @notice Following heads from a migration comes back to it.
/// @param script The path of the first script found on the cycle.
error PrerequisiteCycle(string script);

/// @notice `paths` and `declarations` differ in length.
error DeclarationCountMismatch();

/// @title LibScriptDeclarations
/// @notice The rules every script's declaration on one chain must satisfy,
/// over all of `script/` at once: one line on the root namespace, with one
/// genesis, never forking, each id its script path.
library LibScriptDeclarations {
    /// @dev What `indexOf` returns for a head no declared migration is.
    uint256 internal constant NOT_FOUND = type(uint256).max;

    uint256 private constant VISITING = 1;

    uint256 private constant VISITED = 2;

    /// @notice Revert on the first rule `declarations` break.
    /// @param paths Each script's path.
    /// @param declarations Each script's declaration on one chain, by index.
    function validate(string[] memory paths, ScriptDeclaration[] memory declarations) internal pure {
        if (paths.length != declarations.length) revert DeclarationCountMismatch();
        for (uint256 i = 0; i < declarations.length; i++) {
            ScriptDeclaration memory declared = declarations[i];
            if (declared.id == 0 || declared.id == MIGRATION_HEAD_GENESIS) revert MigrationWithoutRecord(paths[i]);
            if (declared.id != keccak256(bytes(paths[i]))) revert IdNotScriptPath(paths[i]);
            for (uint256 j = 0; j < i; j++) {
                if (declarations[j].id == declared.id) revert DuplicateRecord(paths[i], paths[j]);
                if (declarations[j].onto == declared.onto) revert ForkedLine(paths[i], paths[j]);
            }
        }
        for (uint256 i = 0; i < declarations.length; i++) {
            if (
                declarations[i].onto != MIGRATION_HEAD_GENESIS
                    && indexOf(declarations, declarations[i].onto) == NOT_FOUND
            ) {
                revert UnknownPrerequisite(paths[i]);
            }
        }
        uint256[] memory states = new uint256[](declarations.length);
        for (uint256 i = 0; i < declarations.length; i++) {
            visit(paths, declarations, states, i);
        }
    }

    function visit(string[] memory paths, ScriptDeclaration[] memory declarations, uint256[] memory states, uint256 i)
        private
        pure
    {
        if (states[i] == VISITED) return;
        if (states[i] == VISITING) revert PrerequisiteCycle(paths[i]);
        states[i] = VISITING;
        uint256 at = indexOf(declarations, declarations[i].onto);
        if (at != NOT_FOUND) visit(paths, declarations, states, at);
        states[i] = VISITED;
    }

    /// @dev The declared migration whose id is `id`, or `NOT_FOUND`.
    function indexOf(ScriptDeclaration[] memory declarations, bytes32 id) private pure returns (uint256) {
        for (uint256 j = 0; j < declarations.length; j++) {
            if (declarations[j].id == id) return j;
        }
        return NOT_FOUND;
    }
}

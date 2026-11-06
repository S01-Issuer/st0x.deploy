// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

/// @notice A script's record on the root line (`LibRegistryAuthority.ROOT_AUTHORITY`,
/// `LibStoxMigrations.NAMESPACE`): its id, the head it is applied onto, and
/// whether it is recorded later as history.
struct ScriptDeclaration {
    bytes32 id;
    bytes32 onto;
    bool history;
}

/// @notice Every `script/*.s.sol` implements this; `BuildMigrations` reads it
/// and reverts on a script that does not, or whose declaration is invalid.
interface IStoxScript {
    /// @param chainId The chain id; history order differs per chain.
    /// @return The script's declaration on `chainId`.
    function declaration(uint256 chainId) external pure returns (ScriptDeclaration memory);
}

/// @notice A migration that ran before its record could be written.
interface IStoxHistoryMigration {
    /// @param chainId The chain id.
    /// @return When the migration executed on `chainId`, unix seconds.
    function executedAt(uint256 chainId) external pure returns (uint256);
}

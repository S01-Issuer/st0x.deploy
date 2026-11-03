// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IStoxScript, IStoxHistoryMigration, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";

/// @notice The rehearsal never runs live; the backfill bundle writes its record.
/// @param chainId The active chain id.
error ExecuteTimelockOperationsRecordedByBackfill(uint256 chainId);

/// @notice The rehearsal execute only ran on Base.
/// @param chainId The chain id asked for.
error ExecuteTimelockOperationsNotHistory(uint256 chainId);

/// @notice This script's declaration: onto the rehearsal cancel on every
/// chain; history on Base, record-only elsewhere.
/// @param chainId The chain id.
/// @return The declaration.
function executeTimelockOperationsDeclaration(uint256 chainId) pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.EXECUTE_TIMELOCK_OPERATIONS,
        onto: LibStoxMigrations.TIMELOCK_REHEARSAL_CANCEL,
        history: chainId == LibSafeInvariants.BASE_CHAIN_ID
    });
}

/// @title ExecuteTimelockOperations
/// @notice The timelock rehearsal execute (see `LibTimelockRehearsal`), run on
/// Base only; every chain's record is written by the backfill bundle.
contract ExecuteTimelockOperations is IStoxScript, IStoxHistoryMigration {
    /// @inheritdoc IStoxScript
    function declaration(uint256 chainId) external pure returns (ScriptDeclaration memory) {
        return executeTimelockOperationsDeclaration(chainId);
    }

    /// @inheritdoc IStoxHistoryMigration
    function executedAt(uint256 chainId) external pure returns (uint256) {
        if (chainId == LibSafeInvariants.BASE_CHAIN_ID) return 1787336483;
        revert ExecuteTimelockOperationsNotHistory(chainId);
    }

    function run() external view {
        revert ExecuteTimelockOperationsRecordedByBackfill(block.chainid);
    }
}

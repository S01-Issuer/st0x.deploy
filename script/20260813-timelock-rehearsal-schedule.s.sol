// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IStoxScript, IStoxHistoryMigration, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";

/// @notice The rehearsal never runs live; the backfill bundle writes its record.
/// @param chainId The active chain id.
error RehearsalScheduleRecordedByBackfill(uint256 chainId);

/// @notice The rehearsal schedule only executed on Base.
/// @param chainId The chain id asked for.
error RehearsalScheduleNotHistory(uint256 chainId);

/// @notice This script's declaration: on Base, history after the threshold
/// migration; elsewhere, record-only after the orchestrator emergency grant.
/// @param chainId The chain id.
/// @return The declaration.
function timelockRehearsalScheduleDeclaration(uint256 chainId) pure returns (ScriptDeclaration memory) {
    if (chainId == LibSafeInvariants.BASE_CHAIN_ID) {
        return ScriptDeclaration({
            id: LibStoxMigrations.TIMELOCK_REHEARSAL_SCHEDULE, onto: LibStoxMigrations.MULTISIG_THRESHOLD, history: true
        });
    }
    return ScriptDeclaration({
        id: LibStoxMigrations.TIMELOCK_REHEARSAL_SCHEDULE,
        onto: LibStoxMigrations.ORCHESTRATOR_EMERGENCY,
        history: false
    });
}

/// @title TimelockRehearsalSchedule
/// @notice The timelock rehearsal schedule (see `LibTimelockRehearsal`), run on
/// Base only; every chain's record is written by the backfill bundle.
contract TimelockRehearsalSchedule is IStoxScript, IStoxHistoryMigration {
    /// @inheritdoc IStoxScript
    function declaration(uint256 chainId) external pure returns (ScriptDeclaration memory) {
        return timelockRehearsalScheduleDeclaration(chainId);
    }

    /// @inheritdoc IStoxHistoryMigration
    function executedAt(uint256 chainId) external pure returns (uint256) {
        if (chainId == LibSafeInvariants.BASE_CHAIN_ID) return 1787076699;
        revert RehearsalScheduleNotHistory(chainId);
    }

    function run() external view {
        revert RehearsalScheduleRecordedByBackfill(block.chainid);
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {IStoxHistoryMigration, IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";

/// @notice The grant already ran on every chain; the backfill bundle writes its record.
/// @param chainId The active chain id.
error OrchestratorEmergencyRecordedByBackfill(uint256 chainId);

/// @notice The emergency grant did not run on `chainId`.
/// @param chainId The chain id.
error NoOrchestratorEmergencyOnChain(uint256 chainId);

/// @notice This script's declaration: the root line's history record of the
/// emergency grant, after the EU authoriser-role grant.
/// @return The declaration.
function grantOrchestratorEmergencyDeclaration() pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.ORCHESTRATOR_EMERGENCY, onto: LibStoxMigrations.GRANT_EU_AUTHORISER_ROLES, history: true
    });
}

/// @title GrantOrchestratorEmergency
/// @notice The grant of `EMERGENCY_ROLE` on the orchestrator to each chain's
/// token-owner Safe, already executed everywhere; every chain's record is
/// written as history by the backfill bundle.
contract GrantOrchestratorEmergency is IStoxScript, IStoxHistoryMigration {
    /// @inheritdoc IStoxHistoryMigration
    function executedAt(uint256 chainId) external pure returns (uint256) {
        if (chainId == LibSafeInvariants.BASE_CHAIN_ID) return 1_792_605_015;
        if (chainId == LibSafeInvariants.ETHEREUM_CHAIN_ID) return 1_792_605_299;
        if (chainId == LibSafeInvariants.HYPEREVM_CHAIN_ID) return 1_792_605_977;
        if (chainId == LibSafeInvariants.ROBINHOOD_CHAIN_ID) return 1_792_606_175;
        if (chainId == LibSafeInvariants.BSC_CHAIN_ID) return 1_792_605_822;
        revert NoOrchestratorEmergencyOnChain(chainId);
    }

    /// @inheritdoc IStoxScript
    function declaration(uint256) external pure returns (ScriptDeclaration memory) {
        return grantOrchestratorEmergencyDeclaration();
    }

    function run() external view {
        revert OrchestratorEmergencyRecordedByBackfill(block.chainid);
    }
}

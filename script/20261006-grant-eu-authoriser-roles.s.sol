// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {IStoxHistoryMigration, IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";

/// @notice The grant already ran on every chain; the backfill bundle writes its record.
/// @param chainId The active chain id.
error GrantEuAuthoriserRolesRecordedByBackfill(uint256 chainId);

/// @notice The EU grant did not run on `chainId`.
/// @param chainId The chain id.
error NoGrantEuAuthoriserRolesOnChain(uint256 chainId);

/// @notice This script's declaration on the root line: after the
/// governance-timelock history, recorded as history at its V2 moment.
/// @return The declaration.
function grantEuAuthoriserRolesDeclaration() pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.GRANT_EU_AUTHORISER_ROLES, onto: LibStoxMigrations.GOVERNANCE_TIMELOCK, history: true
    });
}

/// @title GrantEuAuthoriserRoles
/// @notice The pinned role map on the EU assets authoriser clone and the admin
/// handover to the timelock, already executed everywhere; every chain's record
/// is written as history by the backfill bundle.
contract GrantEuAuthoriserRoles is IStoxScript, IStoxHistoryMigration {
    /// @inheritdoc IStoxHistoryMigration
    function executedAt(uint256 chainId) external pure returns (uint256) {
        if (chainId == LibSafeInvariants.BASE_CHAIN_ID) return 1_791_457_413;
        if (chainId == LibSafeInvariants.ETHEREUM_CHAIN_ID) return 1_792_605_263;
        if (chainId == LibSafeInvariants.HYPEREVM_CHAIN_ID) return 1_792_605_943;
        if (chainId == LibSafeInvariants.ROBINHOOD_CHAIN_ID) return 1_792_606_144;
        if (chainId == LibSafeInvariants.BSC_CHAIN_ID) return 1_792_605_427;
        revert NoGrantEuAuthoriserRolesOnChain(chainId);
    }

    /// @inheritdoc IStoxScript
    function declaration(uint256) external pure returns (ScriptDeclaration memory) {
        return grantEuAuthoriserRolesDeclaration();
    }

    function run() external view {
        revert GrantEuAuthoriserRolesRecordedByBackfill(block.chainid);
    }
}

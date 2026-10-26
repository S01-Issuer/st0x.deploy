// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.22/src/lib/LibMigrationRegistry.sol";

import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {migrateMultisigThresholdDeclaration} from "../../script/20260619-migrate-multisig-threshold.s.sol";
import {migrateGovernanceToTimelockDeclaration} from "../../script/20260729-migrate-governance-to-timelock.s.sol";
import {grantEuAuthoriserRolesDeclaration} from "../../script/20261006-grant-eu-authoriser-roles.s.sol";
import {grantOrchestratorEmergencyDeclaration} from "../../script/20261006-grant-orchestrator-emergency.s.sol";
import {orchestratorAdminToTimelockDeclaration} from "../../script/20261006-orchestrator-admin-to-timelock.s.sol";
import {retireDirectSignerRolesDeclaration} from "../../script/20260831-retire-direct-signer-roles.s.sol";

/// @title LibMigrationLineFork
/// @notice Puts a fork's st0x.deploy line where a migration script expects
/// it, as `LibStoxMigrations.WRITER` would.
library LibMigrationLineFork {
    /// @notice The line's migrations in order.
    /// @return The declarations.
    function line() internal pure returns (ScriptDeclaration[] memory) {
        ScriptDeclaration[] memory all = new ScriptDeclaration[](6);
        all[0] = migrateMultisigThresholdDeclaration();
        all[1] = migrateGovernanceToTimelockDeclaration();
        all[2] = grantEuAuthoriserRolesDeclaration();
        all[3] = grantOrchestratorEmergencyDeclaration();
        all[4] = orchestratorAdminToTimelockDeclaration();
        all[5] = retireDirectSignerRolesDeclaration();
        return all;
    }

    /// @notice `WRITER` approves `delegate` to write its line.
    /// @param vm The cheatcodes.
    /// @param delegate The account approved.
    function approve(Vm vm, address delegate) internal {
        vm.prank(LibStoxMigrations.WRITER);
        LibMigrationRegistry.approveV3(LibStoxMigrations.NAMESPACE, delegate);
    }

    /// @notice `WRITER` withdraws `delegate`'s approval.
    /// @param vm The cheatcodes.
    /// @param delegate The account revoked.
    function revoke(Vm vm, address delegate) internal {
        vm.prank(LibStoxMigrations.WRITER);
        LibMigrationRegistry.revokeV3(LibStoxMigrations.NAMESPACE, delegate);
    }

    /// @notice `WRITER` records every migration before `declared`, so the
    /// line's head is `declared.onto`.
    /// @param vm The cheatcodes.
    /// @param declared The migration about to be applied.
    function recordOnto(Vm vm, ScriptDeclaration memory declared) internal {
        ScriptDeclaration[] memory all = line();
        for (uint256 i = 0; i < all.length && all[i].id != declared.id; i++) {
            if (LibStoxMigrations.applied(all[i].id) != 0) continue;
            vm.prank(LibStoxMigrations.WRITER);
            LibMigrationRegistry.applyMigrationV3(
                LibStoxMigrations.WRITER, LibStoxMigrations.NAMESPACE, all[i].id, LibStoxMigrations.onto(all[i].onto)
            );
        }
    }
}

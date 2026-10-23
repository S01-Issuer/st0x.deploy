// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/StdCheats.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.22/src/interface/IMigrationRegistryV3.sol";
import {IMigrationRegistryV2} from "rain-deploy-0.1.22/src/interface/deprecated/IMigrationRegistryV2.sol";
import {DEPLOYED_ADDRESS as REGISTRY_V2} from "rain-deploy-0.1.22/src/generated/0_1_18/MigrationRegistry.sol";
import {LibSafeFork} from "rain-deploy-0.1.22/src/lib/LibSafeFork.sol";

import {BackfillMigrationRegistryV3Harness} from "../script/BackfillMigrationRegistryV3Harness.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";

library LibTestV3Backfill {
    /// @notice Execute the V3 backfill bundle on the fork if the chain has
    /// not: the Safe's V3 line is at genesis and its V2 line holds the records
    /// the backfill carries.
    function executeIfPending(Vm vm, address safe) internal {
        if (LibStoxMigrations.head(safe) != MIGRATION_HEAD_GENESIS) return;
        if (
            IMigrationRegistryV2(REGISTRY_V2).head(safe, LibStoxMigrations.NAMESPACE)
                != LibStoxMigrations.ORCHESTRATOR_EMERGENCY
        ) return;
        BackfillMigrationRegistryV3Harness backfill = new BackfillMigrationRegistryV3Harness("fork-prerequisite");
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), backfill.callAuthorBundle());
    }
}

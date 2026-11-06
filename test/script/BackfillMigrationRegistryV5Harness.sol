// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {BackfillMigrationRegistryV5} from "../../script/20261030-backfill-migration-registry-v5.s.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {SafeBundleScriptHooks} from "../lib/SafeBundleScriptHooks.sol";

/// @dev The backfill reads no script for `id`.
error NoBackfillScript(bytes32 id);

contract BackfillMigrationRegistryV5Harness is BackfillMigrationRegistryV5, SafeBundleScriptHooks {
    constructor(string memory artifactTag) SafeBundleScriptHooks(artifactTag) {}

    /// @inheritdoc BackfillMigrationRegistryV5
    function artifactPath() internal view override returns (string memory) {
        return tagged(super.artifactPath());
    }

    function callScriptArtifactPath() external view returns (string memory) {
        return BackfillMigrationRegistryV5.artifactPath();
    }

    function scriptOf(bytes32 id) external view returns (address) {
        if (id == LibStoxMigrations.MULTISIG_THRESHOLD) return MULTISIG_THRESHOLD_SCRIPT;
        if (id == LibStoxMigrations.TIMELOCK_REHEARSAL_SCHEDULE) return REHEARSAL_SCHEDULE_SCRIPT;
        if (id == LibStoxMigrations.TIMELOCK_REHEARSAL_CANCEL) return REHEARSAL_CANCEL_SCRIPT;
        if (id == LibStoxMigrations.EXECUTE_TIMELOCK_OPERATIONS) return EXECUTE_TIMELOCK_OPERATIONS_SCRIPT;
        if (id == LibStoxMigrations.GOVERNANCE_TIMELOCK) return GOVERNANCE_TIMELOCK_SCRIPT;
        if (id == LibStoxMigrations.GRANT_EU_AUTHORISER_ROLES) return EU_AUTHORISER_SCRIPT;
        if (id == LibStoxMigrations.ORCHESTRATOR_EMERGENCY) return ORCHESTRATOR_EMERGENCY_SCRIPT;
        revert NoBackfillScript(id);
    }
}

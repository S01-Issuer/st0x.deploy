// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {BackfillMigrationRegistryV5} from "../../script/20261030-backfill-migration-registry-v5.s.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";

/// @dev The backfill reads no script for `id`.
error NoBackfillScript(bytes32 id);

/// @dev Exposes the script's hooks and the scripts it reads each record from,
/// with a per-instance artifact path because tests run in parallel.
contract BackfillMigrationRegistryV5Harness is BackfillMigrationRegistryV5 {
    string internal sArtifactTag;

    constructor(string memory artifactTag) {
        sArtifactTag = artifactTag;
    }

    /// @inheritdoc BackfillMigrationRegistryV5
    function artifactPath() internal view override returns (string memory) {
        return string.concat(
            "out/20261030-backfill-migration-registry-v5-", vm.toString(block.chainid), "-", sArtifactTag, ".json"
        );
    }

    function callPreflight() external view {
        preflight();
    }

    function callAuthorBundle() external view returns (SafeTx[] memory) {
        return authorBundle();
    }

    function callArtifactPath() external view returns (string memory) {
        return artifactPath();
    }

    function callScriptArtifactPath() external view returns (string memory) {
        return super.artifactPath();
    }

    function callAssertPostState() external view {
        assertPostState();
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

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.29/src/abstract/SafeBundleScript.sol";
import {IMigrationRegistryV3} from "rain-deploy-0.1.29/src/interface/deprecated/IMigrationRegistryV3.sol";
import {DEPLOYED_ADDRESS as REGISTRY_V3} from "rain-deploy-0.1.29/src/generated/0_1_25/MigrationRegistry.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.29/src/lib/LibMigrationRegistry.sol";
import {SafeTx} from "rain-deploy-0.1.29/src/lib/LibSafeTx.sol";

import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {migrateGovernanceToTimelockDeclaration} from "./20260729-migrate-governance-to-timelock.s.sol";
import {grantEuAuthoriserRolesDeclaration} from "./20261006-grant-eu-authoriser-roles.s.sol";
import {grantOrchestratorEmergencyDeclaration} from "./20261006-grant-orchestrator-emergency.s.sol";
import {backfillMigrationRegistryV3Declaration} from "./20261022-backfill-migration-registry-v3.s.sol";
import {orchestratorAdminToTimelockDeclaration} from "./20261006-orchestrator-admin-to-timelock.s.sol";
import {migrateMultisigThresholdDeclaration} from "./20260619-migrate-multisig-threshold.s.sol";

/// @notice After the bundle, a V5 record differs from its V3 record.
/// @param migration The record.
/// @param expected The V3 moment.
/// @param actual The V5 moment.
error BackfillV5RecordMismatch(bytes32 migration, uint256 expected, uint256 actual);

/// @notice After the bundle, V5 holds this script's predecessor but not this
/// script's own record.
/// @param migration The missing record.
error BackfillV5RecordMissing(bytes32 migration);

/// @notice This script's declaration: the Safe's record after the last
/// record in its deploy line.
/// @return The declaration.
function backfillMigrationRegistryV5Declaration() pure returns (ScriptDeclaration memory) {
    return LibStoxMigrations.safeMigrationOnto(
        LibStoxMigrations.NAMESPACE,
        LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5,
        migrateMultisigThresholdDeclaration().id,
        false
    );
}

/// @title BackfillMigrationRegistryV5
/// @notice Authors the per-chain Safe Tx Builder bundle that replays the
/// chain's token-owner Safe's records from the V3 `MigrationRegistry` onto
/// the V5 `MigrationRegistry`, each as history at its V3 moment and from its
/// own script's declaration, in line order. A record V3 does not hold ends
/// its line's replay; a record V5 already holds is skipped. The bundle ends
/// with this script's own record when V5's deploy line is headed by its
/// declared predecessor.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20261030-backfill-migration-registry-v5` per chain.
contract BackfillMigrationRegistryV5 is SafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return backfillMigrationRegistryV5Declaration();
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x: backfill MigrationRegistry V5 from V3";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261030-backfill-migration-registry-v5-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @notice The Safe's lines, each in order from genesis.
    function lines() internal pure returns (ScriptDeclaration[][] memory) {
        ScriptDeclaration[][] memory all = new ScriptDeclaration[][](2);
        all[0] = new ScriptDeclaration[](5);
        all[0][0] = migrateGovernanceToTimelockDeclaration();
        all[0][1] = grantOrchestratorEmergencyDeclaration();
        all[0][2] = backfillMigrationRegistryV3Declaration();
        all[0][3] = orchestratorAdminToTimelockDeclaration();
        all[0][4] = migrateMultisigThresholdDeclaration();
        all[1] = new ScriptDeclaration[](1);
        all[1][0] = grantEuAuthoriserRolesDeclaration();
        return all;
    }

    function v3Moment(address chainSafe, ScriptDeclaration memory declared) internal view returns (uint256) {
        return IMigrationRegistryV3(REGISTRY_V3).appliedV3(chainSafe, declared.namespace, declared.id);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The Safe and timelock are what this repo pins.
    function preflight() internal view override {
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibTimelockInvariants.assertTimelockState(LibTimelockInvariants.timelockForChainId(block.chainid), chainSafe);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Each V3-held record V5 lacks, as history at its V3 moment, then
    /// this script's own record if its predecessor heads V5's deploy line
    /// after the replay and V5 does not hold it yet.
    function authorBundle() internal view override returns (SafeTx[] memory) {
        address chainSafe = address(safe());
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        ScriptDeclaration[][] memory all = lines();
        uint256 count = 0;
        bytes32 deployHead = LibStoxMigrations.head(chainSafe);
        for (uint256 i = 0; i < all.length; i++) {
            for (uint256 j = 0; j < all[i].length; j++) {
                ScriptDeclaration memory declared = all[i][j];
                if (v3Moment(chainSafe, declared) == 0) break;
                if (LibMigrationRegistry.appliedV5(chainSafe, declared.namespace, declared.id) != 0) continue;
                count++;
                if (i == 0) deployHead = declared.id;
            }
        }
        ScriptDeclaration memory own = backfillMigrationRegistryV5Declaration();
        bool recordOwn =
            deployHead == own.prerequisites[0].migration && LibStoxMigrations.applied(chainSafe, own.id) == 0;
        if (recordOwn) count++;
        SafeTx[] memory txs = new SafeTx[](count);
        uint256 k = 0;
        for (uint256 i = 0; i < all.length; i++) {
            for (uint256 j = 0; j < all[i].length; j++) {
                ScriptDeclaration memory declared = all[i][j];
                uint256 at = v3Moment(chainSafe, declared);
                if (at == 0) break;
                if (LibMigrationRegistry.appliedV5(chainSafe, declared.namespace, declared.id) != 0) continue;
                (address to, bytes memory data) = LibStoxMigrations.historyCall(declared, at, chainSafe, timelock);
                txs[k++] = SafeTx({to: to, value: 0, data: data, operation: Enum.Operation.Call});
            }
        }
        if (recordOwn) {
            (address to, bytes memory data) = LibStoxMigrations.recordCall(own, chainSafe, timelock);
            txs[k] = SafeTx({to: to, value: 0, data: data, operation: Enum.Operation.Call});
        }
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Every V3-held record has its V3 moment on V5, and V5 holds this
    /// script's record wherever V5 holds its predecessor.
    function assertPostState() internal view override {
        address chainSafe = address(safe());
        ScriptDeclaration[][] memory all = lines();
        for (uint256 i = 0; i < all.length; i++) {
            for (uint256 j = 0; j < all[i].length; j++) {
                ScriptDeclaration memory declared = all[i][j];
                uint256 expected = v3Moment(chainSafe, declared);
                if (expected == 0) break;
                uint256 actual = LibMigrationRegistry.appliedV5(chainSafe, declared.namespace, declared.id);
                if (actual != expected) revert BackfillV5RecordMismatch(declared.id, expected, actual);
            }
        }
        ScriptDeclaration memory own = backfillMigrationRegistryV5Declaration();
        if (
            LibStoxMigrations.applied(chainSafe, own.prerequisites[0].migration) != 0
                && LibStoxMigrations.applied(chainSafe, own.id) == 0
        ) {
            revert BackfillV5RecordMissing(own.id);
        }
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
    }
}

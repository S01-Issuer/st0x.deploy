// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.29/src/abstract/SafeBundleScript.sol";
import {IMigrationRegistryV2} from "rain-deploy-0.1.29/src/interface/deprecated/IMigrationRegistryV2.sol";
import {
    DEPLOYED_ADDRESS as REGISTRY_V2,
    BYTECODE_HASH as REGISTRY_V2_CODEHASH
} from "rain-deploy-0.1.29/src/generated/0_1_18/MigrationRegistry.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.29/src/lib/LibMigrationRegistry.sol";
import {SafeTx} from "rain-deploy-0.1.29/src/lib/LibSafeTx.sol";

import {LibRbacMigration} from "../src/lib/LibRbacMigration.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {migrateGovernanceToTimelockDeclaration} from "./20260729-migrate-governance-to-timelock.s.sol";
import {grantEuAuthoriserRolesDeclaration} from "./20261006-grant-eu-authoriser-roles.s.sol";
import {grantOrchestratorEmergencyDeclaration} from "./20261006-grant-orchestrator-emergency.s.sol";

/// @notice The code at the V2 registry address is not the frozen 0.1.18
/// registry.
/// @param actualCodeHash The code hash found.
error UnexpectedRegistryV2CodeHash(bytes32 actualCodeHash);

/// @notice A V2 line does not end where this backfill expects, so it holds a
/// record this script does not know how to carry over.
/// @param namespace The line's namespace.
/// @param head The line's V2 head.
error UnexpectedRegistryV2Line(bytes32 namespace, bytes32 head);

/// @notice A V2 record is not applied onto the record this backfill replays
/// it onto.
/// @param migration The record.
/// @param onto What V2 says it was applied onto.
error UnexpectedRegistryV2Order(bytes32 migration, bytes32 onto);

/// @notice The V2 governance-timelock record disagrees with the moment
/// `LibStoxMigrations.governanceTimelockExecution` pins.
/// @param pinned The pinned moment.
/// @param recorded The V2 moment.
error GovernanceTimelockMomentMismatch(uint256 pinned, uint256 recorded);

/// @notice After the bundle, a V5 record differs from its V2 record.
/// @param migration The record.
/// @param expected The V2 moment.
/// @param actual The V5 moment.
error BackfillV5RecordMismatch(bytes32 migration, uint256 expected, uint256 actual);

/// @notice After the bundle, V5 does not hold this script's own record.
/// @param migration The missing record.
error BackfillV5RecordMissing(bytes32 migration);

/// @notice This script's declaration: the Safe's record after the last V2
/// record in its deploy line.
/// @return The declaration.
function backfillMigrationRegistryV5Declaration() pure returns (ScriptDeclaration memory) {
    return LibStoxMigrations.safeMigrationOnto(
        LibStoxMigrations.NAMESPACE,
        LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5,
        grantOrchestratorEmergencyDeclaration().id,
        false
    );
}

/// @title BackfillMigrationRegistryV5
/// @notice Authors the per-chain Safe Tx Builder bundle that replays the
/// chain's token-owner Safe's records from the frozen V2 `MigrationRegistry`
/// onto the V5 `MigrationRegistry`, each as history at its V2 moment and
/// from its own script's declaration, in line order:
///
/// 1. `st0x.deploy`: `GOVERNANCE_TIMELOCK` onto genesis.
/// 2. `st0x.deploy`: `ORCHESTRATOR_EMERGENCY` onto `GOVERNANCE_TIMELOCK`.
/// 3. `st0x.rbac`: `EU_AUTHORISER_GRANT_AND_HANDOVER` onto genesis.
/// 4. `st0x.deploy`: this script's own record onto `ORCHESTRATOR_EMERGENCY`.
///
/// A record V5 already holds is skipped.
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
        return "ST0x: backfill MigrationRegistry V5 from V2";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261030-backfill-migration-registry-v5-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @notice The Safe's V2 records, in replay order.
    function records() internal pure returns (ScriptDeclaration[] memory) {
        ScriptDeclaration[] memory all = new ScriptDeclaration[](3);
        all[0] = migrateGovernanceToTimelockDeclaration();
        all[1] = grantOrchestratorEmergencyDeclaration();
        all[2] = grantEuAuthoriserRolesDeclaration();
        return all;
    }

    /// @notice The Safe's V2 moment for `declared`, after checking it was
    /// applied onto its declared predecessor.
    function v2Moment(address chainSafe, ScriptDeclaration memory declared) internal view returns (uint256) {
        bytes32 onto = declared.prerequisites[0].migration;
        bytes32 actualOnto = IMigrationRegistryV2(REGISTRY_V2).appliedOnto(chainSafe, declared.namespace, declared.id);
        if (actualOnto != onto) revert UnexpectedRegistryV2Order(declared.id, actualOnto);
        return IMigrationRegistryV2(REGISTRY_V2).applied(chainSafe, declared.namespace, declared.id);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The Safe and timelock are what this repo pins, V2 is the frozen
    /// 0.1.18 registry, and the V2 lines hold exactly the three records in
    /// order, the governance-timelock one at its pinned moment.
    function preflight() internal view override {
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibTimelockInvariants.assertTimelockState(LibTimelockInvariants.timelockForChainId(block.chainid), chainSafe);

        if (REGISTRY_V2.codehash != REGISTRY_V2_CODEHASH) revert UnexpectedRegistryV2CodeHash(REGISTRY_V2.codehash);
        bytes32 deployHead = IMigrationRegistryV2(REGISTRY_V2).head(chainSafe, LibStoxMigrations.NAMESPACE);
        if (deployHead != LibStoxMigrations.ORCHESTRATOR_EMERGENCY) {
            revert UnexpectedRegistryV2Line(LibStoxMigrations.NAMESPACE, deployHead);
        }
        bytes32 rbacHead = IMigrationRegistryV2(REGISTRY_V2).head(chainSafe, LibRbacMigration.STOX_RBAC_NAMESPACE);
        if (rbacHead != LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER) {
            revert UnexpectedRegistryV2Line(LibRbacMigration.STOX_RBAC_NAMESPACE, rbacHead);
        }
        ScriptDeclaration[] memory all = records();
        for (uint256 i = 0; i < all.length; i++) {
            v2Moment(chainSafe, all[i]);
        }
        (uint256 pinned,) = LibStoxMigrations.governanceTimelockExecution(block.chainid);
        uint256 recorded = v2Moment(chainSafe, all[0]);
        if (recorded != pinned) revert GovernanceTimelockMomentMismatch(pinned, recorded);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Each V2 record V5 lacks, as history at its V2 moment, then this
    /// script's own record if V5 lacks it.
    function authorBundle() internal view override returns (SafeTx[] memory) {
        address chainSafe = address(safe());
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        ScriptDeclaration[] memory all = records();
        ScriptDeclaration memory own = backfillMigrationRegistryV5Declaration();
        bool recordOwn = LibStoxMigrations.applied(chainSafe, own.id) == 0;
        SafeTx[] memory txs = new SafeTx[](all.length + 1);
        uint256 k = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (LibMigrationRegistry.appliedV5(chainSafe, all[i].namespace, all[i].id) != 0) continue;
            (address to, bytes memory data) =
                LibStoxMigrations.historyCall(all[i], v2Moment(chainSafe, all[i]), chainSafe, timelock);
            txs[k++] = SafeTx({to: to, value: 0, data: data, operation: Enum.Operation.Call});
        }
        if (recordOwn) {
            (address to, bytes memory data) = LibStoxMigrations.recordCall(own, chainSafe, timelock);
            txs[k++] = SafeTx({to: to, value: 0, data: data, operation: Enum.Operation.Call});
        }
        SafeTx[] memory bundle = new SafeTx[](k);
        for (uint256 i = 0; i < k; i++) {
            bundle[i] = txs[i];
        }
        return bundle;
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Every V2 record has its V2 moment on V5, V5 holds this script's
    /// record, and the Safe policy holds.
    function assertPostState() internal view override {
        address chainSafe = address(safe());
        ScriptDeclaration[] memory all = records();
        for (uint256 i = 0; i < all.length; i++) {
            uint256 expected = IMigrationRegistryV2(REGISTRY_V2).applied(chainSafe, all[i].namespace, all[i].id);
            uint256 actual = LibMigrationRegistry.appliedV5(chainSafe, all[i].namespace, all[i].id);
            if (actual != expected) revert BackfillV5RecordMismatch(all[i].id, expected, actual);
        }
        bytes32 own = backfillMigrationRegistryV5Declaration().id;
        if (LibStoxMigrations.applied(chainSafe, own) == 0) revert BackfillV5RecordMissing(own);
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
    }
}

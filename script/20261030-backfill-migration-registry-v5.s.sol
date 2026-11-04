// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.30/src/abstract/SafeBundleScript.sol";
import {IMigrationRegistryV2} from "rain-deploy-0.1.30/src/interface/deprecated/IMigrationRegistryV2.sol";
import {
    DEPLOYED_ADDRESS as REGISTRY_V2,
    BYTECODE_HASH as REGISTRY_V2_CODEHASH
} from "rain-deploy-0.1.30/src/generated/0_1_18/MigrationRegistry.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.30/src/lib/LibMigrationRegistry.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {IStoxHistoryMigration, IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";

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

/// @notice A V2 record's moment differs from its script's `executedAt`.
/// @param migration The record.
/// @param executedAt The script's moment.
/// @param recorded The V2 moment.
error HistoryMomentMismatch(bytes32 migration, uint256 executedAt, uint256 recorded);

/// @notice After the bundle, a V5 record differs from its expected moment.
/// @param migration The record.
/// @param expected The script's moment.
/// @param actual The V5 moment.
error BackfillV5RecordMismatch(bytes32 migration, uint256 expected, uint256 actual);

/// @notice After the bundle, a V5 record is applied onto a different record
/// than this backfill replays it onto.
/// @param migration The record.
/// @param onto What V5 says it was applied onto.
error BackfillV5OrderMismatch(bytes32 migration, bytes32 onto);

/// @notice After the bundle, V5 does not hold a record this backfill writes.
/// @param migration The missing record.
error BackfillV5RecordMissing(bytes32 migration);

/// @notice The frozen V2 rbac line the EU grant was recorded on.
bytes32 constant V2_RBAC_NAMESPACE = keccak256("st0x.rbac");

/// @notice The EU grant's V2 id on `V2_RBAC_NAMESPACE`.
bytes32 constant V2_EU_AUTHORISER_GRANT_AND_HANDOVER = keccak256("st0x.rbac.eu-assets-authoriser.grant-and-handover");

/// @notice This script's declaration: last record of the chain's block, after
/// orchestrator-emergency on Base and after the record-only rehearsal entries
/// elsewhere.
/// @return The declaration.
function backfillMigrationRegistryV5Declaration(uint256 chainId) pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5,
        onto: chainId == LibSafeInvariants.BASE_CHAIN_ID
            ? LibStoxMigrations.ORCHESTRATOR_EMERGENCY
            : LibStoxMigrations.EXECUTE_TIMELOCK_OPERATIONS,
        history: false
    });
}

/// @notice One record this backfill writes: the script that declares it,
/// its root-line declaration, and where V2 holds it (zero `v2Id` when it has
/// no V2 record). A history record is written at the script's `executedAt`.
struct BackfillRecord {
    address script;
    ScriptDeclaration declared;
    bytes32 v2Namespace;
    bytes32 v2Id;
    bytes32 v2Onto;
}

/// @title BackfillMigrationRegistryV5
/// @notice Authors the per-chain Safe Tx Builder bundle that writes the
/// chain's history onto the V5 root line (`ROOT_AUTHORITY`,
/// `LibStoxMigrations.NAMESPACE`), each history record at its script's
/// `IStoxHistoryMigration.executedAt`:
///
/// 1. `MULTISIG_THRESHOLD` onto `MIGRATION_HEAD_GENESIS`.
/// 2. Base only: `TIMELOCK_REHEARSAL_SCHEDULE`, `TIMELOCK_REHEARSAL_CANCEL`,
///    `EXECUTE_TIMELOCK_OPERATIONS` as history.
/// 3. `GOVERNANCE_TIMELOCK`, the EU grant, `ORCHESTRATOR_EMERGENCY`, each
///    checked against its V2 moment.
/// 4. Off Base: `TIMELOCK_REHEARSAL_SCHEDULE`, `TIMELOCK_REHEARSAL_CANCEL`,
///    `EXECUTE_TIMELOCK_OPERATIONS` record-only.
/// 5. This script's own record.
///
/// The Safe, an unscoped delegate of the root, writes every record. A record
/// V5 already holds is skipped.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20261030-backfill-migration-registry-v5` per chain.
contract BackfillMigrationRegistryV5 is SafeBundleScript, IStoxScript {
    address internal immutable MULTISIG_THRESHOLD_SCRIPT =
        vm.deployCode("20260619-migrate-multisig-threshold.s.sol:MigrateMultisigThreshold");
    address internal immutable REHEARSAL_SCHEDULE_SCRIPT =
        vm.deployCode("20260813-timelock-rehearsal-schedule.s.sol:TimelockRehearsalSchedule");
    address internal immutable REHEARSAL_CANCEL_SCRIPT =
        vm.deployCode("20260813-timelock-rehearsal-cancel.s.sol:TimelockRehearsalCancel");
    address internal immutable EXECUTE_TIMELOCK_OPERATIONS_SCRIPT =
        vm.deployCode("20260813-execute-timelock-operations.s.sol:ExecuteTimelockOperations");
    address internal immutable GOVERNANCE_TIMELOCK_SCRIPT =
        vm.deployCode("20260729-migrate-governance-to-timelock.s.sol:MigrateGovernanceToTimelock");
    address internal immutable EU_AUTHORISER_SCRIPT =
        vm.deployCode("20261006-grant-eu-authoriser-roles.s.sol:GrantEuAuthoriserRoles");
    address internal immutable ORCHESTRATOR_EMERGENCY_SCRIPT =
        vm.deployCode("20261006-grant-orchestrator-emergency.s.sol:GrantOrchestratorEmergency");

    /// @inheritdoc IStoxScript
    function declaration(uint256 chainId) external pure returns (ScriptDeclaration memory) {
        return backfillMigrationRegistryV5Declaration(chainId);
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x: backfill MigrationRegistry V5 root line";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261030-backfill-migration-registry-v5-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    function entry(address script, uint256 chainId, bytes32 v2Namespace, bytes32 v2Id, bytes32 v2Onto)
        internal
        view
        returns (BackfillRecord memory)
    {
        return BackfillRecord({
            script: script,
            declared: IStoxScript(script).declaration(chainId),
            v2Namespace: v2Namespace,
            v2Id: v2Id,
            v2Onto: v2Onto
        });
    }

    /// @notice The chain's block, in write order.
    function records(uint256 chainId) internal view returns (BackfillRecord[] memory) {
        bool base = chainId == LibSafeInvariants.BASE_CHAIN_ID;
        BackfillRecord[] memory all = new BackfillRecord[](7);
        uint256 k = 0;
        all[k++] = entry(MULTISIG_THRESHOLD_SCRIPT, chainId, bytes32(0), bytes32(0), bytes32(0));
        if (base) {
            all[k++] = entry(REHEARSAL_SCHEDULE_SCRIPT, chainId, bytes32(0), bytes32(0), bytes32(0));
            all[k++] = entry(REHEARSAL_CANCEL_SCRIPT, chainId, bytes32(0), bytes32(0), bytes32(0));
            all[k++] = entry(EXECUTE_TIMELOCK_OPERATIONS_SCRIPT, chainId, bytes32(0), bytes32(0), bytes32(0));
        }
        all[k++] = entry(
            GOVERNANCE_TIMELOCK_SCRIPT,
            chainId,
            LibStoxMigrations.NAMESPACE,
            LibStoxMigrations.GOVERNANCE_TIMELOCK,
            bytes32(0)
        );
        all[k++] =
            entry(EU_AUTHORISER_SCRIPT, chainId, V2_RBAC_NAMESPACE, V2_EU_AUTHORISER_GRANT_AND_HANDOVER, bytes32(0));
        all[k++] = entry(
            ORCHESTRATOR_EMERGENCY_SCRIPT,
            chainId,
            LibStoxMigrations.NAMESPACE,
            LibStoxMigrations.ORCHESTRATOR_EMERGENCY,
            LibStoxMigrations.GOVERNANCE_TIMELOCK
        );
        if (!base) {
            all[k++] = entry(REHEARSAL_SCHEDULE_SCRIPT, chainId, bytes32(0), bytes32(0), bytes32(0));
            all[k++] = entry(REHEARSAL_CANCEL_SCRIPT, chainId, bytes32(0), bytes32(0), bytes32(0));
            all[k++] = entry(EXECUTE_TIMELOCK_OPERATIONS_SCRIPT, chainId, bytes32(0), bytes32(0), bytes32(0));
        }
        return all;
    }

    /// @notice `record`'s moment from its script, checked against V2 where
    /// V2 holds it.
    function moment(address chainSafe, BackfillRecord memory record) internal view returns (uint256) {
        uint256 at = IStoxHistoryMigration(record.script).executedAt(block.chainid);
        if (record.v2Id == bytes32(0)) return at;
        bytes32 actualOnto = IMigrationRegistryV2(REGISTRY_V2).appliedOnto(chainSafe, record.v2Namespace, record.v2Id);
        if (actualOnto != record.v2Onto) revert UnexpectedRegistryV2Order(record.v2Id, actualOnto);
        uint256 recorded = IMigrationRegistryV2(REGISTRY_V2).applied(chainSafe, record.v2Namespace, record.v2Id);
        if (recorded != at) revert HistoryMomentMismatch(record.declared.id, at, recorded);
        return at;
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The Safe and timelock are what this repo pins, V2 is the frozen
    /// 0.1.18 registry, the V2 lines hold exactly the three records at their
    /// scripts' moments, history moments never decrease, and each record is
    /// declared onto the record before it from `MIGRATION_HEAD_GENESIS`.
    function preflight() internal view override {
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibTimelockInvariants.assertTimelockState(LibTimelockInvariants.timelockForChainId(block.chainid), chainSafe);

        if (REGISTRY_V2.codehash != REGISTRY_V2_CODEHASH) revert UnexpectedRegistryV2CodeHash(REGISTRY_V2.codehash);
        bytes32 deployHead = IMigrationRegistryV2(REGISTRY_V2).head(chainSafe, LibStoxMigrations.NAMESPACE);
        if (deployHead != LibStoxMigrations.ORCHESTRATOR_EMERGENCY) {
            revert UnexpectedRegistryV2Line(LibStoxMigrations.NAMESPACE, deployHead);
        }
        bytes32 rbacHead = IMigrationRegistryV2(REGISTRY_V2).head(chainSafe, V2_RBAC_NAMESPACE);
        if (rbacHead != V2_EU_AUTHORISER_GRANT_AND_HANDOVER) {
            revert UnexpectedRegistryV2Line(V2_RBAC_NAMESPACE, rbacHead);
        }

        BackfillRecord[] memory all = records(block.chainid);
        bytes32 previous = MIGRATION_HEAD_GENESIS;
        uint256 previousMoment = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (all[i].declared.onto != previous) {
                revert UnexpectedRegistryV2Order(all[i].declared.id, all[i].declared.onto);
            }
            if (all[i].declared.history) {
                uint256 at = moment(chainSafe, all[i]);
                if (at < previousMoment) revert UnexpectedRegistryV2Order(all[i].declared.id, previous);
                previousMoment = at;
            }
            previous = all[i].declared.id;
        }
        if (backfillMigrationRegistryV5Declaration(block.chainid).onto != previous) {
            revert UnexpectedRegistryV2Order(LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5, previous);
        }
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Each record V5 lacks (history at its moment, else record-only),
    /// then this script's own record if V5 lacks it.
    function authorBundle() internal view override returns (SafeTx[] memory) {
        address chainSafe = address(safe());
        BackfillRecord[] memory all = records(block.chainid);
        ScriptDeclaration memory own = backfillMigrationRegistryV5Declaration(block.chainid);
        SafeTx[] memory txs = new SafeTx[](all.length + 1);
        uint256 k = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (LibStoxMigrations.applied(all[i].declared.id) != 0) continue;
            (address to, bytes memory data) = all[i].declared.history
                ? LibStoxMigrations.historyCall(all[i].declared, moment(chainSafe, all[i]))
                : LibStoxMigrations.recordCall(all[i].declared);
            txs[k++] = SafeTx({to: to, value: 0, data: data, operation: Enum.Operation.Call});
        }
        if (LibStoxMigrations.applied(own.id) == 0) {
            (address to, bytes memory data) = LibStoxMigrations.recordCall(own);
            txs[k++] = SafeTx({to: to, value: 0, data: data, operation: Enum.Operation.Call});
        }
        SafeTx[] memory bundle = new SafeTx[](k);
        for (uint256 i = 0; i < k; i++) {
            bundle[i] = txs[i];
        }
        return bundle;
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Every record is on the root line onto its declared predecessor,
    /// each history record at its moment, this script's record onto its
    /// declared predecessor, and the Safe policy holds.
    function assertPostState() internal view override {
        address chainSafe = address(safe());
        BackfillRecord[] memory all = records(block.chainid);
        for (uint256 i = 0; i < all.length; i++) {
            uint256 actual = LibStoxMigrations.applied(all[i].declared.id);
            if (actual == 0) revert BackfillV5RecordMissing(all[i].declared.id);
            if (all[i].declared.history) {
                uint256 expected = moment(chainSafe, all[i]);
                if (actual != expected) revert BackfillV5RecordMismatch(all[i].declared.id, expected, actual);
            }
            assertOnto(all[i].declared);
        }
        ScriptDeclaration memory own = backfillMigrationRegistryV5Declaration(block.chainid);
        if (LibStoxMigrations.applied(own.id) == 0) revert BackfillV5RecordMissing(own.id);
        assertOnto(own);
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
    }

    function assertOnto(ScriptDeclaration memory declared) internal view {
        bytes32 actualOnto = LibMigrationRegistry.appliedOntoV5(
            LibRegistryAuthority.ROOT_AUTHORITY, LibStoxMigrations.NAMESPACE, declared.id
        );
        if (actualOnto != declared.onto) revert BackfillV5OrderMismatch(declared.id, actualOnto);
    }
}

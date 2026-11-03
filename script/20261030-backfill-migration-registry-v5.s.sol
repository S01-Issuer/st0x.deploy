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
import {LibRegistryAuthority} from "rain-deploy-0.1.29/src/lib/LibRegistryAuthority.sol";
import {SafeTx} from "rain-deploy-0.1.29/src/lib/LibSafeTx.sol";

import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {LibStoxDeployNetworks} from "../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {migrateGovernanceToTimelockDeclaration} from "./20260729-migrate-governance-to-timelock.s.sol";
import {grantEuAuthoriserRolesDeclaration} from "./20261006-grant-eu-authoriser-roles.s.sol";
import {grantOrchestratorEmergencyDeclaration} from "./20261006-grant-orchestrator-emergency.s.sol";
import {migrateMultisigThresholdDeclaration} from "./20260619-migrate-multisig-threshold.s.sol";
import {timelockRehearsalScheduleDeclaration} from "./20260813-timelock-rehearsal-schedule.s.sol";
import {timelockRehearsalCancelDeclaration} from "./20260813-timelock-rehearsal-cancel.s.sol";
import {executeTimelockOperationsDeclaration} from "./20260813-execute-timelock-operations.s.sol";

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

/// @notice After the bundle, a V5 record is applied onto a different record
/// than this backfill replays it onto.
/// @param migration The record.
/// @param onto What V5 says it was applied onto.
error BackfillV5OrderMismatch(bytes32 migration, bytes32 onto);

/// @notice After the bundle, V5 does not hold this script's own record.
/// @param migration The missing record.
error BackfillV5RecordMissing(bytes32 migration);

/// @notice No pinned moment for a no-record history migration on this chain.
/// @param chainId The chain asked about.
/// @param migration The migration.
error NoHistoryMomentOnChain(uint256 chainId, bytes32 migration);

/// @notice The frozen V2 rbac line the EU grant was recorded on.
bytes32 constant V2_RBAC_NAMESPACE = keccak256("st0x.rbac");

/// @notice The EU grant's V2 id on `V2_RBAC_NAMESPACE`.
bytes32 constant V2_EU_AUTHORISER_GRANT_AND_HANDOVER = keccak256("st0x.rbac.eu-assets-authoriser.grant-and-handover");

/// @notice This script's declaration: after the orchestrator-emergency
/// record that ends the history block.
/// @return The declaration.
function backfillMigrationRegistryV5Declaration(uint256) pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5,
        onto: LibStoxMigrations.ORCHESTRATOR_EMERGENCY,
        history: false
    });
}

/// @notice One history record this backfill replays: the script's root-line
/// declaration, where V2 holds it (zero `v2Id` when it has no V2 record),
/// and its moment when it has none.
struct HistoryRecord {
    ScriptDeclaration declared;
    bytes32 v2Namespace;
    bytes32 v2Id;
    bytes32 v2Onto;
    uint256 pinned;
}

/// @title BackfillMigrationRegistryV5
/// @notice Authors the per-chain Safe Tx Builder bundle that replays the
/// chain's history onto the V5 root line (`ROOT_AUTHORITY`,
/// `LibStoxMigrations.NAMESPACE`), each record as history at its real moment,
/// in moment order:
///
/// 1. `MULTISIG_THRESHOLD` onto genesis (no V2 record; pinned moment).
/// 2. Base only: `TIMELOCK_REHEARSAL_SCHEDULE`, `TIMELOCK_REHEARSAL_CANCEL`,
///    `EXECUTE_TIMELOCK_OPERATIONS` (no V2 record; pinned moments).
/// 3. `GOVERNANCE_TIMELOCK` at its V2 moment.
/// 4. The EU grant at its V2 (`st0x.rbac`) moment.
/// 5. `ORCHESTRATOR_EMERGENCY` at its V2 moment.
/// 6. This script's own record onto `ORCHESTRATOR_EMERGENCY`.
///
/// The Safe, an unscoped delegate of the root, writes every record. A record
/// V5 already holds is skipped.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20261030-backfill-migration-registry-v5` per chain.
contract BackfillMigrationRegistryV5 is SafeBundleScript, IStoxScript {
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

    /// @notice When the Safe's threshold was raised to 3 on `chainId`.
    function multisigThresholdMoment(uint256 chainId) internal pure returns (uint256) {
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        for (uint256 i = 0; i < networks.length; i++) {
            if (networks[i].chainId == chainId) {
                bytes32 name = keccak256(bytes(networks[i].name));
                if (name == keccak256(bytes(LibRainDeploy.BASE))) return 1_782_241_221;
                if (name == keccak256(bytes(LibRainDeploy.ETHEREUM))) return 1_784_297_831;
                if (name == keccak256(bytes(LibRainDeploy.HYPEREVM))) return 1_784_902_282;
                if (name == keccak256(bytes(LibRainDeploy.ROBINHOOD))) return 1_789_068_996;
                if (name == keccak256(bytes(LibRainDeploy.BSC))) return 1_789_068_910;
            }
        }
        revert NoHistoryMomentOnChain(chainId, LibStoxMigrations.MULTISIG_THRESHOLD);
    }

    /// @notice The chain's history block, in replay order.
    function records(uint256 chainId) internal pure returns (HistoryRecord[] memory) {
        bool base = chainId == LibSafeInvariants.BASE_CHAIN_ID;
        HistoryRecord[] memory all = new HistoryRecord[](base ? 7 : 4);
        uint256 k = 0;
        all[k++] = HistoryRecord({
            declared: migrateMultisigThresholdDeclaration(chainId),
            v2Namespace: bytes32(0),
            v2Id: bytes32(0),
            v2Onto: bytes32(0),
            pinned: multisigThresholdMoment(chainId)
        });
        if (base) {
            all[k++] = HistoryRecord({
                declared: timelockRehearsalScheduleDeclaration(chainId),
                v2Namespace: bytes32(0),
                v2Id: bytes32(0),
                v2Onto: bytes32(0),
                pinned: 1_787_076_699
            });
            all[k++] = HistoryRecord({
                declared: timelockRehearsalCancelDeclaration(chainId),
                v2Namespace: bytes32(0),
                v2Id: bytes32(0),
                v2Onto: bytes32(0),
                pinned: 1_787_152_049
            });
            all[k++] = HistoryRecord({
                declared: executeTimelockOperationsDeclaration(chainId),
                v2Namespace: bytes32(0),
                v2Id: bytes32(0),
                v2Onto: bytes32(0),
                pinned: 1_787_336_483
            });
        }
        all[k++] = HistoryRecord({
            declared: migrateGovernanceToTimelockDeclaration(chainId),
            v2Namespace: LibStoxMigrations.NAMESPACE,
            v2Id: LibStoxMigrations.GOVERNANCE_TIMELOCK,
            v2Onto: bytes32(0),
            pinned: 0
        });
        all[k++] = HistoryRecord({
            declared: grantEuAuthoriserRolesDeclaration(chainId),
            v2Namespace: V2_RBAC_NAMESPACE,
            v2Id: V2_EU_AUTHORISER_GRANT_AND_HANDOVER,
            v2Onto: bytes32(0),
            pinned: 0
        });
        all[k++] = HistoryRecord({
            declared: grantOrchestratorEmergencyDeclaration(chainId),
            v2Namespace: LibStoxMigrations.NAMESPACE,
            v2Id: LibStoxMigrations.ORCHESTRATOR_EMERGENCY,
            v2Onto: LibStoxMigrations.GOVERNANCE_TIMELOCK,
            pinned: 0
        });
        return all;
    }

    /// @notice `record`'s moment: pinned, or its V2 moment after checking V2
    /// applied it onto what V2 wrote it onto.
    function moment(address chainSafe, HistoryRecord memory record) internal view returns (uint256) {
        if (record.v2Id == bytes32(0)) return record.pinned;
        bytes32 actualOnto = IMigrationRegistryV2(REGISTRY_V2).appliedOnto(chainSafe, record.v2Namespace, record.v2Id);
        if (actualOnto != record.v2Onto) revert UnexpectedRegistryV2Order(record.v2Id, actualOnto);
        return IMigrationRegistryV2(REGISTRY_V2).applied(chainSafe, record.v2Namespace, record.v2Id);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The Safe and timelock are what this repo pins, V2 is the frozen
    /// 0.1.18 registry, the V2 lines hold exactly the three records, the
    /// governance-timelock one at its pinned moment, and each record is
    /// declared onto the record before it.
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

        HistoryRecord[] memory all = records(block.chainid);
        bytes32 previous = bytes32(0);
        uint256 previousMoment = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (all[i].declared.onto != previous) {
                revert UnexpectedRegistryV2Order(all[i].declared.id, all[i].declared.onto);
            }
            uint256 at = moment(chainSafe, all[i]);
            if (at < previousMoment) revert UnexpectedRegistryV2Order(all[i].declared.id, previous);
            previous = all[i].declared.id;
            previousMoment = at;
        }
        if (backfillMigrationRegistryV5Declaration(block.chainid).onto != previous) {
            revert UnexpectedRegistryV2Order(LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5, previous);
        }
        (uint256 pinned,) = LibStoxMigrations.governanceTimelockExecution(block.chainid);
        uint256 recorded = IMigrationRegistryV2(REGISTRY_V2)
            .applied(chainSafe, LibStoxMigrations.NAMESPACE, LibStoxMigrations.GOVERNANCE_TIMELOCK);
        if (recorded != pinned) revert GovernanceTimelockMomentMismatch(pinned, recorded);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Each history record V5 lacks, at its moment, then this script's
    /// own record if V5 lacks it.
    function authorBundle() internal view override returns (SafeTx[] memory) {
        address chainSafe = address(safe());
        HistoryRecord[] memory all = records(block.chainid);
        ScriptDeclaration memory own = backfillMigrationRegistryV5Declaration(block.chainid);
        SafeTx[] memory txs = new SafeTx[](all.length + 1);
        uint256 k = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (LibStoxMigrations.applied(all[i].declared.id) != 0) continue;
            (address to, bytes memory data) = LibStoxMigrations.historyCall(all[i].declared, moment(chainSafe, all[i]));
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
    /// @dev Every history record is on the root line at its moment onto its
    /// declared predecessor, this script's record is onto
    /// `ORCHESTRATOR_EMERGENCY`, and the Safe policy holds.
    function assertPostState() internal view override {
        address chainSafe = address(safe());
        HistoryRecord[] memory all = records(block.chainid);
        for (uint256 i = 0; i < all.length; i++) {
            uint256 expected = moment(chainSafe, all[i]);
            uint256 actual = LibStoxMigrations.applied(all[i].declared.id);
            if (actual != expected) revert BackfillV5RecordMismatch(all[i].declared.id, expected, actual);
            bytes32 actualOnto = LibMigrationRegistry.appliedOntoV5(
                LibRegistryAuthority.ROOT_AUTHORITY, LibStoxMigrations.NAMESPACE, all[i].declared.id
            );
            if (actualOnto != all[i].declared.onto) revert BackfillV5OrderMismatch(all[i].declared.id, actualOnto);
        }
        bytes32 own = LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5;
        if (LibStoxMigrations.applied(own) == 0) revert BackfillV5RecordMissing(own);
        bytes32 ownOnto =
            LibMigrationRegistry.appliedOntoV5(LibRegistryAuthority.ROOT_AUTHORITY, LibStoxMigrations.NAMESPACE, own);
        if (ownOnto != LibStoxMigrations.ORCHESTRATOR_EMERGENCY) revert BackfillV5OrderMismatch(own, ownOnto);
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
    }
}

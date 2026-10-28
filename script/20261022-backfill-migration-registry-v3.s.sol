// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.26/src/abstract/SafeBundleScript.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.26/src/interface/IMigrationRegistryV4.sol";
import {IMigrationRegistryV2} from "rain-deploy-0.1.26/src/interface/deprecated/IMigrationRegistryV2.sol";
import {
    DEPLOYED_ADDRESS as REGISTRY_V2,
    BYTECODE_HASH as REGISTRY_V2_CODEHASH
} from "rain-deploy-0.1.26/src/generated/0_1_18/MigrationRegistry.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.26/src/lib/LibMigrationRegistry.sol";
import {SafeTx} from "rain-deploy-0.1.26/src/lib/LibSafeTx.sol";

import {ST0xOrchestrator} from "../src/concrete/ST0xOrchestrator.sol";
import {LibOrchestratorInvariants} from "../src/lib/LibOrchestratorInvariants.sol";
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

/// @notice A V3 line is not at genesis: the backfill has already executed,
/// or something else was written first.
/// @param namespace The line's namespace.
/// @param head The line's V3 head.
error UnexpectedRegistryV3Line(bytes32 namespace, bytes32 head);

/// @notice After the bundle, a V3 record differs from the moment it must
/// carry: its V2 moment, or this block for this script's own record.
/// @param migration The record.
/// @param expected The moment it must carry.
/// @param actual The V3 moment.
error BackfillRecordMismatch(bytes32 migration, uint256 expected, uint256 actual);

/// @notice After the bundle, the Safe does not hold `EMERGENCY_ROLE` on the
/// orchestrator, though the carried record says it was granted.
/// @param safe The chain's token-owner Safe.
error EmergencyNotHeld(address safe);

/// @notice This script's declaration: the Safe's record after the V2
/// records it carries into V3.
/// @return The declaration.
function backfillMigrationRegistryV3Declaration() pure returns (ScriptDeclaration memory) {
    return LibStoxMigrations.safeMigrationOnto(
        LibStoxMigrations.NAMESPACE,
        keccak256("script/20261022-backfill-migration-registry-v3.s.sol"),
        grantOrchestratorEmergencyDeclaration().id,
        false
    );
}

/// @title BackfillMigrationRegistryV3
/// @notice Authors the per-chain Safe Tx Builder bundle that carries the
/// chain's token-owner Safe's records from the frozen V2 `MigrationRegistry`
/// into V3, each as history at its V2 moment and onto the same predecessor:
///
/// 1. `st0x.deploy`: `GOVERNANCE_TIMELOCK` onto genesis.
/// 2. `st0x.deploy`: `ORCHESTRATOR_EMERGENCY` onto `GOVERNANCE_TIMELOCK`.
/// 3. `st0x.rbac`: `EU_AUTHORISER_GRANT_AND_HANDOVER` onto genesis.
/// 4. `st0x.deploy`: this script's own record onto `ORCHESTRATOR_EMERGENCY`.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20261022-backfill-migration-registry-v3` per chain. Refuses once
/// either V3 line has moved off genesis (`UnexpectedRegistryV3Line`).
contract BackfillMigrationRegistryV3 is SafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return backfillMigrationRegistryV3Declaration();
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x: backfill MigrationRegistry V3 from V2";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261022-backfill-migration-registry-v3-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @notice The Safe's V2 moment for `migration` in `namespace`, after
    /// checking it was applied onto `onto`.
    function v2Moment(bytes32 namespace, bytes32 migration, bytes32 onto) internal view returns (uint256) {
        address chainSafe = address(safe());
        bytes32 actualOnto = IMigrationRegistryV2(REGISTRY_V2).appliedOnto(chainSafe, namespace, migration);
        if (actualOnto != onto) revert UnexpectedRegistryV2Order(migration, actualOnto);
        return IMigrationRegistryV2(REGISTRY_V2).applied(chainSafe, namespace, migration);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The Safe and timelock are what this repo pins, the V2 lines hold
    /// exactly the three records in order, and both V3 lines are at genesis.
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
        (uint256 pinned,) = LibStoxMigrations.governanceTimelockExecution(block.chainid);
        uint256 recorded =
            v2Moment(LibStoxMigrations.NAMESPACE, LibStoxMigrations.GOVERNANCE_TIMELOCK, MIGRATION_HEAD_GENESIS);
        if (recorded != pinned) revert GovernanceTimelockMomentMismatch(pinned, recorded);

        bytes32 v3DeployHead = LibStoxMigrations.head(chainSafe);
        if (v3DeployHead != MIGRATION_HEAD_GENESIS) {
            revert UnexpectedRegistryV3Line(LibStoxMigrations.NAMESPACE, v3DeployHead);
        }
        bytes32 v3RbacHead = LibMigrationRegistry.headV4(chainSafe, LibRbacMigration.STOX_RBAC_NAMESPACE);
        if (v3RbacHead != MIGRATION_HEAD_GENESIS) {
            revert UnexpectedRegistryV3Line(LibRbacMigration.STOX_RBAC_NAMESPACE, v3RbacHead);
        }
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The three V2 records as history at their V2 moments, each from
    /// its own script's declaration, then this script's own record.
    function authorBundle() internal view override returns (SafeTx[] memory) {
        address chainSafe = address(safe());
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        (uint256 timelockAt,) = LibStoxMigrations.governanceTimelockExecution(block.chainid);
        uint256 emergencyAt = v2Moment(
            LibStoxMigrations.NAMESPACE, LibStoxMigrations.ORCHESTRATOR_EMERGENCY, LibStoxMigrations.GOVERNANCE_TIMELOCK
        );
        uint256 euAt = v2Moment(
            LibRbacMigration.STOX_RBAC_NAMESPACE,
            LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER,
            MIGRATION_HEAD_GENESIS
        );

        SafeTx[] memory txs = new SafeTx[](4);
        (address to, bytes memory data) =
            LibStoxMigrations.historyCall(migrateGovernanceToTimelockDeclaration(), timelockAt, chainSafe, timelock);
        txs[0] = SafeTx({to: to, value: 0, data: data, operation: Enum.Operation.Call});
        (to, data) =
            LibStoxMigrations.historyCall(grantOrchestratorEmergencyDeclaration(), emergencyAt, chainSafe, timelock);
        txs[1] = SafeTx({to: to, value: 0, data: data, operation: Enum.Operation.Call});
        (to, data) = LibStoxMigrations.historyCall(grantEuAuthoriserRolesDeclaration(), euAt, chainSafe, timelock);
        txs[2] = SafeTx({to: to, value: 0, data: data, operation: Enum.Operation.Call});
        (to, data) = LibStoxMigrations.recordCall(backfillMigrationRegistryV3Declaration(), chainSafe, timelock);
        txs[3] = SafeTx({to: to, value: 0, data: data, operation: Enum.Operation.Call});
        return txs;
    }

    /// @notice Reverts unless the Safe's V3 record for `migration` equals its
    /// V2 record.
    function assertCarried(bytes32 namespace, bytes32 migration) internal view {
        address chainSafe = address(safe());
        uint256 expected = IMigrationRegistryV2(REGISTRY_V2).applied(chainSafe, namespace, migration);
        uint256 actual = LibMigrationRegistry.appliedV4(chainSafe, namespace, migration);
        if (actual != expected) revert BackfillRecordMismatch(migration, expected, actual);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Every carried V3 record equals its V2 record, this script's record
    /// carries this block and heads the deploy line, the rbac head equals the
    /// V2 head, the Safe holds `EMERGENCY_ROLE`, and the orchestrator invariant
    /// holds.
    function assertPostState() internal view override {
        address chainSafe = address(safe());
        assertCarried(LibStoxMigrations.NAMESPACE, LibStoxMigrations.GOVERNANCE_TIMELOCK);
        assertCarried(LibStoxMigrations.NAMESPACE, LibStoxMigrations.ORCHESTRATOR_EMERGENCY);
        assertCarried(LibRbacMigration.STOX_RBAC_NAMESPACE, LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER);
        bytes32 own = backfillMigrationRegistryV3Declaration().id;
        uint256 ownAt = LibStoxMigrations.applied(chainSafe, own);
        // forge-lint: disable-next-line(block-timestamp)
        if (ownAt != block.timestamp) {
            // forge-lint: disable-next-line(block-timestamp)
            revert BackfillRecordMismatch(own, block.timestamp, ownAt);
        }
        bytes32 deployHead = LibStoxMigrations.head(chainSafe);
        if (deployHead != own) {
            revert UnexpectedRegistryV3Line(LibStoxMigrations.NAMESPACE, deployHead);
        }
        bytes32 rbacHead = LibMigrationRegistry.headV4(chainSafe, LibRbacMigration.STOX_RBAC_NAMESPACE);
        if (rbacHead != LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER) {
            revert UnexpectedRegistryV3Line(LibRbacMigration.STOX_RBAC_NAMESPACE, rbacHead);
        }
        ST0xOrchestrator orchestrator = ST0xOrchestrator(payable(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE));
        if (!orchestrator.hasRole(orchestrator.EMERGENCY_ROLE(), chainSafe)) {
            revert EmergencyNotHeld(chainSafe);
        }
        LibOrchestratorInvariants.assertInstance();
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
    }
}

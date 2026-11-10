// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.30/src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibMigrationRegistryDeploy.sol";
import {IRegistryDelegatesV3} from "rain-deploy-0.1.30/src/interface/IRegistryDelegatesV3.sol";
import {Prerequisite} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";

import {ScriptDeclaration} from "../interface/IStoxScript.sol";
import {LibStoxDeployNetworks} from "./LibStoxDeployNetworks.sol";

/// @notice No execution moment is pinned for the governance-timelock
/// migration on this chain.
/// @param chainId The chain asked about.
error NoGovernanceTimelockMigrationOnChain(uint256 chainId);

/// @notice The root line is not at the head a migration is applied onto: the
/// migration is already recorded, or its predecessor is not.
/// @param head The line's head.
error UnexpectedMigrationLine(bytes32 head);

/// @notice The account that would write the record is not an unscoped
/// delegate of the root authority, so the record would revert.
/// @param safe The account.
error SafeNotApprovedWriter(address safe);

/// @notice After the bundle, the migration's record is not the one the
/// bundle wrote.
/// @param migration The migration.
/// @param expected The moment the bundle records.
/// @param actual The moment the registry answers.
error RecordMismatch(bytes32 migration, uint256 expected, uint256 actual);

/// @notice After the bundle, the root line does not end at the bundle's
/// record.
/// @param head The line's head.
error LineHeadMismatch(bytes32 head);

/// @title LibStoxMigrations
/// @notice The ids under which this repo's scripts record what they applied
/// in `rain-deploy`'s `MigrationRegistry`, and the calls that write and read
/// those records.
///
/// Every record is on one line: writer `LibRegistryAuthority.ROOT_AUTHORITY`,
/// namespace `NAMESPACE`. The chain's token-owner Safe, an unscoped delegate
/// of the root, writes every record, so the line does not depend on which
/// account performs a migration:
///
/// - a migration the Safe performs directly is recorded as the last call of
///   the Safe's MultiSend, so the record and the change land atomically;
/// - a migration executed through the governance timelock is recorded by the
///   Safe in its next bundle after the operation executes; no record rides in
///   a timelock batch, so a pending batch never holds the line.
///
/// A migration that ran before anything was recorded is recorded later as
/// history, with the moment it executed. Until that record lands, `applied`
/// answering zero does NOT mean it has not run.
///
/// The records live in ONE registry instance: the address and code hash
/// `LibMigrationRegistryDeploy` carries in the imported rain-deploy.
/// `LibStoxMigrationsTest` pins the instance so a rain-deploy bump that
/// moves the registry fails there first.
library LibStoxMigrations {
    /// @notice The namespace every st0x.deploy record is written in.
    bytes32 internal constant NAMESPACE = keccak256("st0x.deploy");

    /// @notice `script/20260729-migrate-governance-to-timelock.s.sol`: vault
    /// and beacon ownership plus the authoriser `_ADMIN` roles to the
    /// governance timelock. Ran before anything was recorded, so it is
    /// recorded as history with the moment it executed.
    bytes32 internal constant GOVERNANCE_TIMELOCK = keccak256("script/20260729-migrate-governance-to-timelock.s.sol");

    /// @notice `script/20261006-grant-orchestrator-emergency.s.sol`: the
    /// chain's Safe is granted `EMERGENCY_ROLE` on the orchestrator.
    bytes32 internal constant ORCHESTRATOR_EMERGENCY = keccak256("script/20261006-grant-orchestrator-emergency.s.sol");

    /// @notice `script/20261006-grant-eu-authoriser-roles.s.sol`.
    bytes32 internal constant GRANT_EU_AUTHORISER_ROLES = keccak256("script/20261006-grant-eu-authoriser-roles.s.sol");

    /// @notice `script/20261006-orchestrator-admin-to-timelock.s.sol`: the
    /// orchestrator's `DEFAULT_ADMIN_ROLE` moves from the chain's Safe to the
    /// governance timelock.
    bytes32 internal constant ORCHESTRATOR_ADMIN_TO_TIMELOCK =
        keccak256("script/20261006-orchestrator-admin-to-timelock.s.sol");

    /// @notice `script/20261030-backfill-migration-registry-v5.s.sol`: the
    /// Safe's V2 `MigrationRegistry` records replayed onto V5.
    bytes32 internal constant BACKFILL_MIGRATION_REGISTRY_V5 =
        keccak256("script/20261030-backfill-migration-registry-v5.s.sol");

    /// @notice `script/20261110-bind-orchestrator-config.s.sol`: the
    /// orchestrator beacon and initial admin bound in the ConfigRegistry.
    bytes32 internal constant BIND_ORCHESTRATOR_CONFIG =
        keccak256("script/20261110-bind-orchestrator-config.s.sol");

    /// @notice `script/20261022-bind-beacon-initial-owner.s.sol`: the beacon
    /// initial owner bound to the governance timelock in the ConfigRegistry.
    bytes32 internal constant BIND_BEACON_INITIAL_OWNER = keccak256("script/20261022-bind-beacon-initial-owner.s.sol");

    /// @notice `script/20260619-migrate-multisig-threshold.s.sol`.
    bytes32 internal constant MULTISIG_THRESHOLD = keccak256("script/20260619-migrate-multisig-threshold.s.sol");

    /// @notice `script/20260813-timelock-rehearsal-schedule.s.sol`.
    bytes32 internal constant TIMELOCK_REHEARSAL_SCHEDULE =
        keccak256("script/20260813-timelock-rehearsal-schedule.s.sol");

    /// @notice `script/20260813-timelock-rehearsal-cancel.s.sol`.
    bytes32 internal constant TIMELOCK_REHEARSAL_CANCEL = keccak256("script/20260813-timelock-rehearsal-cancel.s.sol");

    /// @notice `script/20260813-execute-timelock-operations.s.sol`.
    bytes32 internal constant EXECUTE_TIMELOCK_OPERATIONS =
        keccak256("script/20260813-execute-timelock-operations.s.sol");

    /// @notice `script/20261021-schedule-underlying-naming-beacons.s.sol`.
    bytes32 internal constant SCHEDULE_UNDERLYING_NAMING_BEACONS =
        keccak256("script/20261021-schedule-underlying-naming-beacons.s.sol");

    /// @notice `script/20261021-schedule-underlying-naming-rename.s.sol`.
    bytes32 internal constant SCHEDULE_UNDERLYING_NAMING_RENAME =
        keccak256("script/20261021-schedule-underlying-naming-rename.s.sol");

    /// @notice `script/20261021-execute-underlying-naming.s.sol`.
    bytes32 internal constant EXECUTE_UNDERLYING_NAMING = keccak256("script/20261021-execute-underlying-naming.s.sol");

    /// @notice `script/20261109-schedule-revoke-service-signer-deposit-withdraw.s.sol`.
    bytes32 internal constant SCHEDULE_REVOKE_SERVICE_SIGNER =
        keccak256("script/20261109-schedule-revoke-service-signer-deposit-withdraw.s.sol");

    /// @notice `script/20261109-execute-revoke-service-signer-deposit-withdraw.s.sol`.
    bytes32 internal constant EXECUTE_REVOKE_SERVICE_SIGNER =
        keccak256("script/20261109-execute-revoke-service-signer-deposit-withdraw.s.sol");

    /// @notice What `declared` is recorded after on the root line.
    /// @param declared The declaration.
    /// @return The prerequisites.
    function prerequisitesFor(ScriptDeclaration memory declared) internal pure returns (Prerequisite[] memory) {
        return LibMigrationRegistry.onto(LibRegistryAuthority.ROOT_AUTHORITY, NAMESPACE, declared.onto);
    }

    /// @notice The registry call, sent by the Safe as an unscoped delegate of
    /// the root, that writes `declared`'s record. Verifies the registry's code
    /// hash first.
    /// @param declared The declaration.
    /// @return The registry.
    /// @return The calldata.
    function recordCall(ScriptDeclaration memory declared) internal view returns (address, bytes memory) {
        (address registry, bytes memory data) = LibMigrationRegistry.applyMigrationV4Call(
            LibRegistryAuthority.ROOT_AUTHORITY, NAMESPACE, declared.id, prerequisitesFor(declared), ""
        );
        return (registry, data);
    }

    /// @notice `recordCall` as a bundle entry.
    /// @param declared The declaration.
    /// @return The CALL that writes the record.
    function recordTx(ScriptDeclaration memory declared) internal view returns (SafeTx memory) {
        (address registry, bytes memory data) = recordCall(declared);
        return SafeTx({to: registry, value: 0, data: data, operation: Enum.Operation.Call});
    }

    /// @notice Reverts unless `declared` is the root line's next record and
    /// `delegate` may write it.
    /// @param declared The declaration.
    /// @param delegate The account that writes the record.
    function assertNext(ScriptDeclaration memory declared, address delegate) internal view {
        bytes32 lineHead = head();
        if (lineHead != declared.onto) revert UnexpectedMigrationLine(lineHead);
        if (!approved(delegate)) revert SafeNotApprovedWriter(delegate);
    }

    /// @notice Reverts unless `declared` was recorded in this block and heads
    /// the root line.
    /// @param declared The declaration.
    function assertRecorded(ScriptDeclaration memory declared) internal view {
        uint256 record = applied(declared.id);
        // forge-lint: disable-next-line(block-timestamp)
        if (record != block.timestamp) revert RecordMismatch(declared.id, block.timestamp, record);
        bytes32 lineHead = head();
        if (lineHead != declared.id) revert LineHeadMismatch(lineHead);
    }

    /// @notice Whether `delegate` is an unscoped delegate of the root
    /// authority. Verifies the registry's code hash first.
    /// @param delegate The account asked about.
    /// @return The root's unscoped approval of it.
    function approved(address delegate) internal view returns (bool) {
        LibMigrationRegistry.checkCodeHash();
        return IRegistryDelegatesV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .approvedUnscopedV5(LibRegistryAuthority.ROOT_AUTHORITY, delegate);
    }

    /// @notice `recordCall` as history, at `appliedAt`.
    /// @param declared The declaration.
    /// @param appliedAt When it executed, unix seconds.
    /// @return The registry.
    /// @return The calldata.
    function historyCall(ScriptDeclaration memory declared, uint256 appliedAt)
        internal
        view
        returns (address, bytes memory)
    {
        (address registry, bytes memory data) = LibMigrationRegistry.applyMigrationHistoryV4Call(
            LibRegistryAuthority.ROOT_AUTHORITY, NAMESPACE, declared.id, appliedAt, prerequisitesFor(declared), ""
        );
        return (registry, data);
    }

    /// @notice The block timestamp of the Safe transaction that executed the
    /// governance-timelock migration on `chainId`: the block in which the
    /// orchestrator beacon's `OwnershipTransferred(safe, timelock)` was
    /// emitted.
    ///
    /// `chainId` resolves to a network through `rain-deploy`'s catalogue
    /// entries for `LibStoxDeployNetworks.deploymentNetworks()`, so chain ids
    /// are stated once, in the catalogue; the moments are pinned per network
    /// name.
    /// @param chainId The chain id.
    /// @return The execution moment, unix seconds.
    /// @return The block the migration executed in.
    function governanceTimelockExecution(uint256 chainId) internal pure returns (uint256, uint256) {
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        for (uint256 i = 0; i < networks.length; i++) {
            if (networks[i].chainId == chainId) {
                bytes32 name = keccak256(bytes(networks[i].name));
                if (name == keccak256(bytes(LibRainDeploy.ETHEREUM))) return (1_791_056_759, 26_113_992);
                if (name == keccak256(bytes(LibRainDeploy.HYPEREVM))) return (1_791_062_016, 47_585_501);
                if (name == keccak256(bytes(LibRainDeploy.BSC))) return (1_791_109_807, 125_660_540);
                if (name == keccak256(bytes(LibRainDeploy.ROBINHOOD))) return (1_791_131_389, 80_078_305);
                if (name == keccak256(bytes(LibRainDeploy.BASE))) return (1_791_142_369, 52_176_511);
            }
        }
        revert NoGovernanceTimelockMigrationOnChain(chainId);
    }

    /// @notice When `migration` was recorded on the root line, or zero.
    /// @param migration The migration id.
    /// @return The recorded moment, or zero.
    function applied(bytes32 migration) internal view returns (uint256) {
        return LibMigrationRegistry.appliedV5(LibRegistryAuthority.ROOT_AUTHORITY, NAMESPACE, migration);
    }

    /// @notice The root line's head, or `MIGRATION_HEAD_GENESIS`.
    /// @return The head.
    function head() internal view returns (bytes32) {
        return LibMigrationRegistry.headV5(LibRegistryAuthority.ROOT_AUTHORITY, NAMESPACE);
    }
}

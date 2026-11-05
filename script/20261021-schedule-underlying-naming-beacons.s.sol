// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.30/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";
import {StoxCorporateActionsFacet} from "../src/concrete/StoxCorporateActionsFacet.sol";
import {AssetIdNotInitializing} from "../src/error/ErrAssetId.sol";
import {IStoxAssetIdV1} from "../src/interface/IStoxAssetIdV1.sol";
import {LibBeaconInvariants} from "../src/lib/LibBeaconInvariants.sol";
import {TokenInstance} from "../src/lib/LibTokenInvariants.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {LibUnderlyingNamingRollout, UnderlyingNamingReleaseNotFrozen} from "../src/lib/LibUnderlyingNamingRollout.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";

/// @notice An implementation the beacon batch points a beacon at does not
/// carry its pinned code on this chain. Deploy it first (rollout step 1).
/// @param implementation The implementation address.
/// @param expected The pinned codehash.
/// @param actual The codehash on chain.
error ImplementationNotDeployed(address implementation, bytes32 expected, bytes32 actual);

/// @notice A beacon this batch upgrades already points at the target
/// implementation, so the batch has run on this chain.
/// @param beacon The beacon.
error BeaconAlreadyUpgraded(address beacon);

/// @notice The operation is already registered on the timelock: scheduling
/// it again would revert inside the Safe transaction.
/// @param id The operation id.
error OperationAlreadyScheduled(bytes32 id);

/// @notice After the bundle the operation is not pending, or is ready inside
/// its delay.
/// @param id The operation id.
error OperationNotPendingInsideDelay(bytes32 id);

/// @notice After execution a beacon does not point at its target.
/// @param beacon The beacon.
/// @param expected The target implementation.
/// @param actual The beacon's implementation.
error BeaconNotUpgraded(address beacon, address expected, address actual);

/// @notice The beacon batch changed a vault's or wrapper's name or symbol.
/// @param token The vault or wrapper.
/// @param before The value before the batch.
/// @param afterUpgrade The value after it.
error BeaconUpgradeMovedMetadata(address token, string before, string afterUpgrade);

/// @notice A live vault behind the upgraded beacon reports an asset id.
/// @param vault The vault.
/// @param assetId The id it reports.
error UpgradedVaultHasAssetId(address vault, string assetId);

/// @notice A live vault behind the upgraded beacon does not refuse
/// `initializeAssetId` with `AssetIdNotInitializing`, so the new
/// implementation does not carry the asset id hook.
/// @param vault The vault.
/// @param result What the call returned.
error UpgradedVaultMissingAssetIdHook(address vault, bytes result);

/// @notice The root line is not at the record this migration is applied onto.
/// @param head The line's head.
error ScheduleBeaconsUnexpectedMigrationLine(bytes32 head);

/// @notice After the bundle this migration's record is not on the root line.
error ScheduleBeaconsRecordMissing();

/// @notice After the bundle the root line's head is neither this migration's
/// record nor, after a reschedule under a recorded rename, the rename
/// schedule's.
/// @param head The line's head.
error ScheduleBeaconsLineHeadMismatch(bytes32 head);

/// @notice This script's declaration: the Safe's record, after the
/// Safe-owned Base vault handover.
/// @return The declaration.
function scheduleUnderlyingNamingBeaconsDeclaration() pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS,
        onto: LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK,
        history: false
    });
}

/// @title ScheduleUnderlyingNamingBeacons
/// @notice Authors the per-chain Safe bundle that SCHEDULES the
/// underlying-naming beacon batch on the chain's governance timelock (rollout
/// step 2 in `docs/TIMELOCK.md`; see `LibUnderlyingNamingRollout` for
/// the calls). Two Safe calls: `timelock.scheduleBatch(...)`, with the pinned
/// 48h delay, then the Safe's root-line record; or the schedule alone when
/// rescheduling a cancelled batch.
///
/// Execution is not a Safe action: the timelock lets anyone execute a ready
/// operation (`20261021-execute-underlying-naming` does it from the CI deploy
/// key). The batch ends with a read-only facet call, so it reverts as a whole,
/// and stays Ready, if the facet has no code at execution.
///
/// Pre-flight refuses while `LibUnderlyingNamingRollout.RELEASE_FROZEN` is
/// false: the implementations must be a frozen, audited release before a
/// beacon is scheduled onto them.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20261021-schedule-underlying-naming-beacons` per chain, after the
/// implementations are deployed there.
contract ScheduleUnderlyingNamingBeacons is SafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration(uint256) external pure returns (ScriptDeclaration memory) {
        return scheduleUnderlyingNamingBeaconsDeclaration();
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x underlying naming: schedule the wrapper and receipt-vault beacon upgrades";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261021-schedule-underlying-naming-beacons-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @notice The chain's governance timelock.
    /// @return The timelock.
    function timelock() internal view returns (address) {
        return LibTimelockInvariants.timelockForChainId(block.chainid);
    }

    /// @notice Whether the implementations are a frozen, audited release.
    /// @return `LibUnderlyingNamingRollout.RELEASE_FROZEN`.
    function releaseFrozen() internal pure virtual returns (bool) {
        return LibUnderlyingNamingRollout.RELEASE_FROZEN;
    }

    /// @notice Reverts unless `implementation` carries `codehash`.
    /// @param implementation The implementation.
    /// @param codehash The pinned codehash.
    function assertDeployed(address implementation, bytes32 codehash) internal view {
        if (implementation.codehash != codehash) {
            revert ImplementationNotDeployed(implementation, codehash, implementation.codehash);
        }
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The root line is at this migration's `onto`, or the batch is being
    /// rescheduled after a cancel (see `rescheduling`). The release is frozen,
    /// the Safe and timelock are the pinned ones, the timelock owns the in-use
    /// beacons, the three implementations carry their pinned code, the beacons
    /// have not moved and still serve their pinned from-implementations, and
    /// the operation is not registered.
    function preflight() internal view override {
        if (!releaseFrozen()) revert UnderlyingNamingReleaseNotFrozen();
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock(), chainSafe);
        bytes32 head = LibStoxMigrations.head();
        if (head != scheduleUnderlyingNamingBeaconsDeclaration().onto && !rescheduling()) {
            revert ScheduleBeaconsUnexpectedMigrationLine(head);
        }
        LibBeaconInvariants.assertProdBeaconsOwnedByChainTimelock(block.chainid);

        assertDeployed(LibUnderlyingNamingRollout.FACET, LibUnderlyingNamingRollout.FACET_CODEHASH);
        assertDeployed(
            LibUnderlyingNamingRollout.RECEIPT_VAULT_IMPLEMENTATION, LibUnderlyingNamingRollout.RECEIPT_VAULT_CODEHASH
        );
        assertDeployed(
            LibUnderlyingNamingRollout.WRAPPED_TOKEN_VAULT_IMPLEMENTATION,
            LibUnderlyingNamingRollout.WRAPPED_TOKEN_VAULT_CODEHASH
        );

        address vaultBeacon = LibUnderlyingNamingRollout.receiptVaultBeacon(block.chainid);
        if (IBeacon(vaultBeacon).implementation() == LibUnderlyingNamingRollout.RECEIPT_VAULT_IMPLEMENTATION) {
            revert BeaconAlreadyUpgraded(vaultBeacon);
        }
        address wrapperBeacon = LibUnderlyingNamingRollout.wrappedTokenVaultBeacon(block.chainid);
        if (IBeacon(wrapperBeacon).implementation() == LibUnderlyingNamingRollout.WRAPPED_TOKEN_VAULT_IMPLEMENTATION) {
            revert BeaconAlreadyUpgraded(wrapperBeacon);
        }
        // Each beacon must still serve the implementation this batch moves it
        // from, so a batch is never scheduled over an upgrade it does not know
        // about.
        bytes32[4] memory codehashes = LibBeaconInvariants.prodBeaconCodehashesForChainId(block.chainid);
        LibBeaconInvariants.assertBeaconInvariants(
            vaultBeacon,
            timelock(),
            LibUnderlyingNamingRollout.RECEIPT_VAULT_FROM_IMPLEMENTATION,
            codehashes[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX]
        );
        LibBeaconInvariants.assertBeaconInvariants(
            wrapperBeacon,
            timelock(),
            LibUnderlyingNamingRollout.WRAPPED_TOKEN_VAULT_FROM_IMPLEMENTATION,
            codehashes[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX]
        );

        bytes32 id = LibUnderlyingNamingRollout.beaconOperationId(timelock(), block.chainid);
        if (TimelockController(payable(timelock())).isOperation(id)) revert OperationAlreadyScheduled(id);
    }

    /// @notice Whether this dispatch reschedules a cancelled beacon batch:
    /// this migration's record is on the line, and the head is that record or
    /// the rename schedule's (the Safe cancelled both batches in their delay).
    /// The pre-flight still requires the batch not to be registered.
    /// @return True when the bundle must schedule without a second record.
    function rescheduling() internal view returns (bool) {
        bytes32 head = LibStoxMigrations.head();
        return LibStoxMigrations.applied(LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS) != 0
            && (head == LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS
                || head == LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The schedule, then the record. When rescheduling a cancelled
    /// batch the record is already on the line, so the bundle is the schedule
    /// alone.
    function authorBundle() internal view override returns (SafeTx[] memory txs) {
        bool reschedule = rescheduling();
        txs = new SafeTx[](reschedule ? 1 : 2);
        txs[0] = SafeTx({
            to: timelock(),
            value: 0,
            data: LibUnderlyingNamingRollout.scheduleBeaconCalldata(block.chainid),
            operation: Enum.Operation.Call
        });
        if (!reschedule) {
            (address recordTo, bytes memory recordData) =
                LibStoxMigrations.recordCall(scheduleUnderlyingNamingBeaconsDeclaration());
            txs[1] = SafeTx({to: recordTo, value: 0, data: recordData, operation: Enum.Operation.Call});
        }
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Scheduled, pending and not ready inside the delay; this
    /// migration's record is on the root line, and the head is that record or,
    /// after a reschedule while the rename is recorded (one or both batches
    /// cancelled), the rename schedule's record.
    function assertPostState() internal view override {
        TimelockController controller = TimelockController(payable(timelock()));
        bytes32 id = LibUnderlyingNamingRollout.beaconOperationId(timelock(), block.chainid);
        if (!controller.isOperationPending(id) || controller.isOperationReady(id)) {
            revert OperationNotPendingInsideDelay(id);
        }
        // A first schedule writes the record in this bundle; a reschedule
        // finds it already on the line.
        uint256 record = LibStoxMigrations.applied(LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS);
        if (record == 0) revert ScheduleBeaconsRecordMissing();
        bytes32 head = LibStoxMigrations.head();
        if (
            head != LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS
                && head != LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME
        ) {
            revert ScheduleBeaconsLineHeadMismatch(head);
        }
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Executes the batch after the delay, as an address with no role,
    /// on a snapshot: both beacons point at their targets.
    function assertReversible() internal override {
        uint256 postBundle = vm.snapshotState();
        proveExecution();
        vm.revertToState(postBundle);
    }

    /// @notice The execution proof `assertReversible` runs. It records every
    /// vault's and wrapper's `name()` and `symbol()` the rollout renames (the
    /// leading `TOKEN_COUNT` rows) before the
    /// batch and requires them unchanged after it: the beacon batch must not
    /// rename anything, that is the rename batch's job. It also proves a live
    /// vault behind the upgraded beacon serves the facet's asset id surface: it
    /// reports `assetId() == ""`, and the init-only `initializeAssetId` refuses
    /// with `AssetIdNotInitializing`. That the vault's `_initialize` forwards to
    /// the hook is bound by the pinned `RECEIPT_VAULT_CODEHASH`, not by this
    /// check.
    function proveExecution() internal {
        TokenInstance[] memory chainTokens = LibUnderlyingNamingRollout.tokens(block.chainid);
        string[] memory before = metadata(chainTokens);
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            LibUnderlyingNamingRollout.beaconBatch(block.chainid);
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        vm.prank(address(0xdead));
        TimelockController(payable(timelock()))
            .executeBatch(targets, values, payloads, bytes32(0), LibUnderlyingNamingRollout.BEACON_SALT);

        assertBeacon(
            LibUnderlyingNamingRollout.wrappedTokenVaultBeacon(block.chainid),
            LibUnderlyingNamingRollout.WRAPPED_TOKEN_VAULT_IMPLEMENTATION
        );
        assertBeacon(
            LibUnderlyingNamingRollout.receiptVaultBeacon(block.chainid),
            LibUnderlyingNamingRollout.RECEIPT_VAULT_IMPLEMENTATION
        );
        string[] memory afterUpgrade = metadata(chainTokens);
        for (uint256 i = 0; i < before.length; i++) {
            if (keccak256(bytes(before[i])) != keccak256(bytes(afterUpgrade[i]))) {
                revert BeaconUpgradeMovedMetadata(metadataToken(chainTokens, i), before[i], afterUpgrade[i]);
            }
        }
        assertAssetIdHook(chainTokens[0].receiptVault);
        console2.log(
            "Execution proven: both beacons upgraded by a roleless executor after 48h, no name or symbol moved"
        );
    }

    /// @notice Every vault's and wrapper's name and symbol, in a fixed order:
    /// vault name, vault symbol, wrapper name, wrapper symbol, per token.
    /// @param chainTokens The chain's tokens.
    /// @return values The values read.
    function metadata(TokenInstance[] memory chainTokens) internal view returns (string[] memory values) {
        values = new string[](chainTokens.length * 4);
        for (uint256 i = 0; i < chainTokens.length; i++) {
            values[i * 4] = IERC20Metadata(chainTokens[i].receiptVault).name();
            values[i * 4 + 1] = IERC20Metadata(chainTokens[i].receiptVault).symbol();
            values[i * 4 + 2] = IERC20Metadata(chainTokens[i].wrappedTokenVault).name();
            values[i * 4 + 3] = IERC20Metadata(chainTokens[i].wrappedTokenVault).symbol();
        }
    }

    /// @notice The token `metadata` read at `index`.
    /// @param chainTokens The chain's tokens.
    /// @param index The index into `metadata`.
    /// @return The vault or wrapper read there.
    function metadataToken(TokenInstance[] memory chainTokens, uint256 index) internal pure returns (address) {
        TokenInstance memory token = chainTokens[index / 4];
        return index % 4 < 2 ? token.receiptVault : token.wrappedTokenVault;
    }

    /// @notice Reverts unless `vault` serves the facet's asset id getter with an
    /// empty id and refuses `initializeAssetId` with `AssetIdNotInitializing`.
    /// @param vault A live vault behind the upgraded beacon.
    function assertAssetIdHook(address vault) internal {
        string memory assetId = IStoxAssetIdV1(vault).assetId();
        if (bytes(assetId).length != 0) revert UpgradedVaultHasAssetId(vault, assetId);
        (bool success, bytes memory result) =
            vault.call(abi.encodeCall(StoxCorporateActionsFacet.initializeAssetId, (bytes(""))));
        if (success || keccak256(result) != keccak256(abi.encodeWithSelector(AssetIdNotInitializing.selector))) {
            revert UpgradedVaultMissingAssetIdHook(vault, result);
        }
    }

    /// @notice Reverts unless `beacon` points at `expected`.
    /// @param beacon The beacon.
    /// @param expected The implementation.
    function assertBeacon(address beacon, address expected) internal view {
        address actual = IBeacon(beacon).implementation();
        if (actual != expected) revert BeaconNotUpgraded(beacon, expected, actual);
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.25/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.25/src/lib/LibSafeTx.sol";

import {LibBeaconInvariants} from "../src/lib/LibBeaconInvariants.sol";
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

/// @title ScheduleUnderlyingNamingBeacons
/// @notice Authors the per-chain Safe bundle that SCHEDULES the
/// underlying-naming beacon batch on the chain's governance timelock (rollout
/// step 2 in `docs/TIMELOCK.md`; see `LibUnderlyingNamingRollout` for
/// the calls). One Safe call: `timelock.scheduleBatch(...)` with the pinned
/// 48h delay.
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
    function declaration() external pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.notAMigration();
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
    /// @dev The release is frozen, the Safe and timelock are the pinned ones,
    /// the timelock owns the in-use beacons, the three implementations carry their pinned code, the
    /// beacons have not moved, and the operation is not registered.
    function preflight() internal view override {
        if (!releaseFrozen()) revert UnderlyingNamingReleaseNotFrozen();
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock(), chainSafe);
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

        bytes32 id = LibUnderlyingNamingRollout.beaconOperationId(timelock(), block.chainid);
        if (TimelockController(payable(timelock())).isOperation(id)) revert OperationAlreadyScheduled(id);
    }

    /// @inheritdoc SafeBundleScript
    function authorBundle() internal view override returns (SafeTx[] memory txs) {
        txs = new SafeTx[](1);
        txs[0] = SafeTx({
            to: timelock(),
            value: 0,
            data: LibUnderlyingNamingRollout.scheduleBeaconCalldata(block.chainid),
            operation: Enum.Operation.Call
        });
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Scheduled, pending and not ready inside the delay.
    function assertPostState() internal view override {
        TimelockController controller = TimelockController(payable(timelock()));
        bytes32 id = LibUnderlyingNamingRollout.beaconOperationId(timelock(), block.chainid);
        if (!controller.isOperationPending(id) || controller.isOperationReady(id)) {
            revert OperationNotPendingInsideDelay(id);
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

    /// @notice The execution proof `assertReversible` runs.
    function proveExecution() internal {
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
        console2.log("Execution proven: both beacons upgraded by a roleless executor after 48h");
    }

    /// @notice Reverts unless `beacon` points at `expected`.
    /// @param beacon The beacon.
    /// @param expected The implementation.
    function assertBeacon(address beacon, address expected) internal view {
        address actual = IBeacon(beacon).implementation();
        if (actual != expected) revert BeaconNotUpgraded(beacon, expected, actual);
    }
}

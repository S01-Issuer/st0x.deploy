// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.22/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.22/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.22/src/lib/LibSafeFork.sol";

import {ST0xOrchestrator} from "../src/concrete/ST0xOrchestrator.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibBeaconInvariants} from "../src/lib/LibBeaconInvariants.sol";
import {LibOrchestratorInvariants} from "../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @notice This repo's line is not at the orchestrator admin move, which
/// this upgrade is applied onto: the move has not executed on this chain,
/// or something has been recorded after it.
/// @param head The line's head.
error UnexpectedMigrationLine(bytes32 head);

/// @notice The timelock is not approved to write this repo's line under
/// `LibStoxMigrations.WRITER`, so the batch's record would revert at execution.
/// @param timelock The timelock.
error TimelockNotApprovedWriter(address timelock);

/// @notice A candidate implementation is not deployed at its pinned address
/// with its pinned code hash.
/// @param implementation The pinned address.
/// @param expected The pinned code hash.
/// @param actual The code hash there.
error CandidateNotDeployed(address implementation, bytes32 expected, bytes32 actual);

/// @notice After the bundle, the upgrade is not pending inside the delay.
/// @param operationId The timelock operation.
error UpgradeNotPending(bytes32 operationId);

/// @notice After the delay, a beacon does not serve its candidate.
/// @param beacon The beacon.
/// @param expected The candidate.
/// @param actual What it serves.
error BeaconNotUpgraded(address beacon, address expected, address actual);

/// @notice After the delay, the upgrade's record is not the one the batch
/// writes, or the line does not end at it.
/// @param recordedAt The recorded moment.
/// @param head The line's head.
error UpgradeNotRecorded(uint256 recordedAt, bytes32 head);

/// @notice After the delay, the orchestrator does not accept the vault logic
/// it is now paired with.
error VaultLogicNotExpected();

/// @notice The Safe's cancel left the upgrade pending.
/// @param operationId The timelock operation.
error UpgradeNotCancelled(bytes32 operationId);

/// @title UpgradeTokenBeacons
/// @notice Authors the per-chain Safe Tx Builder bundle that schedules, on the
/// chain's governance timelock, one batch that upgrades the receipt-vault,
/// receipt and orchestrator beacons onto the candidate implementations and
/// records it. One call:
///
/// `timelock.scheduleBatch([vaultBeacon, receiptBeacon, orchestratorBeacon,
/// registry], [0, 0, 0, 0], [upgradeTo(vault), upgradeTo(receipt),
/// upgradeTo(orchestrator), applyMigrationV3(WRITER, NAMESPACE,
/// TOKEN_BEACONS_UPGRADE, [ORCHESTRATOR_ADMIN_TO_TIMELOCK])], 0, SALT,
/// minDelay)`.
///
/// The three beacons move in one operation because the orchestrator pins the
/// vault and receipt implementations it was built against: upgrading the
/// vault without it halts minting until the orchestrator follows. The record
/// is the last call, written by the timelock as `LibStoxMigrations.WRITER`'s
/// approved delegate, so it lands with the upgrade whoever executes.
///
/// Each chain's beacons are its own (`LibBeaconInvariants.prodBeaconsForChainId`):
/// Base's V1 set, the 0.1.1 set elsewhere. The candidates are the same address
/// on every chain and must be deployed before this is scheduled.
///
/// `run()` and `verify()` are `SafeBundleScript`'s: `run()` executes the
/// bundle through the Safe on the fork, requires the operation pending, proves
/// on a snapshot that it executes after the delay into the upgraded state and
/// that the Safe can cancel it inside the delay, and writes the artifact;
/// `verify(path)` holds a downloaded artifact to the bundle re-derived from
/// live state.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20261022-upgrade-token-beacons` per chain, only after
/// `20261006-orchestrator-admin-to-timelock` has executed there and the
/// candidates are deployed.
contract UpgradeTokenBeacons is SafeBundleScript {
    /// @notice `script/20261022-upgrade-token-beacons.s.sol`: the receipt-vault,
    /// receipt and orchestrator beacons serve the candidate implementations.
    bytes32 internal constant TOKEN_BEACONS_UPGRADE = keccak256("script/20261022-upgrade-token-beacons.s.sol");

    /// @notice The salt of the timelock operation.
    bytes32 internal constant SALT = keccak256("st0x.upgrade-token-beacons");

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x: schedule the token beacon upgrade on the governance timelock";
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Chain-suffixed, for the ACTIVE chain.
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261022-upgrade-token-beacons-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The chain's token-owner Safe. `preflight` proves it in policy.
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @notice The chain's governance timelock. `preflight` proves its state.
    /// @return The timelock.
    function timelock() internal view returns (address) {
        return LibTimelockInvariants.timelockForChainId(block.chainid);
    }

    /// @notice The scheduled batch: the three upgrades, then the record.
    /// @return targets The beacons, then the registry.
    /// @return values Zero for each.
    /// @return payloads The calls.
    function batch()
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        targets = new address[](4);
        values = new uint256[](4);
        payloads = new bytes[](4);
        targets[0] = beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX];
        payloads[0] = abi.encodeCall(UpgradeableBeacon.upgradeTo, (LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE));
        targets[1] = beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX];
        payloads[1] = abi.encodeCall(UpgradeableBeacon.upgradeTo, (LibProdDeployV4.STOX_RECEIPT_CANDIDATE));
        targets[2] = beacons[LibBeaconInvariants.ORCHESTRATOR_BEACON_INDEX];
        payloads[2] = abi.encodeCall(UpgradeableBeacon.upgradeTo, (LibProdDeployV4.ST0X_ORCHESTRATOR_CANDIDATE));
        (targets[3], payloads[3]) = LibStoxMigrations.applyMigrationCall(
            TOKEN_BEACONS_UPGRADE, LibStoxMigrations.onto(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK)
        );
    }

    /// @notice The timelock operation id of `batch()`.
    /// @return The id.
    function operationId() internal view returns (bytes32) {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = batch();
        return TimelockController(payable(timelock())).hashOperationBatch(targets, values, payloads, 0, SALT);
    }

    /// @notice Reverts unless `implementation` holds `codehash`.
    /// @param implementation The candidate's pinned address.
    /// @param codehash The candidate's pinned code hash.
    function assertCandidate(address implementation, bytes32 codehash) internal view {
        if (implementation.codehash != codehash) {
            revert CandidateNotDeployed(implementation, codehash, implementation.codehash);
        }
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The Safe and the timelock are what this repo pins, every beacon is
    /// the timelock's, the candidates the batch points at and the facet the
    /// vault delegates to are deployed, the line is at the admin move, and the
    /// timelock may write it.
    function preflight() internal view override {
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock(), chainSafe);
        LibBeaconInvariants.assertProdBeaconsOwnedByChainTimelock(block.chainid);

        assertCandidate(
            LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE, LibProdDeployV4.STOX_RECEIPT_VAULT_CODEHASH_CANDIDATE
        );
        assertCandidate(LibProdDeployV4.STOX_RECEIPT_CANDIDATE, LibProdDeployV4.STOX_RECEIPT_CODEHASH_CANDIDATE);
        assertCandidate(
            LibProdDeployV4.ST0X_ORCHESTRATOR_CANDIDATE, LibProdDeployV4.ST0X_ORCHESTRATOR_CODEHASH_CANDIDATE
        );
        assertCandidate(
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE,
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CODEHASH_CANDIDATE
        );

        bytes32 head = LibStoxMigrations.head();
        if (head != LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) {
            revert UnexpectedMigrationLine(head);
        }
        if (!LibStoxMigrations.approved(timelock())) {
            revert TimelockNotApprovedWriter(timelock());
        }
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The schedule, at the timelock's minimum delay.
    function authorBundle() internal view override returns (SafeTx[] memory) {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = batch();
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = SafeTx({
            to: timelock(),
            value: 0,
            data: abi.encodeCall(
                TimelockController.scheduleBatch,
                (targets, values, payloads, bytes32(0), SALT, LibTimelockInvariants.TIMELOCK_MIN_DELAY)
            ),
            operation: Enum.Operation.Call
        });
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The operation is pending and not yet ready, and the Safe still
    /// carries the token-owner policy.
    function assertPostState() internal view override {
        TimelockController controller = TimelockController(payable(timelock()));
        bytes32 id = operationId();
        if (!controller.isOperationPending(id) || controller.isOperationReady(id)) {
            revert UpgradeNotPending(id);
        }
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
    }

    /// @inheritdoc SafeBundleScript
    /// @dev On snapshots, so `run()` writes the artifact from the post-bundle
    /// state: after the delay anyone executes the batch into the upgraded,
    /// recorded state the orchestrator accepts, and inside the delay the Safe
    /// can cancel it.
    function assertReversible() internal override {
        uint256 postBundle = vm.snapshotState();
        proveExecution();
        vm.revertToState(postBundle);
        proveCancel();
        vm.revertToState(postBundle);
    }

    /// @notice The batch executes after the delay, from an address with no
    /// role, into the upgraded and recorded state.
    function proveExecution() internal {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = batch();
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        vm.prank(address(0xdead));
        TimelockController(payable(timelock())).executeBatch(targets, values, payloads, bytes32(0), SALT);

        address[3] memory candidates = [
            LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE,
            LibProdDeployV4.STOX_RECEIPT_CANDIDATE,
            LibProdDeployV4.ST0X_ORCHESTRATOR_CANDIDATE
        ];
        for (uint256 i = 0; i < candidates.length; i++) {
            address serving = IBeacon(targets[i]).implementation();
            if (serving != candidates[i]) {
                revert BeaconNotUpgraded(targets[i], candidates[i], serving);
            }
        }
        uint256 recordedAt = LibStoxMigrations.applied(TOKEN_BEACONS_UPGRADE);
        bytes32 head = LibStoxMigrations.head();
        // forge-lint: disable-next-line(block-timestamp)
        if (recordedAt != block.timestamp || head != TOKEN_BEACONS_UPGRADE) {
            revert UpgradeNotRecorded(recordedAt, head);
        }
        if (!ST0xOrchestrator(payable(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE)).vaultLogicIsExpected()) {
            revert VaultLogicNotExpected();
        }
        console2.log("Upgrade proven: executes after the delay into the candidates, recorded");
    }

    /// @notice The Safe cancels the operation inside the delay under its live
    /// threshold.
    function proveCancel() internal {
        bytes32 id = operationId();
        LibSafeFork.simulateNPlus1(vm, safe(), timelock(), abi.encodeCall(TimelockController.cancel, (id)));
        if (TimelockController(payable(timelock())).isOperationPending(id)) {
            revert UpgradeNotCancelled(id);
        }
        console2.log("Cancel proven: the Safe can veto the upgrade inside the delay");
    }
}

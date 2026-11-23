// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {SafeBundleScript} from "rain-deploy-0.1.30/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {LibUnderlyingNamingRollout} from "../src/lib/LibUnderlyingNamingRollout.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";

/// @notice The broadcasting key holds `EXECUTOR_ROLE`, so an execution would
/// prove nothing about permissionless execution.
/// @param timelock The timelock.
/// @param executor The broadcasting key.
error UnderlyingNamingExecutorHoldsRole(address timelock, address executor);

/// @notice No rollout operation can execute: the beacon batch is not ready, and the rename batch is not ready or waits
/// for the beacon batch.
/// @param beaconId The beacon batch's operation id.
/// @param beaconDone Whether the beacon batch has executed.
/// @param renameId The rename batch's operation id.
/// @param renameDone Whether the rename batch has executed.
error NoUnderlyingNamingOperationReady(bytes32 beaconId, bool beaconDone, bytes32 renameId, bool renameDone);

/// @notice The executed operation is not done afterwards.
/// @param id The operation id.
error UnderlyingNamingOperationNotDone(bytes32 id);

/// @notice The rename batch has not executed, so there is nothing to record.
/// @param renameId The rename batch's operation id.
error UnderlyingNamingNotExecuted(bytes32 renameId);

/// @notice The root line already holds this script's record.
/// @param id The migration id.
error ExecuteUnderlyingNamingRecorded(bytes32 id);

/// @notice This script's declaration on the root line: after the rename schedule.
/// @return The declaration.
function executeUnderlyingNamingDeclaration() pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.EXECUTE_UNDERLYING_NAMING,
        onto: LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME,
        history: false
    });
}

/// @title ExecuteUnderlyingNaming
/// @notice `execute()` executes the next ready underlying-naming operation on
/// the active chain from the CI deploy key, which holds no role: the beacon
/// batch if it is ready, otherwise the rename batch once the beacon batch is
/// done. One operation per
/// dispatch. Both operations are reconstructed by `LibUnderlyingNamingRollout`,
/// the same library the scheduling scripts use, so only calldata committed in
/// this repo can execute.
///
/// `run()` authors the record-only Safe bundle that writes this script's
/// record on the root line once the rename batch has executed, outside any
/// timelock batch.
///
/// A reverted `executeBatch` rolls back and leaves the operation Ready with
/// its delay spent, so a failed dispatch (a missing facet, gas) is fixed and
/// re-dispatched without rescheduling.
///
/// **HyperEVM:** the rename batch needs more gas than a small block holds.
/// Enable big blocks for the CI deploy key (`manual-hyperevm-big-blocks`)
/// before dispatching it there.
///
/// @dev Dispatch `execute()` via `Actions → manual-broadcast` with
/// `script = 20261021-execute-underlying-naming`, `sig = execute()` per chain,
/// and `run()` via `Actions → run-script` with the same `script`.
contract ExecuteUnderlyingNaming is SafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration(uint256) external pure returns (ScriptDeclaration memory) {
        return executeUnderlyingNamingDeclaration();
    }

    /// @notice Execute the next ready rollout operation.
    function execute() external {
        address safeAddress = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock, safeAddress);
        if (IAccessControl(timelock).hasRole(LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE, msg.sender)) {
            revert UnderlyingNamingExecutorHoldsRole(timelock, msg.sender);
        }

        TimelockController controller = TimelockController(payable(timelock));
        bytes32 beaconId = LibUnderlyingNamingRollout.beaconOperationId(timelock, block.chainid);
        bytes32 renameId = LibUnderlyingNamingRollout.renameOperationId(timelock, block.chainid);

        if (controller.isOperationReady(beaconId)) {
            (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
                LibUnderlyingNamingRollout.beaconBatch(block.chainid);
            console2.log("Executing the beacon batch:", vm.toString(beaconId));
            vm.startBroadcast();
            controller.executeBatch(targets, values, payloads, bytes32(0), LibUnderlyingNamingRollout.BEACON_SALT);
            vm.stopBroadcast();
            if (!controller.isOperationDone(beaconId)) revert UnderlyingNamingOperationNotDone(beaconId);
            return;
        }
        // The rename's predecessor is the beacon batch, so it waits for it.
        if (controller.isOperationReady(renameId) && controller.isOperationDone(beaconId)) {
            (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
                LibUnderlyingNamingRollout.renameBatch(block.chainid);
            console2.log("Executing the rename batch:", vm.toString(renameId));
            vm.startBroadcast();
            controller.executeBatch(targets, values, payloads, beaconId, LibUnderlyingNamingRollout.RENAME_SALT);
            vm.stopBroadcast();
            if (!controller.isOperationDone(renameId)) revert UnderlyingNamingOperationNotDone(renameId);
            return;
        }
        revert NoUnderlyingNamingOperationReady(
            beaconId, controller.isOperationDone(beaconId), renameId, controller.isOperationDone(renameId)
        );
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x migration record: execute-underlying-naming";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261021-execute-underlying-naming-record-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @inheritdoc SafeBundleScript
    function preflight() internal view override {
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        bytes32 renameId = LibUnderlyingNamingRollout.renameOperationId(timelock, block.chainid);
        if (!TimelockController(payable(timelock)).isOperationDone(renameId)) {
            revert UnderlyingNamingNotExecuted(renameId);
        }
        bytes32 id = LibStoxMigrations.EXECUTE_UNDERLYING_NAMING;
        if (LibStoxMigrations.applied(id) != 0) revert ExecuteUnderlyingNamingRecorded(id);
        LibStoxMigrations.assertNext(executeUnderlyingNamingDeclaration(), chainSafe);
    }

    /// @inheritdoc SafeBundleScript
    function authorBundle() internal view override returns (SafeTx[] memory) {
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = LibStoxMigrations.recordTx(executeUnderlyingNamingDeclaration());
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    function assertPostState() internal view override {
        LibStoxMigrations.assertRecorded(executeUnderlyingNamingDeclaration());
    }
}

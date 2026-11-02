// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";

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

/// @notice Neither rollout operation is ready on this chain.
/// @param beaconId The beacon batch's operation id.
/// @param beaconDone Whether the beacon batch has executed.
/// @param renameId The rename batch's operation id.
/// @param renameDone Whether the rename batch has executed.
error NoUnderlyingNamingOperationReady(bytes32 beaconId, bool beaconDone, bytes32 renameId, bool renameDone);

/// @notice The executed operation is not done afterwards.
/// @param id The operation id.
error UnderlyingNamingOperationNotDone(bytes32 id);

/// @title ExecuteUnderlyingNaming
/// @notice Executes the next ready underlying-naming operation on the active
/// chain from the CI deploy key, which holds no role: the beacon batch if it is
/// ready, otherwise the rename batch. One operation per dispatch. Both
/// operations are reconstructed by `LibUnderlyingNamingRollout`, the same
/// library the scheduling scripts use, so only calldata committed in this
/// repo can execute.
///
/// A reverted `executeBatch` rolls back and leaves the operation Ready with
/// its delay spent, so a failed dispatch (a missing facet, gas) is fixed and
/// re-dispatched without rescheduling.
///
/// **HyperEVM:** the rename batch needs more gas than a small block holds.
/// Enable big blocks for the CI deploy key (`manual-hyperevm-big-blocks`)
/// before dispatching it there.
///
/// @dev Dispatch via `Actions → manual-broadcast` with
/// `script = 20261021-execute-underlying-naming` per chain.
contract ExecuteUnderlyingNaming is Script, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.notAMigration();
    }

    /// @notice Execute the next ready rollout operation.
    function run() external {
        address safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock, safe);
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
        if (controller.isOperationReady(renameId)) {
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
}

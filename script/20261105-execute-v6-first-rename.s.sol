// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";

import {TokenConfig} from "../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {LibV6FirstRename} from "../src/lib/LibV6FirstRename.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";

/// @notice The broadcasting key holds `EXECUTOR_ROLE`, so an execution would
/// prove nothing about permissionless execution.
/// @param timelock The timelock.
/// @param executor The broadcasting key.
error V6FirstRenameExecutorHoldsRole(address timelock, address executor);

/// @notice The batch is not ready on this chain.
/// @param id The operation id.
/// @param pending Whether it is pending (scheduled, in its delay or ready).
/// @param done Whether it has executed.
error V6FirstRenameNotReady(bytes32 id, bool pending, bool done);

/// @notice The executed operation is not done afterwards.
/// @param id The operation id.
error V6FirstRenameNotDone(bytes32 id);

/// @notice This script's declaration on the root line: after the schedule.
/// @return The declaration.
function executeV6FirstRenameDeclaration() pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.EXECUTE_V6_FIRST_RENAME, onto: LibStoxMigrations.SCHEDULE_V6_FIRST_RENAME, history: false
    });
}

/// @title ExecuteV6FirstRename
/// @notice Executes the ready V6 first-rename batch on the governance timelock
/// from the CI deploy key, which holds no role, then checks every V6 token of the batch's
/// name, symbol and asset id. The batch is rebuilt by `LibV6FirstRename`, the
/// same library the schedule script uses, so only calldata committed in this
/// repo can execute. A reverted `executeBatch` leaves the operation Ready, so
/// a failed dispatch is fixed and dispatched again without rescheduling.
///
/// After it runs, the Safe signs `records/20261105-record-execute-v6-first-rename`
/// to write this migration's record.
///
/// **HyperEVM:** the batch needs more gas than a small block holds. Enable big
/// blocks for the CI deploy key (`manual-hyperevm-big-blocks`) before
/// dispatching it there.
///
/// @dev Dispatch via `Actions → manual-broadcast` with
/// `script = 20261105-execute-v6-first-rename` per chain, after the delay.
contract ExecuteV6FirstRename is Script, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration(uint256) external pure returns (ScriptDeclaration memory) {
        return executeV6FirstRenameDeclaration();
    }

    /// @notice Execute the ready batch.
    function run() external {
        address safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address timelock = LibV6FirstRename.timelock();
        LibTimelockInvariants.assertTimelockState(timelock, safe);
        if (IAccessControl(timelock).hasRole(LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE, msg.sender)) {
            revert V6FirstRenameExecutorHoldsRole(timelock, msg.sender);
        }
        TokenConfig[] memory configs = LibV6FirstRename.rows();
        TimelockController controller = TimelockController(payable(timelock));
        bytes32 id = LibV6FirstRename.operationId(configs);
        if (!controller.isOperationReady(id)) {
            revert V6FirstRenameNotReady(id, controller.isOperationPending(id), controller.isOperationDone(id));
        }
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = LibV6FirstRename.batch(configs);
        console2.log("Executing the V6 first-rename batch:", vm.toString(id));
        vm.startBroadcast();
        controller.executeBatch(targets, values, payloads, bytes32(0), LibV6FirstRename.SALT);
        vm.stopBroadcast();
        if (!controller.isOperationDone(id)) revert V6FirstRenameNotDone(id);
        LibV6FirstRename.assertAllNamed(configs);
    }
}

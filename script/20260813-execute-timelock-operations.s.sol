// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.2/src/Script.sol";
import {console2} from "forge-std-1.16.2/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.6.1/governance/TimelockController.sol";

import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {LibTimelockRehearsal} from "../src/lib/LibTimelockRehearsal.sol";

/// @notice The active chain's governance-timelock pin is unhydrated.
/// @param chainId The active chain id.
error ExecuteTimelockNotPinned(uint256 chainId);

/// @notice The operation is not in a state this script can execute: it is
/// unknown, already done, or still waiting out its delay.
/// @param id The operation id.
/// @param pending Whether the timelock reports it pending.
/// @param ready Whether the timelock reports it ready.
/// @param done Whether the timelock reports it done.
error OperationNotExecutable(bytes32 id, bool pending, bool ready, bool done);

/// @notice The key this script is broadcasting from holds `EXECUTOR_ROLE`, so
/// a successful execution would prove nothing about permissionlessness — the
/// whole point of this script is that it executes WITHOUT privilege.
/// @param timelock The timelock inspected.
/// @param executor The broadcasting key that unexpectedly holds the role.
error ExecutorHoldsRole(address timelock, address executor);

/// @title ExecuteTimelockOperations
/// @notice **PENDING.** Executes a matured timelock operation from the CI
/// deploy key.
///
/// This is deliberately NOT a Safe-routed script. The timelock grants
/// `EXECUTOR_ROLE` to `address(0)`, so once an operation's delay has run
/// ANYONE may execute it. Driving execution from the CI deploy key — a key
/// that holds no role on the timelock, the authoriser or any vault — is the
/// most direct demonstration that the property is real: if this succeeds,
/// execution is genuinely permissionless and the operator cannot censor a
/// matured operation.
///
/// Dispatch via `Actions → manual-broadcast` with
/// `script = 20260813-execute-timelock-operations` and the target `network`.
///
/// ## Which operation
///
/// OZ's `TimelockController` stores only a timestamp per operation id; it
/// keeps no enumerable list, so "every outstanding proposal" cannot be read
/// from contract state alone — recovering it would mean indexing
/// `CallScheduled` logs. Rather than pretend otherwise, this script executes
/// operations it can RECONSTRUCT, and asserts their state before acting.
/// Today that is the rehearsal no-op defined in `LibTimelockRehearsal`,
/// whose parameters are fixed and shared with the scripts that schedule and
/// cancel it, so the three cannot drift onto different ids. A future
/// operation is added by appending its reconstruction here, which also keeps
/// the executor honest: it can only ever run something whose full calldata is
/// committed in this repo and therefore reviewable.
///
/// @dev Pre-flight asserts the timelock's pinned configuration —
/// `LibTimelockInvariants.assertTimelockState` asserts the open executor role
/// positively and fails by name (`TimelockMissingRole`) on a timelock whose
/// executor role had been closed, so this script does not restate that check.
/// It asserts the one property the shared invariant cannot see: that the
/// broadcasting key itself holds no `EXECUTOR_ROLE`. That check runs BEFORE
/// the broadcast, because reporting it afterwards would already have sent the
/// transaction.
contract ExecuteTimelockOperations is Script {
    /// @notice Execute the rehearsal operation on the active chain if it has
    /// matured. Broadcasts from the CI deploy key, which holds no roles.
    function run() external {
        address safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        if (timelock == address(0)) revert ExecuteTimelockNotPinned(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock, safe);

        // The executing key must hold no role — that is the point. Checked
        // before anything is broadcast: a privileged key that got this far
        // would execute the operation for real, retiring the rehearsal's
        // fixed operation id while proving nothing about permissionlessness.
        address executor = msg.sender;
        if (IAccessControl(timelock).hasRole(LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE, executor)) {
            revert ExecutorHoldsRole(timelock, executor);
        }

        TimelockController controller = TimelockController(payable(timelock));
        bytes memory payload = LibTimelockRehearsal.payload();
        bytes32 id = LibTimelockRehearsal.operationId(timelock);

        bool pending = controller.isOperationPending(id);
        bool ready = controller.isOperationReady(id);
        bool done = controller.isOperationDone(id);
        if (!ready) revert OperationNotExecutable(id, pending, ready, done);

        console2.log("Executing matured operation:", vm.toString(id));
        console2.log("Timelock:", vm.toString(timelock));
        console2.log("Chain:", block.chainid);

        vm.startBroadcast();
        controller.execute(timelock, 0, payload, bytes32(0), LibTimelockRehearsal.REHEARSAL_SALT);
        vm.stopBroadcast();

        require(controller.isOperationDone(id), "ExecuteTimelockOperations: operation did not complete");

        console2.log("Executed by:", vm.toString(executor));
        console2.log("That address holds no EXECUTOR_ROLE - execution is permissionless");
    }
}

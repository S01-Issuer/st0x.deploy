// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
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

/// @notice Execution is not open on this timelock, so the CI deploy key —
/// which holds no roles — cannot execute. Surfaced by name because the whole
/// point of this script is that it needs no privilege.
/// @param timelock The timelock inspected.
error ExecutionNotPermissionless(address timelock);

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
/// @dev Pre-flight asserts the timelock's pinned configuration AND that
/// execution is open, so a timelock whose executor role had been closed
/// fails by name rather than as an opaque `AccessControl` revert.
contract ExecuteTimelockOperations is Script {
    /// @notice Execute the rehearsal operation on the active chain if it has
    /// matured. Broadcasts from the CI deploy key, which holds no roles.
    function run() external {
        address safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        if (timelock == address(0)) revert ExecuteTimelockNotPinned(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock, safe);

        // The property this script depends on, asserted rather than assumed.
        if (!IAccessControl(timelock).hasRole(LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE, address(0))) {
            revert ExecutionNotPermissionless(timelock);
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
        address executor = msg.sender;
        controller.execute(timelock, 0, payload, bytes32(0), LibTimelockRehearsal.REHEARSAL_SALT);
        vm.stopBroadcast();

        require(controller.isOperationDone(id), "ExecuteTimelockOperations: operation did not complete");

        // The executing key holds no role — that is the point.
        require(
            !IAccessControl(timelock).hasRole(LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE, executor),
            "ExecuteTimelockOperations: executor unexpectedly holds EXECUTOR_ROLE"
        );

        console2.log("Executed by:", vm.toString(executor));
        console2.log("That address holds no EXECUTOR_ROLE - execution is permissionless");
    }
}

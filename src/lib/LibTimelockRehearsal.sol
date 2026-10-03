// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {TimelockController} from "@openzeppelin-contracts-5.6.1/governance/TimelockController.sol";

import {LibTimelockInvariants} from "./LibTimelockInvariants.sol";

/// @title LibTimelockRehearsal
/// @notice The definition of the timelock rehearsal operation — the single
/// place the schedule script, the cancel script and the executor all read it
/// from.
///
/// The rehearsal exercises the governance timelock end-to-end: schedule,
/// cancel, schedule again, then execute once the delay has run.
///
/// The operation is `timelock.updateDelay(TIMELOCK_MIN_DELAY)` — re-setting
/// the delay to the value it already holds, a no-op. OZ's `updateDelay`
/// reverts unless the caller is the timelock itself, so it can only run
/// through the full schedule → delay → execute loop, and it targets the
/// timelock, never a production contract.
///
/// One-shot. `REHEARSAL_SALT` is a constant, so the operation id is a
/// constant per chain, and OZ's `TimelockController` never deregisters an
/// executed operation — `_execute` writes `DONE_TIMESTAMP` and `isOperation`
/// reports any non-`Unset` state. Once the rehearsal has been executed on a
/// chain, `schedule` reverts there forever and the schedule script's
/// `RehearsalAlreadyScheduled` pre-flight refuses every later dispatch.
/// `cancel` clears the timestamp outright, which is what makes the cancel →
/// re-propose stage possible. Rehearsing again after an execution needs a
/// new salt.
library LibTimelockRehearsal {
    /// @notice Salt distinguishing the rehearsal from any real governance
    /// operation, so the two can never collide on an id.
    bytes32 internal constant REHEARSAL_SALT = keccak256("st0x.timelock.rehearsal.20260813");

    /// @notice The no-op call: re-set the minimum delay to its current value.
    /// @return The `updateDelay` calldata.
    function payload() internal pure returns (bytes memory) {
        return abi.encodeCall(TimelockController.updateDelay, (LibTimelockInvariants.TIMELOCK_MIN_DELAY));
    }

    /// @notice The rehearsal operation's id on the supplied timelock.
    /// @param timelock The chain's governance timelock.
    /// @return The operation id.
    function operationId(address timelock) internal pure returns (bytes32) {
        return TimelockController(payable(timelock)).hashOperation(timelock, 0, payload(), bytes32(0), REHEARSAL_SALT);
    }

    /// @notice Calldata for the Safe to schedule the rehearsal.
    /// @param timelock The chain's governance timelock.
    /// @return The `schedule` calldata.
    function scheduleCalldata(address timelock) internal pure returns (bytes memory) {
        return abi.encodeCall(
            TimelockController.schedule,
            (timelock, 0, payload(), bytes32(0), REHEARSAL_SALT, LibTimelockInvariants.TIMELOCK_MIN_DELAY)
        );
    }

    /// @notice Calldata for the Safe to cancel the rehearsal.
    /// @param timelock The chain's governance timelock.
    /// @return The `cancel` calldata.
    function cancelCalldata(address timelock) internal pure returns (bytes memory) {
        return abi.encodeCall(TimelockController.cancel, (operationId(timelock)));
    }
}

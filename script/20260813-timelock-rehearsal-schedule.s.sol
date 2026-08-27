// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.2/src/Script.sol";
import {console2} from "forge-std-1.16.2/src/console2.sol";
import {TimelockController} from "@openzeppelin-contracts-5.6.1/governance/TimelockController.sol";

import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx} from "../src/lib/LibSafeOps.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {LibTimelockRehearsal} from "../src/lib/LibTimelockRehearsal.sol";

/// @notice The active chain's governance-timelock pin is unhydrated, so
/// there is nothing to rehearse against.
/// @param chainId The active chain id.
error RehearsalTimelockNotPinned(uint256 chainId);

/// @notice The rehearsal operation is already registered on the timelock, so
/// scheduling it again would revert inside the Safe transaction. Cancel it
/// (or execute it) first.
/// @param id The operation id already registered.
error RehearsalAlreadyScheduled(bytes32 id);

/// @notice Executing the scheduled rehearsal changed the timelock's minimum
/// delay. The rehearsal is a no-op by construction, so a change means the
/// operation is not the one this script believes it is.
/// @param expected The delay before execution.
/// @param actual The delay after.
error RehearsalChangedMinDelay(uint256 expected, uint256 actual);

/// @title TimelockRehearsalSchedule
/// @notice **PENDING.** Authors the Safe bundle that SCHEDULES the timelock
/// rehearsal no-op — see `LibTimelockRehearsal` for what the operation is and
/// why it was chosen.
///
/// Dispatch via `Actions → run-script` with
/// `script = 20260813-timelock-rehearsal-schedule` and the target `network`.
///
/// Re-dispatch this same script for the "re-propose" stage: `cancel` clears
/// the timestamp, so the identical operation becomes schedulable again, and
/// that recovery is itself the property worth rehearsing. No separate
/// re-schedule script exists because there is no separate operation.
///
/// Execution is NOT a Safe action: the timelock grants `EXECUTOR_ROLE` to
/// `address(0)`, so anyone may execute once the delay has run.
/// `20260813-execute-timelock-operations` does that from the CI deploy key.
///
/// @dev Pre-flight asserts the Safe's pinned policy and the timelock's pinned
/// configuration, and refuses if the operation is already registered — so a
/// stage dispatched out of order fails here rather than in the Safe. The run
/// then proves the whole loop on the fork: warp past the delay, execute as an
/// address holding no roles, and confirm the delay is unchanged.
contract TimelockRehearsalSchedule is Script {
    /// @notice Author the schedule bundle for the active chain.
    function run() external {
        IGnosisSafe safe = IGnosisSafe(LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid));
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        if (timelock == address(0)) revert RehearsalTimelockNotPinned(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock, address(safe));

        TimelockController controller = TimelockController(payable(timelock));
        bytes32 id = LibTimelockRehearsal.operationId(timelock);
        if (controller.isOperation(id)) revert RehearsalAlreadyScheduled(id);

        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = SafeTx({to: timelock, value: 0, data: LibTimelockRehearsal.scheduleCalldata(timelock), operation: 0});

        uint256 nonce = safe.nonce();
        bytes32 safeTxHash = LibSafeOps.computeSafeTxHashViaSafe(safe, txs[0], nonce);

        uint256 delayBefore = controller.getMinDelay();
        LibSafeOps.simulateExternalCall(safe, txs[0].to, txs[0].data);

        // Pending, and NOT executable until the delay has run.
        require(controller.isOperationPending(id), "TimelockRehearsalSchedule: operation not registered");
        require(!controller.isOperationReady(id), "TimelockRehearsalSchedule: ready before the delay elapsed");

        // Prove the loop on the fork, executing as an address with no roles —
        // which is what permissionless execution means.
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        require(controller.isOperationReady(id), "TimelockRehearsalSchedule: not ready after the delay");
        vm.prank(address(uint160(uint256(keccak256("st0x.rehearsal.roleless-executor")))));
        controller.execute(timelock, 0, LibTimelockRehearsal.payload(), bytes32(0), LibTimelockRehearsal.REHEARSAL_SALT);
        require(controller.isOperationDone(id), "TimelockRehearsalSchedule: execution did not complete");
        uint256 delayAfter = controller.getMinDelay();
        if (delayAfter != delayBefore) revert RehearsalChangedMinDelay(delayBefore, delayAfter);

        string memory artifactPath =
            string.concat("out/20260813-timelock-rehearsal-schedule-", vm.toString(block.chainid), ".json");
        string memory json = LibSafeOps.emitTxBuilderJson(
            address(safe), block.chainid, "ST0x timelock rehearsal: schedule the no-op", txs
        );
        vm.writeFile(artifactPath, json);

        console2.log("==== TX BUILDER JSON BEGIN ====");
        console2.log(json);
        console2.log("==== TX BUILDER JSON END ====");
        console2.log("Artifact:", artifactPath);
        console2.log("SafeTxHash:", vm.toString(safeTxHash));
        console2.log("Nonce:", nonce);
        console2.log("Operation id:", vm.toString(id));
        console2.log("Chain:", block.chainid);
        console2.log("Loop proven on fork: schedule -> 48h -> execute BY A ROLELESS ADDRESS -> delay unchanged");
    }
}

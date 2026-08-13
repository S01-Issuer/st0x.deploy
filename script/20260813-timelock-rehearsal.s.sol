// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {TimelockController} from "@openzeppelin-contracts-5.6.1/governance/TimelockController.sol";

import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx} from "../src/lib/LibSafeOps.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @notice The active chain's governance-timelock pin is unhydrated, so
/// there is nothing to rehearse against.
/// @param chainId The active chain id.
error RehearsalTimelockNotPinned(uint256 chainId);

/// @notice The rehearsal operation is already scheduled, so scheduling it
/// again would revert inside the Safe transaction. Cancel it first, or
/// execute it.
/// @param id The operation id already pending.
error RehearsalAlreadyScheduled(bytes32 id);

/// @notice The rehearsal operation is not scheduled, so there is nothing to
/// cancel.
/// @param id The operation id that is not pending.
error RehearsalNotScheduled(bytes32 id);

/// @notice The scheduled rehearsal did not leave the timelock's minimum
/// delay unchanged. The rehearsal is a no-op by construction — it re-sets
/// the delay to the value it already holds — so a change means the operation
/// being rehearsed is not the one this script believes it is.
/// @param expected The delay before the rehearsal executed.
/// @param actual The delay after.
error RehearsalChangedMinDelay(uint256 expected, uint256 actual);

/// @title TimelockRehearsal
/// @notice **PENDING.** Authors the Safe bundles that rehearse the
/// governance timelock end-to-end BEFORE any governance is handed to it:
/// schedule a no-op, cancel it, then schedule it again. Each entrypoint
/// emits its own Safe Tx Builder JSON, so the rehearsal is driven entirely
/// from the Safe UI exactly as real governance will be.
///
/// The operation rehearsed is `timelock.updateDelay(TIMELOCK_MIN_DELAY)` —
/// setting the delay to the value it ALREADY holds. That is deliberate on
/// three counts:
///
/// 1. It is a genuine no-op. Even executed, nothing changes.
/// 2. OZ's `updateDelay` reverts unless the caller is the timelock itself,
///    so it CANNOT be performed any way other than through the full
///    schedule → delay → execute loop. Rehearsing it therefore exercises the
///    real path rather than a shortcut.
/// 3. It targets the timelock, not any production contract, so a rehearsal
///    left half-finished cannot touch vaults, beacons or the authoriser.
///
/// Dispatch via `Actions → run-script` with
/// `script = 20260813-timelock-rehearsal`, the target `network`, and `sig`
/// selecting the stage:
///
/// - `run()`        — schedule the no-op (stage 1)
/// - `cancel()`     — cancel it (stage 2)
/// - `reschedule()` — schedule it again (stage 3)
///
/// Execution is NOT a Safe action: the timelock grants `EXECUTOR_ROLE` to
/// `address(0)`, so anyone may execute once the delay has run.
/// `20260813-execute-timelock-operations` does that from the CI deploy key,
/// which proves permissionlessness with a key that holds no roles at all.
///
/// @dev Every stage pre-flights the Safe's pinned policy and the timelock's
/// pinned configuration, simulates the call as the Safe, asserts the
/// resulting operation state, and emits the artifact. `cancel()` and
/// `reschedule()` additionally assert the state they depend on, so a stage
/// dispatched out of order refuses to author rather than emitting a bundle
/// that would revert in the Safe.
contract TimelockRehearsal is Script {
    /// @notice Salt distinguishing the rehearsal operation from any real
    /// governance action. Fixed so every stage — and the executor script —
    /// derives the same operation id without passing state between runs.
    bytes32 internal constant REHEARSAL_SALT = keccak256("st0x.timelock.rehearsal.20260813");

    /// @notice The active chain's governance timelock, asserted pinned and
    /// in its expected configuration.
    /// @return timelock The chain's timelock.
    /// @return safe The chain's token-owner Safe.
    function preflight() internal view returns (address timelock, IGnosisSafe safe) {
        safe = IGnosisSafe(LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid));
        timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        if (timelock == address(0)) revert RehearsalTimelockNotPinned(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock, address(safe));
    }

    /// @notice The no-op call the rehearsal schedules: re-set the timelock's
    /// minimum delay to the value it already holds.
    /// @return The `updateDelay` calldata.
    function rehearsalPayload() internal pure returns (bytes memory) {
        return abi.encodeCall(TimelockController.updateDelay, (LibTimelockInvariants.TIMELOCK_MIN_DELAY));
    }

    /// @notice The rehearsal operation's id on the active chain. Shared by
    /// every stage and by the executor script, so all four agree on which
    /// operation they are talking about.
    /// @param timelock The chain's timelock.
    /// @return The operation id.
    function rehearsalId(address timelock) internal view returns (bytes32) {
        return TimelockController(payable(timelock))
            .hashOperation(timelock, 0, rehearsalPayload(), bytes32(0), REHEARSAL_SALT);
    }

    /// @notice Stage 1 — schedule the no-op.
    function run() external {
        _authorSchedule("out/20260813-timelock-rehearsal-schedule-", "ST0x timelock rehearsal: schedule a no-op");
    }

    /// @notice Stage 3 — schedule the no-op again after the cancellation.
    /// Identical operation to `run()`: `cancel` clears the timestamp, so the
    /// same id becomes schedulable again, which is itself the property worth
    /// rehearsing.
    function reschedule() external {
        _authorSchedule("out/20260813-timelock-rehearsal-reschedule-", "ST0x timelock rehearsal: re-schedule the no-op");
    }

    /// @notice Stage 2 — cancel the scheduled no-op.
    function cancel() external {
        (address timelock, IGnosisSafe safe) = preflight();
        bytes32 id = rehearsalId(timelock);

        TimelockController controller = TimelockController(payable(timelock));
        if (!controller.isOperationPending(id)) revert RehearsalNotScheduled(id);

        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = SafeTx({to: timelock, value: 0, data: abi.encodeCall(TimelockController.cancel, (id)), operation: 0});

        uint256 nonce = safe.nonce();
        bytes32 safeTxHash = LibSafeOps.computeSafeTxHashViaSafe(safe, txs[0], nonce);

        LibSafeOps.simulateExternalCall(safe, txs[0].to, txs[0].data);

        // Post-state: the operation is gone, so it is neither pending nor
        // executable, and the same id is schedulable again.
        require(!controller.isOperationPending(id), "TimelockRehearsal: cancel did not clear the operation");
        require(!controller.isOperation(id), "TimelockRehearsal: operation still registered after cancel");

        _emit(
            "out/20260813-timelock-rehearsal-cancel-",
            "ST0x timelock rehearsal: cancel the no-op",
            safe,
            txs,
            safeTxHash,
            nonce,
            id
        );
    }

    /// @notice Author a schedule bundle under the supplied artifact prefix.
    /// @param pathPrefix Artifact path prefix; the chain id and `.json` are
    /// appended.
    /// @param bundleName Human-readable name shown in the Safe Tx Builder.
    function _authorSchedule(string memory pathPrefix, string memory bundleName) internal {
        (address timelock, IGnosisSafe safe) = preflight();
        bytes32 id = rehearsalId(timelock);

        TimelockController controller = TimelockController(payable(timelock));
        if (controller.isOperation(id)) revert RehearsalAlreadyScheduled(id);

        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = SafeTx({
            to: timelock,
            value: 0,
            data: abi.encodeCall(
                TimelockController.schedule,
                (timelock, 0, rehearsalPayload(), bytes32(0), REHEARSAL_SALT, LibTimelockInvariants.TIMELOCK_MIN_DELAY)
            ),
            operation: 0
        });

        uint256 nonce = safe.nonce();
        bytes32 safeTxHash = LibSafeOps.computeSafeTxHashViaSafe(safe, txs[0], nonce);

        uint256 delayBefore = controller.getMinDelay();
        LibSafeOps.simulateExternalCall(safe, txs[0].to, txs[0].data);

        // Post-state: pending, and NOT executable until the delay has run.
        require(controller.isOperationPending(id), "TimelockRehearsal: schedule did not register the operation");
        require(!controller.isOperationReady(id), "TimelockRehearsal: operation ready before the delay elapsed");

        // Prove the whole loop on the fork: warp past the delay and execute
        // as an arbitrary address with no roles, which is what permissionless
        // execution means, then confirm the no-op changed nothing.
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        require(controller.isOperationReady(id), "TimelockRehearsal: operation not ready after the delay");
        vm.prank(address(uint160(uint256(keccak256("st0x.rehearsal.random-executor")))));
        controller.execute(timelock, 0, rehearsalPayload(), bytes32(0), REHEARSAL_SALT);
        require(controller.isOperationDone(id), "TimelockRehearsal: execution did not complete the operation");
        uint256 delayAfter = controller.getMinDelay();
        if (delayAfter != delayBefore) revert RehearsalChangedMinDelay(delayBefore, delayAfter);

        _emit(pathPrefix, bundleName, safe, txs, safeTxHash, nonce, id);
        console2.log("Loop proven on fork: schedule -> 48h -> execute BY A ROLELESS ADDRESS -> delay unchanged");
    }

    /// @notice Write the Tx Builder JSON and log what a signer cross-checks.
    function _emit(
        string memory pathPrefix,
        string memory bundleName,
        IGnosisSafe safe,
        SafeTx[] memory txs,
        bytes32 safeTxHash,
        uint256 nonce,
        bytes32 id
    ) internal {
        string memory artifactPath = string.concat(pathPrefix, vm.toString(block.chainid), ".json");
        string memory json = LibSafeOps.emitTxBuilderJson(address(safe), block.chainid, bundleName, txs);
        vm.writeFile(artifactPath, json);

        console2.log("==== TX BUILDER JSON BEGIN ====");
        console2.log(json);
        console2.log("==== TX BUILDER JSON END ====");
        console2.log("Artifact:", artifactPath);
        console2.log("SafeTxHash:", vm.toString(safeTxHash));
        console2.log("Nonce:", nonce);
        console2.log("Operation id:", vm.toString(id));
        console2.log("Chain:", block.chainid);
    }
}

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
import {LibTimelockRehearsal} from "../src/lib/LibTimelockRehearsal.sol";

/// @notice The active chain's governance-timelock pin is unhydrated, so
/// there is nothing to rehearse against.
/// @param chainId The active chain id.
error CancelTimelockNotPinned(uint256 chainId);

/// @notice The rehearsal operation is not pending, so there is nothing to
/// cancel and the bundle would revert inside the Safe.
/// @param id The operation id that is not pending.
error RehearsalNotScheduled(bytes32 id);

/// @title TimelockRehearsalCancel
/// @notice **PENDING.** Authors the Safe bundle that CANCELS the scheduled
/// timelock rehearsal — see `LibTimelockRehearsal` for the operation.
///
/// This is the stage that demonstrates the veto: a scheduled operation can be
/// stopped inside its window, and OZ's `cancel` has no open-role path, so
/// vetoing stays privileged even though execution is permissionless. After it
/// lands, the identical operation becomes schedulable again — re-dispatch
/// `20260813-timelock-rehearsal-schedule` for the re-propose stage.
///
/// Dispatch via `Actions → run-script` with
/// `script = 20260813-timelock-rehearsal-cancel` and the target `network`.
///
/// @dev Refuses unless the operation is actually pending, so cancelling
/// nothing fails at authoring time rather than in the Safe. Post-state
/// asserts the operation is fully deregistered, which is what makes the
/// re-propose stage possible.
contract TimelockRehearsalCancel is Script {
    /// @notice Author the cancel bundle for the active chain.
    function run() external {
        IGnosisSafe safe = IGnosisSafe(LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid));
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        if (timelock == address(0)) revert CancelTimelockNotPinned(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock, address(safe));

        TimelockController controller = TimelockController(payable(timelock));
        bytes32 id = LibTimelockRehearsal.operationId(timelock);
        if (!controller.isOperationPending(id)) revert RehearsalNotScheduled(id);

        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = SafeTx({to: timelock, value: 0, data: LibTimelockRehearsal.cancelCalldata(timelock), operation: 0});

        uint256 nonce = safe.nonce();
        bytes32 safeTxHash = LibSafeOps.computeSafeTxHashViaSafe(safe, txs[0], nonce);

        LibSafeOps.simulateExternalCall(safe, txs[0].to, txs[0].data);

        // Fully deregistered: not pending, and not known to the timelock at
        // all — which is what lets the same operation be scheduled again.
        require(!controller.isOperationPending(id), "TimelockRehearsalCancel: still pending after cancel");
        require(!controller.isOperation(id), "TimelockRehearsalCancel: still registered after cancel");

        string memory artifactPath =
            string.concat("out/20260813-timelock-rehearsal-cancel-", vm.toString(block.chainid), ".json");
        string memory json = LibSafeOps.emitTxBuilderJson(
            address(safe), block.chainid, "ST0x timelock rehearsal: cancel the no-op", txs
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
        console2.log("Cancelled: the same operation is schedulable again - re-dispatch the schedule script");
    }
}

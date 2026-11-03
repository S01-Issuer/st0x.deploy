// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";

import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeTx} from "rain-deploy-0.1.29/src/lib/LibSafeTx.sol";
import {SafeBundleScript} from "rain-deploy-0.1.29/src/abstract/SafeBundleScript.sol";
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

/// @notice After the bundle, the root line does not end at this script's record.
/// @param head The line's head.
error LineHeadMismatch(bytes32 head);

/// @notice This script's declaration: on Base, history after the threshold
/// migration; elsewhere, recorded after the history block.
/// @param chainId The chain id.
/// @return The declaration.
function timelockRehearsalScheduleDeclaration(uint256 chainId) pure returns (ScriptDeclaration memory) {
    if (chainId == LibSafeInvariants.BASE_CHAIN_ID) {
        return ScriptDeclaration({
            id: LibStoxMigrations.TIMELOCK_REHEARSAL_SCHEDULE, onto: LibStoxMigrations.MULTISIG_THRESHOLD, history: true
        });
    }
    return ScriptDeclaration({
        id: LibStoxMigrations.TIMELOCK_REHEARSAL_SCHEDULE,
        onto: LibStoxMigrations.ORCHESTRATOR_EMERGENCY,
        history: false
    });
}

/// @title TimelockRehearsalSchedule
/// @notice Authors the Safe bundle that SCHEDULES the timelock rehearsal
/// no-op (see `LibTimelockRehearsal`) and writes this script's record on the
/// root line.
///
/// Execution is NOT a Safe action: the timelock grants `EXECUTOR_ROLE` to
/// `address(0)`, so anyone may execute once the delay has run.
/// `20260813-execute-timelock-operations` does that from the CI deploy key.
contract TimelockRehearsalSchedule is SafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration(uint256 chainId) external pure returns (ScriptDeclaration memory) {
        return timelockRehearsalScheduleDeclaration(chainId);
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x timelock rehearsal: schedule the no-op";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20260813-timelock-rehearsal-schedule-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @inheritdoc SafeBundleScript
    function preflight() internal view override {
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        if (timelock == address(0)) revert RehearsalTimelockNotPinned(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock, chainSafe);
        bytes32 id = LibTimelockRehearsal.operationId(timelock);
        if (TimelockController(payable(timelock)).isOperation(id)) revert RehearsalAlreadyScheduled(id);
    }

    /// @inheritdoc SafeBundleScript
    function authorBundle() internal view override returns (SafeTx[] memory) {
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        SafeTx[] memory txs = new SafeTx[](2);
        txs[0] = SafeTx({
            to: timelock,
            value: 0,
            data: LibTimelockRehearsal.scheduleCalldata(timelock),
            operation: Enum.Operation.Call
        });
        (address recordTo, bytes memory recordData) =
            LibStoxMigrations.recordCall(timelockRehearsalScheduleDeclaration(block.chainid));
        txs[1] = SafeTx({to: recordTo, value: 0, data: recordData, operation: Enum.Operation.Call});
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    function assertPostState() internal view override {
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        TimelockController controller = TimelockController(payable(timelock));
        bytes32 id = LibTimelockRehearsal.operationId(timelock);
        require(controller.isOperationPending(id), "TimelockRehearsalSchedule: operation not registered");
        require(!controller.isOperationReady(id), "TimelockRehearsalSchedule: ready before the delay elapsed");
        bytes32 head = LibStoxMigrations.head();
        if (head != LibStoxMigrations.TIMELOCK_REHEARSAL_SCHEDULE) revert LineHeadMismatch(head);
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Execution by a roleless address after the delay leaves the delay unchanged.
    function assertReversible() internal override {
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        TimelockController controller = TimelockController(payable(timelock));
        bytes32 id = LibTimelockRehearsal.operationId(timelock);
        uint256 delayBefore = controller.getMinDelay();
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        require(controller.isOperationReady(id), "TimelockRehearsalSchedule: not ready after the delay");
        vm.prank(address(uint160(uint256(keccak256("st0x.rehearsal.roleless-executor")))));
        controller.execute(timelock, 0, LibTimelockRehearsal.payload(), bytes32(0), LibTimelockRehearsal.REHEARSAL_SALT);
        require(controller.isOperationDone(id), "TimelockRehearsalSchedule: execution did not complete");
        uint256 delayAfter = controller.getMinDelay();
        if (delayAfter != delayBefore) revert RehearsalChangedMinDelay(delayBefore, delayAfter);
    }
}

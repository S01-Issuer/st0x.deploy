// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.30/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {TokenConfig} from "../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {LibV6FirstRename} from "../src/lib/LibV6FirstRename.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";

/// @notice The batch is already registered on the governance timelock: pending,
/// ready or done.
/// @param id The operation id.
error V6FirstRenameAlreadyScheduled(bytes32 id);

/// @notice The root line is neither at this migration's `onto` nor at its own
/// record.
/// @param head The line's head.
error ScheduleV6FirstRenameUnexpectedMigrationLine(bytes32 head);

/// @notice After the bundle the operation is not pending, or is ready inside
/// its delay.
/// @param id The operation id.
error V6FirstRenameNotPendingInsideDelay(bytes32 id);

/// @notice After the bundle the root line does not hold this migration's
/// record at its head.
/// @param head The line's head.
/// @param record The recorded moment, zero if none.
error ScheduleV6FirstRenameRecordMismatch(bytes32 head, uint256 record);

/// @notice This script's declaration on the root line: after the execution of
/// the live tokens' rename.
/// @return The declaration.
function scheduleV6FirstRenameDeclaration() pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.SCHEDULE_V6_FIRST_RENAME,
        onto: LibStoxMigrations.EXECUTE_UNDERLYING_NAMING,
        history: false
    });
}

/// @title ScheduleV6FirstRename
/// @notice Authors the per-chain Safe bundle that SCHEDULES the first
/// `setUnderlying` of every V6 token of the batch on the governance timelock
/// (`LibV6FirstRename`): `timelock.scheduleBatch(...)` with the 48h delay,
/// then the Safe's root-line record.
///
/// Pre-flight binds each call to its row by asset id: every V6 token of the batch must be
/// deployed at its pinned address, report its row's `assetId()`, be owned by
/// the governance timelock, and have no name or symbol yet. A nameless token
/// has no symbol, so the asset id takes the place of the live tokens'
/// `TickerNotBoundToVault` check.
///
/// **Cancel and reschedule.** While the delay runs the Safe can `cancel` the
/// batch. The record already sits at the head then, so a new dispatch authors
/// the schedule alone: the line stays where it is and the batch is
/// registered again.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20261105-schedule-v6-first-rename` per chain, once every V6 token of the batch
/// suite is deployed there.
contract ScheduleV6FirstRename is SafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration(uint256) external pure returns (ScriptDeclaration memory) {
        return scheduleV6FirstRenameDeclaration();
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x V6 tokens: schedule the first setUnderlying of the first 59 V6 tokens";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261105-schedule-v6-first-rename-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @notice Whether the root line already holds this migration's record,
    /// so the bundle only reschedules a cancelled batch.
    /// @return True when the head is this migration's own record.
    function rescheduling() internal view returns (bool) {
        return LibStoxMigrations.head() == scheduleV6FirstRenameDeclaration().id;
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The Safe and governance timelock are the pinned ones, the root
    /// line is at this migration's `onto` or at its own record, the batch is
    /// not registered, and every V6 token of the batch is ready to be named.
    function preflight() internal view override {
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibTimelockInvariants.assertTimelockState(LibV6FirstRename.timelock(), chainSafe);
        bytes32 head = LibStoxMigrations.head();
        ScriptDeclaration memory declared = scheduleV6FirstRenameDeclaration();
        if (head != declared.onto && head != declared.id) {
            revert ScheduleV6FirstRenameUnexpectedMigrationLine(head);
        }
        TokenConfig[] memory configs = LibV6FirstRename.rows();
        bytes32 id = LibV6FirstRename.operationId(configs);
        if (TimelockController(payable(LibV6FirstRename.timelock())).isOperation(id)) {
            revert V6FirstRenameAlreadyScheduled(id);
        }
        LibV6FirstRename.assertAllReady(configs);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The schedule, then the record unless the record is already the
    /// head.
    function authorBundle() internal view override returns (SafeTx[] memory txs) {
        bool reschedule = rescheduling();
        txs = new SafeTx[](reschedule ? 1 : 2);
        txs[0] = SafeTx({
            to: LibV6FirstRename.timelock(),
            value: 0,
            data: LibV6FirstRename.scheduleCalldata(LibV6FirstRename.rows(), LibTimelockInvariants.TIMELOCK_MIN_DELAY),
            operation: Enum.Operation.Call
        });
        if (!reschedule) {
            (address recordTo, bytes memory recordData) =
                LibStoxMigrations.recordCall(scheduleV6FirstRenameDeclaration());
            txs[1] = SafeTx({to: recordTo, value: 0, data: recordData, operation: Enum.Operation.Call});
        }
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Scheduled, pending and not ready inside the delay; this
    /// migration's record heads the root line.
    function assertPostState() internal view override {
        TimelockController controller = TimelockController(payable(LibV6FirstRename.timelock()));
        bytes32 id = LibV6FirstRename.operationId(LibV6FirstRename.rows());
        if (!controller.isOperationPending(id) || controller.isOperationReady(id)) {
            revert V6FirstRenameNotPendingInsideDelay(id);
        }
        bytes32 head = LibStoxMigrations.head();
        uint256 record = LibStoxMigrations.applied(LibStoxMigrations.SCHEDULE_V6_FIRST_RENAME);
        if (head != scheduleV6FirstRenameDeclaration().id || record == 0) {
            revert ScheduleV6FirstRenameRecordMismatch(head, record);
        }
    }

    /// @inheritdoc SafeBundleScript
    /// @dev On a snapshot: after the delay, executes the batch as an address
    /// with no role and checks every V6 token of the batch's name, symbol and asset id.
    function assertReversible() internal override {
        uint256 postBundle = vm.snapshotState();
        proveExecution();
        vm.revertToState(postBundle);
    }

    /// @notice The execution proof `assertReversible` runs.
    function proveExecution() internal {
        TokenConfig[] memory configs = LibV6FirstRename.rows();
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = LibV6FirstRename.batch(configs);
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        vm.prank(address(0xdead));
        TimelockController(payable(LibV6FirstRename.timelock()))
            .executeBatch(targets, values, payloads, bytes32(0), LibV6FirstRename.SALT);
        LibV6FirstRename.assertAllNamed(configs);
        console2.log("Execution proven: every V6 token of the batch named by a roleless executor");
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.30/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {LibProdTokenConfig, TokenConfig} from "../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../src/lib/LibTokenInvariants.sol";
import {
    LibUnderlyingNamingRollout,
    UnderlyingNamingBatchMoved,
    UnderlyingNamingReleaseNotFrozen,
    DownstreamNotReadyForRename
} from "../src/lib/LibUnderlyingNamingRollout.sol";
import {ST0X_NAME_SUFFIX} from "../src/lib/LibUnderlying.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibStoxMigrations, LineHeadMismatch, RecordMismatch} from "../src/lib/LibStoxMigrations.sol";

/// @notice The beacon batch is not registered on this chain's timelock, so
/// the rename batch, which names it as predecessor, could never execute.
/// @param beaconId The beacon batch's operation id.
error BeaconBatchNotScheduled(bytes32 beaconId);

/// @notice The rename batch is already registered on the timelock.
/// @param id The operation id.
error RenameAlreadyScheduled(bytes32 id);

/// @notice After the bundle the operation is not pending, or is ready inside
/// its delay.
/// @param id The operation id.
error RenameNotPendingInsideDelay(bytes32 id);

/// @notice After execution a token's metadata is not what the rename sets.
/// @param token The token contract.
/// @param expected The expected value.
/// @param actual The value read.
error RenamedMetadataMismatch(address token, string expected, string actual);

/// @notice A token of the chain's table that the rename skips changed its name or symbol across the execution.
/// @param token The token contract.
/// @param before The value before.
/// @param afterRun The value after.
error SkippedRowMetadataMoved(address token, string before, string afterRun);

/// @notice This script's declaration: the Safe's record, after the beacon schedule.
/// @return The declaration.
function scheduleUnderlyingNamingRenameDeclaration() pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME,
        onto: LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS,
        history: false
    });
}

/// @title ScheduleUnderlyingNamingRename
/// @notice Authors the per-chain Safe bundle that SCHEDULES the rename batch
/// (rollout step 3 in `docs/TIMELOCK.md`): `setUnderlying(ticker,
/// underlyingName)` on every production vault of the chain, ticker from
/// `TokenConfig.underlying` and name from `TokenConfig.underlyingName`. Two
/// Safe calls: `timelock.scheduleBatch(...)`, with the beacon batch as
/// predecessor so the timelock refuses to execute the rename first, then the
/// Safe's root-line record; or the schedule alone when rescheduling a
/// cancelled batch.
///
/// **The pre-flight refuses until
/// `LibUnderlyingNamingRollout.DOWNSTREAM_ACCEPTS_NEW_SYMBOLS` is set**, which
/// names the consumers that must accept `<TICKER>s` first. The rename is
/// one-way: `setUnderlying` overwrites the stored ERC-20 name and symbol, so
/// nothing on chain restores the initialized metadata. While the delay runs,
/// the Safe can still `cancel` the operation.
///
/// Pre-flight binds each ticker to its vault: every production vault must
/// report `"t" + underlying` as its live symbol, so a shifted or mistyped row
/// refuses here rather than renaming the wrong token. It also requires the
/// timelock to own every production vault of the chain, because the batch
/// executes `setUnderlying` as the timelock.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20261021-schedule-underlying-naming-rename` per chain, after the
/// beacon batch is scheduled there.
contract ScheduleUnderlyingNamingRename is SafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration(uint256) external pure returns (ScriptDeclaration memory) {
        return scheduleUnderlyingNamingRenameDeclaration();
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x underlying naming: schedule setUnderlying on every production vault";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261021-schedule-underlying-naming-rename-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @notice The chain's governance timelock.
    /// @return The timelock.
    function timelock() internal view returns (address) {
        return LibTimelockInvariants.timelockForChainId(block.chainid);
    }

    /// @notice Whether the implementations are a frozen, audited release.
    /// @return `LibUnderlyingNamingRollout.RELEASE_FROZEN`.
    function releaseFrozen() internal pure virtual returns (bool) {
        return LibUnderlyingNamingRollout.RELEASE_FROZEN;
    }

    /// @notice Whether the downstream services accept the new symbols.
    /// @return `LibUnderlyingNamingRollout.DOWNSTREAM_ACCEPTS_NEW_SYMBOLS`.
    function downstreamReady() internal pure virtual returns (bool) {
        return LibUnderlyingNamingRollout.DOWNSTREAM_ACCEPTS_NEW_SYMBOLS;
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The root line is at this migration's `onto`, or its own record
    /// heads it and the batch is being rescheduled after a cancel. The release
    /// is frozen, the downstream services accept the new
    /// symbols, every row is well formed, the Safe and timelock are the pinned ones,
    /// the beacon batch is registered, the rename batch is not, every ticker
    /// is bound to its vault, the timelock owns every vault, and the derived id is the pinned one.
    function preflight() internal view override {
        if (!releaseFrozen()) revert UnderlyingNamingReleaseNotFrozen();
        if (!downstreamReady()) revert DownstreamNotReadyForRename();
        LibUnderlyingNamingRollout.assertUnderlyingsWellFormed(block.chainid);
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock(), chainSafe);
        if (!rescheduling()) LibStoxMigrations.assertNext(scheduleUnderlyingNamingRenameDeclaration(), chainSafe);
        TimelockController controller = TimelockController(payable(timelock()));

        bytes32 beaconId = LibUnderlyingNamingRollout.beaconOperationId(timelock(), block.chainid);
        if (!controller.isOperation(beaconId)) revert BeaconBatchNotScheduled(beaconId);
        bytes32 id = LibUnderlyingNamingRollout.renameOperationId(timelock(), block.chainid);
        (, bytes32 pinned) = LibUnderlyingNamingRollout.pinnedOperationIds(block.chainid);
        if (id != pinned) revert UnderlyingNamingBatchMoved(pinned, id);
        if (controller.isOperation(id)) revert RenameAlreadyScheduled(id);

        TokenInstance[] memory chainTokens = LibUnderlyingNamingRollout.tokens(block.chainid);
        LibUnderlyingNamingRollout.assertTickersBound(block.chainid);
        // `setUnderlying` checks the vault owner, so a vault the timelock
        // does not own would revert the whole batch at execution.
        LibTokenInvariants.assertUniformOwnership(chainTokens, timelock());
    }

    /// @notice Whether this dispatch reschedules a cancelled rename batch:
    /// this migration's record already heads the line. The pre-flight still
    /// requires the batch not to be registered.
    /// @return True when the bundle must schedule without a second record.
    function rescheduling() internal view returns (bool) {
        return LibStoxMigrations.head() == LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME;
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The schedule, then the record. When rescheduling a cancelled
    /// batch the record already heads the line, so the bundle is the schedule
    /// alone.
    function authorBundle() internal view override returns (SafeTx[] memory) {
        bool reschedule = rescheduling();
        SafeTx[] memory txs = new SafeTx[](reschedule ? 1 : 2);
        txs[0] = SafeTx({
            to: timelock(),
            value: 0,
            data: LibUnderlyingNamingRollout.scheduleRenameCalldata(timelock(), block.chainid),
            operation: Enum.Operation.Call
        });
        if (!reschedule) txs[1] = LibStoxMigrations.recordTx(scheduleUnderlyingNamingRenameDeclaration());
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Scheduled, pending and not ready inside the delay; this migration's record heads the root line, written by
    /// this bundle or, on a reschedule, before it.
    function assertPostState() internal view override {
        TimelockController controller = TimelockController(payable(timelock()));
        bytes32 id = LibUnderlyingNamingRollout.renameOperationId(timelock(), block.chainid);
        if (!controller.isOperationPending(id) || controller.isOperationReady(id)) {
            revert RenameNotPendingInsideDelay(id);
        }
        // A first schedule writes the record in this bundle; a reschedule
        // finds it already on the line.
        if (LibStoxMigrations.applied(LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME) == 0) {
            // forge-lint: disable-next-line(block-timestamp)
            revert RecordMismatch(LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME, block.timestamp, 0);
        }
        bytes32 lineHead = LibStoxMigrations.head();
        if (lineHead != scheduleUnderlyingNamingRenameDeclaration().id) revert LineHeadMismatch(lineHead);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev On a snapshot: after the delay, executes the beacon batch if it
    /// has not run, then the rename batch, as an address with no role, and
    /// checks every token's metadata.
    function assertReversible() internal override {
        uint256 postBundle = vm.snapshotState();
        proveExecution();
        vm.revertToState(postBundle);
    }

    /// @notice The execution proof `assertReversible` runs.
    function proveExecution() internal {
        TokenInstance[] memory skipped = skippedRows(block.chainid);
        string[] memory before = skippedMetadata(skipped);
        TimelockController controller = TimelockController(payable(timelock()));
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);

        bytes32 beaconId = LibUnderlyingNamingRollout.beaconOperationId(timelock(), block.chainid);
        if (!controller.isOperationDone(beaconId)) {
            (address[] memory beaconTargets, uint256[] memory beaconValues, bytes[] memory beaconPayloads) =
                LibUnderlyingNamingRollout.beaconBatch(block.chainid);
            vm.prank(address(0xdead));
            controller.executeBatch(
                beaconTargets, beaconValues, beaconPayloads, bytes32(0), LibUnderlyingNamingRollout.BEACON_SALT
            );
        }

        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            LibUnderlyingNamingRollout.renameBatch(block.chainid);
        vm.prank(address(0xdead));
        controller.executeBatch(targets, values, payloads, beaconId, LibUnderlyingNamingRollout.RENAME_SALT);

        assertRenamed(block.chainid);
        string[] memory afterRun = skippedMetadata(skipped);
        for (uint256 i = 0; i < before.length; i++) {
            if (keccak256(bytes(before[i])) != keccak256(bytes(afterRun[i]))) {
                TokenInstance memory token = skipped[i / 4];
                revert SkippedRowMetadataMoved(
                    i % 4 < 2 ? token.receiptVault : token.wrappedTokenVault, before[i], afterRun[i]
                );
            }
        }
        console2.log("Execution proven: every production vault and wrapper renamed by a roleless executor");
    }

    /// @notice The chain's table rows after the leading `TOKEN_COUNT`, which the rename does not touch.
    /// @param chainId The chain id.
    /// @return The rows.
    function skippedRows(uint256 chainId) internal pure returns (TokenInstance[] memory) {
        TokenInstance[] memory table = LibTokenInvariants.productionTokensForChainId(chainId);
        uint256 count = LibUnderlyingNamingRollout.TOKEN_COUNT;
        TokenInstance[] memory rows = new TokenInstance[](table.length > count ? table.length - count : 0);
        for (uint256 i = 0; i < rows.length; i++) {
            rows[i] = table[count + i];
        }
        return rows;
    }

    /// @notice Each row's vault name and symbol, then wrapper name and symbol.
    /// @param rows The rows.
    /// @return The values read.
    function skippedMetadata(TokenInstance[] memory rows) internal view returns (string[] memory) {
        string[] memory values = new string[](rows.length * 4);
        for (uint256 i = 0; i < rows.length; i++) {
            values[i * 4] = IERC20Metadata(rows[i].receiptVault).name();
            values[i * 4 + 1] = IERC20Metadata(rows[i].receiptVault).symbol();
            values[i * 4 + 2] = IERC20Metadata(rows[i].wrappedTokenVault).name();
            values[i * 4 + 3] = IERC20Metadata(rows[i].wrappedTokenVault).symbol();
        }
        return values;
    }

    /// @notice Reverts unless every production token of `chainId` reports the
    /// metadata the rename sets.
    /// @param chainId The chain id.
    function assertRenamed(uint256 chainId) internal view {
        TokenInstance[] memory chainTokens = LibUnderlyingNamingRollout.tokens(chainId);
        for (uint256 tokenIndex = 0; tokenIndex < chainTokens.length; tokenIndex++) {
            TokenInstance memory token = chainTokens[tokenIndex];
            TokenConfig memory config = LibProdTokenConfig.configOf(token.underlying);
            string memory vaultName = string.concat(config.underlyingName, ST0X_NAME_SUFFIX);
            assertMetadata(
                token.receiptVault, string.concat("t", token.underlying), IERC20Metadata(token.receiptVault).symbol()
            );
            assertMetadata(token.receiptVault, vaultName, IERC20Metadata(token.receiptVault).name());
            assertMetadata(
                token.wrappedTokenVault,
                string.concat(token.underlying, "s"),
                IERC20Metadata(token.wrappedTokenVault).symbol()
            );
            assertMetadata(token.wrappedTokenVault, vaultName, IERC20Metadata(token.wrappedTokenVault).name());
        }
    }

    /// @notice Reverts unless `actual` equals `expected`.
    /// @param token The token read.
    /// @param expected The expected value.
    /// @param actual The value read.
    function assertMetadata(address token, string memory expected, string memory actual) internal pure {
        if (keccak256(bytes(expected)) != keccak256(bytes(actual))) {
            revert RenamedMetadataMismatch(token, expected, actual);
        }
    }
}

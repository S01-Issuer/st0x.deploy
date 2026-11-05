// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.30/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibUnderlyingNamingRollout} from "../../src/lib/LibUnderlyingNamingRollout.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {executeUnderlyingNamingDeclaration} from "../20261021-execute-underlying-naming.s.sol";

/// @notice The rename batch has not executed, so there is nothing to record.
/// @param renameId The rename batch's operation id.
error UnderlyingNamingNotExecuted(bytes32 renameId);

/// @notice The root line already holds this script's record.
/// @param id The migration id.
error ExecuteUnderlyingNamingRecorded(bytes32 id);

/// @notice The root line is not at the record this migration is applied onto.
/// @param head The line's head.
error ExecuteUnderlyingNamingUnexpectedMigrationLine(bytes32 head);

/// @notice After the bundle this migration's record is not stamped at the
/// fork's block.
/// @param expected The fork's block timestamp.
/// @param actual The recorded moment.
error ExecuteUnderlyingNamingRecordMismatch(uint256 expected, uint256 actual);

/// @title RecordExecuteUnderlyingNaming
/// @notice The record-only Safe bundle that writes `ExecuteUnderlyingNaming`'s
/// record on the root line once the rename batch has executed, outside any
/// timelock batch.
contract RecordExecuteUnderlyingNaming is SafeBundleScript {
    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x migration record: execute-underlying-naming";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261021-execute-underlying-naming-record-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @inheritdoc SafeBundleScript
    function preflight() internal view override {
        LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        bytes32 renameId = LibUnderlyingNamingRollout.renameOperationId(timelock, block.chainid);
        if (!TimelockController(payable(timelock)).isOperationDone(renameId)) {
            revert UnderlyingNamingNotExecuted(renameId);
        }
        bytes32 id = LibStoxMigrations.EXECUTE_UNDERLYING_NAMING;
        if (LibStoxMigrations.applied(id) != 0) revert ExecuteUnderlyingNamingRecorded(id);
        bytes32 head = LibStoxMigrations.head();
        if (head != executeUnderlyingNamingDeclaration().onto) {
            revert ExecuteUnderlyingNamingUnexpectedMigrationLine(head);
        }
    }

    /// @inheritdoc SafeBundleScript
    function authorBundle() internal view override returns (SafeTx[] memory) {
        (address registry, bytes memory data) = LibStoxMigrations.recordCall(executeUnderlyingNamingDeclaration());
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = SafeTx({to: registry, value: 0, data: data, operation: Enum.Operation.Call});
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    function assertPostState() internal view override {
        uint256 record = LibStoxMigrations.applied(LibStoxMigrations.EXECUTE_UNDERLYING_NAMING);
        // forge-lint: disable-next-line(block-timestamp)
        if (record != block.timestamp) {
            // forge-lint: disable-next-line(block-timestamp)
            revert ExecuteUnderlyingNamingRecordMismatch(block.timestamp, record);
        }
        require(
            LibStoxMigrations.head() == LibStoxMigrations.EXECUTE_UNDERLYING_NAMING,
            "RecordExecuteUnderlyingNaming: record not at head"
        );
    }
}

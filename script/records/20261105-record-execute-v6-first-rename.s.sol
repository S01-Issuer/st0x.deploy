// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.30/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibV6FirstRename} from "../../src/lib/LibV6FirstRename.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {executeV6FirstRenameDeclaration} from "../20261105-execute-v6-first-rename.s.sol";

/// @notice The batch has not executed, so there is nothing to record.
/// @param id The operation id.
error V6FirstRenameNotExecuted(bytes32 id);

/// @notice The root line already holds the execution's record.
/// @param id The migration id.
error ExecuteV6FirstRenameRecorded(bytes32 id);

/// @notice The root line is not at the record the execution is applied onto.
/// @param head The line's head.
error ExecuteV6FirstRenameUnexpectedMigrationLine(bytes32 head);

/// @notice After the bundle the execution's record is not stamped at the
/// fork's block, or does not head the line.
/// @param expected The fork's block timestamp.
/// @param actual The recorded moment.
error ExecuteV6FirstRenameRecordMismatch(uint256 expected, uint256 actual);

/// @title RecordExecuteV6FirstRename
/// @notice The record-only Safe bundle that writes `ExecuteV6FirstRename`'s
/// record on the root line once the V6 first-rename batch has executed. It
/// lives under `script/records/` because it writes another script's record,
/// and `BuildMigrations` reads only `script/*.s.sol`.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = records/20261105-record-execute-v6-first-rename` per chain.
contract RecordExecuteV6FirstRename is SafeBundleScript {
    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x migration record: execute-v6-first-rename";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261105-execute-v6-first-rename-record-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @inheritdoc SafeBundleScript
    function preflight() internal view override {
        LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        bytes32 id = LibV6FirstRename.operationId(LibV6FirstRename.rows());
        if (!TimelockController(payable(LibV6FirstRename.timelock())).isOperationDone(id)) {
            revert V6FirstRenameNotExecuted(id);
        }
        bytes32 migration = LibStoxMigrations.EXECUTE_V6_FIRST_RENAME;
        if (LibStoxMigrations.applied(migration) != 0) revert ExecuteV6FirstRenameRecorded(migration);
        bytes32 head = LibStoxMigrations.head();
        if (head != executeV6FirstRenameDeclaration().onto) {
            revert ExecuteV6FirstRenameUnexpectedMigrationLine(head);
        }
    }

    /// @inheritdoc SafeBundleScript
    function authorBundle() internal view override returns (SafeTx[] memory) {
        (address registry, bytes memory data) = LibStoxMigrations.recordCall(executeV6FirstRenameDeclaration());
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = SafeTx({to: registry, value: 0, data: data, operation: Enum.Operation.Call});
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    function assertPostState() internal view override {
        uint256 record = LibStoxMigrations.applied(LibStoxMigrations.EXECUTE_V6_FIRST_RENAME);
        // forge-lint: disable-next-line(block-timestamp)
        if (record != block.timestamp || LibStoxMigrations.head() != LibStoxMigrations.EXECUTE_V6_FIRST_RENAME) {
            // forge-lint: disable-next-line(block-timestamp)
            revert ExecuteV6FirstRenameRecordMismatch(block.timestamp, record);
        }
    }
}

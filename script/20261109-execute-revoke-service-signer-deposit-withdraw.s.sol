// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {SafeBundleScript} from "rain-deploy-0.1.30/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibServiceSignerRevoke} from "../src/lib/LibServiceSignerRevoke.sol";

/// @notice The broadcasting key holds `EXECUTOR_ROLE`, so an execution would
/// prove nothing about permissionless execution.
/// @param timelock The timelock.
/// @param executor The broadcasting key.
error RevokeExecutorHoldsRole(address timelock, address executor);

/// @notice The revoke batch is not ready on this chain.
/// @param id The operation id.
/// @param pending Whether the operation is pending.
/// @param done Whether the operation has executed.
error RevokeOperationNotReady(bytes32 id, bool pending, bool done);

/// @notice The executed operation is not done afterwards.
/// @param id The operation id.
error RevokeOperationNotDone(bytes32 id);

/// @notice The revoke batch has not executed, so there is nothing to record.
/// @param id The operation id.
error RevokeNotExecuted(bytes32 id);

/// @notice The root line already holds this script's record.
/// @param id The migration id.
error ExecuteRevokeServiceSignerRecorded(bytes32 id);

/// @notice This script's declaration on the root line: after the revoke schedule.
/// @return The declaration.
function executeRevokeServiceSignerDeclaration() pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.EXECUTE_REVOKE_SERVICE_SIGNER,
        onto: LibStoxMigrations.SCHEDULE_REVOKE_SERVICE_SIGNER,
        history: false
    });
}

/// @title ExecuteRevokeServiceSignerDepositWithdraw
/// @notice `execute()` executes the revoke batch on the active chain from the
/// CI deploy key, which holds no role. The batch is reconstructed by
/// `LibServiceSignerRevoke`, the same library the scheduling script uses.
///
/// `run()` authors the record-only Safe bundle that writes this script's
/// record on the root line once the batch has executed.
///
/// @dev Dispatch `execute()` via `Actions → manual-broadcast` with
/// `script = 20261109-execute-revoke-service-signer-deposit-withdraw`,
/// `sig = execute()` per chain, and `run()` via `Actions → run-script` with
/// the same `script`.
contract ExecuteRevokeServiceSignerDepositWithdraw is SafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration(uint256) external pure returns (ScriptDeclaration memory) {
        return executeRevokeServiceSignerDeclaration();
    }

    /// @notice Execute the revoke batch.
    function execute() external {
        address safeAddress = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock, safeAddress);
        if (IAccessControl(timelock).hasRole(LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE, msg.sender)) {
            revert RevokeExecutorHoldsRole(timelock, msg.sender);
        }

        TimelockController controller = TimelockController(payable(timelock));
        bytes32 id = LibServiceSignerRevoke.operationId(timelock, block.chainid);
        if (!controller.isOperationReady(id)) {
            revert RevokeOperationNotReady(id, controller.isOperationPending(id), controller.isOperationDone(id));
        }

        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            LibServiceSignerRevoke.batch(block.chainid);
        console2.log("Executing the revoke batch:", vm.toString(id));
        vm.startBroadcast();
        controller.executeBatch(targets, values, payloads, bytes32(0), LibServiceSignerRevoke.SALT);
        vm.stopBroadcast();
        if (!controller.isOperationDone(id)) revert RevokeOperationNotDone(id);
        LibServiceSignerRevoke.assertRevoked(LibAuthoriserInvariants.authoriserForChainId(block.chainid));
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x migration record: execute-revoke-service-signer-deposit-withdraw";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat(
            "out/20261109-execute-revoke-service-signer-deposit-withdraw-record-", vm.toString(block.chainid), ".json"
        );
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @inheritdoc SafeBundleScript
    function preflight() internal view override {
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        bytes32 revokeId = LibServiceSignerRevoke.operationId(timelock, block.chainid);
        if (!TimelockController(payable(timelock)).isOperationDone(revokeId)) revert RevokeNotExecuted(revokeId);
        LibServiceSignerRevoke.assertRevoked(LibAuthoriserInvariants.authoriserForChainId(block.chainid));
        bytes32 id = LibStoxMigrations.EXECUTE_REVOKE_SERVICE_SIGNER;
        if (LibStoxMigrations.applied(id) != 0) revert ExecuteRevokeServiceSignerRecorded(id);
        LibStoxMigrations.assertNext(executeRevokeServiceSignerDeclaration(), chainSafe);
    }

    /// @inheritdoc SafeBundleScript
    function authorBundle() internal view override returns (SafeTx[] memory) {
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = LibStoxMigrations.recordTx(executeRevokeServiceSignerDeclaration());
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    function assertPostState() internal view override {
        LibStoxMigrations.assertRecorded(executeRevokeServiceSignerDeclaration());
    }
}

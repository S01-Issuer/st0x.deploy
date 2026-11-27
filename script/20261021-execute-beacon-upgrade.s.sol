// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {SafeBundleScript} from "rain-deploy-0.1.38/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.38/src/lib/LibSafeTx.sol";

import {StoxSafeBundleScript} from "../src/abstract/StoxSafeBundleScript.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {LibBeaconUpgrade} from "../src/lib/LibBeaconUpgrade.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";

/// @notice The broadcasting key holds `EXECUTOR_ROLE`, so an execution would
/// prove nothing about permissionless execution.
/// @param timelock The timelock.
/// @param executor The broadcasting key.
error BeaconUpgradeExecutorHoldsRole(address timelock, address executor);

/// @notice The beacon batch is not ready on this chain.
/// @param id The operation id.
/// @param pending Whether the operation is pending.
/// @param done Whether the operation has executed.
error BeaconUpgradeNotReady(bytes32 id, bool pending, bool done);

/// @notice The executed operation is not done afterwards.
/// @param id The operation id.
error BeaconUpgradeNotDone(bytes32 id);

/// @notice The beacon batch has not executed, so there is nothing to record.
/// @param id The operation id.
error BeaconUpgradeNotExecuted(bytes32 id);

/// @notice The root line already holds this script's record.
/// @param id The migration id.
error ExecuteBeaconUpgradeRecorded(bytes32 id);

/// @notice This script's declaration on the root line: after the beacon batch's record.
/// @return The declaration.
function executeBeaconUpgradeDeclaration() pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.EXECUTE_BEACON_UPGRADE,
        onto: LibStoxMigrations.SCHEDULE_BEACON_UPGRADE,
        history: false
    });
}

/// @title ExecuteBeaconUpgrade
/// @notice `execute()` executes the beacon upgrade batch on the
/// active chain from the CI deploy key, which holds no role. The batch is
/// reconstructed by `LibBeaconUpgrade`, the same library the
/// scheduling script uses, and its last call writes its root-line record.
///
/// `run()` authors the record-only Safe bundle that writes this script's
/// record on the root line once the batch has executed.
///
/// @dev Dispatch `execute()` via `Actions → manual-broadcast` with
/// `script = 20261021-execute-beacon-upgrade`, `sig = execute()`
/// per chain, and `run()` via `Actions → run-script` with the same `script`.
contract ExecuteBeaconUpgrade is StoxSafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration(uint256) external pure returns (ScriptDeclaration memory) {
        return executeBeaconUpgradeDeclaration();
    }

    /// @notice Execute the beacon batch.
    function execute() external {
        address safeAddress = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock, safeAddress);
        if (IAccessControl(timelock).hasRole(LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE, msg.sender)) {
            revert BeaconUpgradeExecutorHoldsRole(timelock, msg.sender);
        }

        TimelockController controller = TimelockController(payable(timelock));
        bytes32 id = LibBeaconUpgrade.beaconOperationId(timelock, block.chainid);
        if (!controller.isOperationReady(id)) {
            revert BeaconUpgradeNotReady(id, controller.isOperationPending(id), controller.isOperationDone(id));
        }

        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            LibBeaconUpgrade.beaconBatch(block.chainid);
        console2.log("Executing the beacon batch:", vm.toString(id));
        vm.startBroadcast();
        controller.executeBatch(targets, values, payloads, bytes32(0), LibBeaconUpgrade.BEACON_SALT);
        vm.stopBroadcast();
        if (!controller.isOperationDone(id)) revert BeaconUpgradeNotDone(id);
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x migration record: execute-beacon-upgrade";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat(
            "out/20261021-execute-beacon-upgrade-record-", vm.toString(block.chainid), ".json"
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
        bytes32 beaconId = LibBeaconUpgrade.beaconOperationId(timelock, block.chainid);
        if (!TimelockController(payable(timelock)).isOperationDone(beaconId)) {
            revert BeaconUpgradeNotExecuted(beaconId);
        }
        bytes32 id = LibStoxMigrations.EXECUTE_BEACON_UPGRADE;
        if (LibStoxMigrations.applied(id) != 0) revert ExecuteBeaconUpgradeRecorded(id);
        LibStoxMigrations.assertNext(executeBeaconUpgradeDeclaration(), chainSafe);
    }

    /// @inheritdoc SafeBundleScript
    function authorBundle() internal view override returns (SafeTx[] memory) {
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = LibStoxMigrations.recordTx(executeBeaconUpgradeDeclaration());
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    function assertPostState() internal view override {
        LibStoxMigrations.assertRecorded(executeBeaconUpgradeDeclaration());
    }
}

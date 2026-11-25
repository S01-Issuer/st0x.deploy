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
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibOrchestratorInvariants} from "../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {LibZerogOrchestratorRoles} from "../src/lib/LibZerogOrchestratorRoles.sol";

/// @notice `execute()` runs only on 0G: no other chain schedules the batch.
/// @param chainId The active chain id.
error ZerogOrchestratorRolesExecuteOffZerog(uint256 chainId);

/// @notice The broadcasting key holds `EXECUTOR_ROLE`, so an execution would prove nothing about permissionless
/// execution.
/// @param timelock The timelock.
/// @param executor The broadcasting key.
error ZerogOrchestratorRolesExecutorHoldsRole(address timelock, address executor);

/// @notice The batch is not ready.
/// @param id The operation id.
/// @param pending Whether the operation is pending.
/// @param done Whether the operation has executed.
error ZerogOrchestratorRolesNotReady(bytes32 id, bool pending, bool done);

/// @notice The executed operation is not done afterwards.
/// @param id The operation id.
error ZerogOrchestratorRolesNotDone(bytes32 id);

/// @notice The batch has not executed, so there is nothing to record.
/// @param id The operation id.
error ZerogOrchestratorRolesNotExecuted(bytes32 id);

/// @notice This script's declaration on the root line: right after the schedule.
/// @return The declaration.
function executeZerogOrchestratorRolesDeclaration() pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.EXECUTE_ZEROG_ORCHESTRATOR_ROLES,
        onto: LibStoxMigrations.SCHEDULE_ZEROG_ORCHESTRATOR_ROLES,
        history: false
    });
}

/// @title ExecuteZerogOrchestratorRoles
/// @notice `execute()` executes the 0G orchestrator roles batch from the CI deploy key, which holds no role. The
/// batch is rebuilt by `LibZerogOrchestratorRoles`, the library the schedule script uses.
///
/// `run()` authors the record-only Safe bundle that writes this script's record on the root line: on 0G once the
/// batch has executed and every grant is held; elsewhere at once.
///
/// @dev Dispatch `execute()` via `Actions → manual-broadcast` with
/// `script = 20261123-execute-zerog-orchestrator-roles`, `sig = execute()`, `network = zerog`, and `run()` via
/// `Actions → run-script` with the same `script` per chain.
contract ExecuteZerogOrchestratorRoles is StoxSafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration(uint256) external pure returns (ScriptDeclaration memory) {
        return executeZerogOrchestratorRolesDeclaration();
    }

    /// @notice Execute the batch on 0G.
    function execute() external {
        if (block.chainid != LibSafeInvariants.ZEROG_CHAIN_ID) {
            revert ZerogOrchestratorRolesExecuteOffZerog(block.chainid);
        }
        address safeAddress = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address chainTimelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        LibTimelockInvariants.assertTimelockState(chainTimelock, safeAddress);
        if (IAccessControl(chainTimelock).hasRole(LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE, msg.sender)) {
            revert ZerogOrchestratorRolesExecutorHoldsRole(chainTimelock, msg.sender);
        }

        TimelockController controller = TimelockController(payable(chainTimelock));
        bytes32 id = LibZerogOrchestratorRoles.operationId(chainTimelock);
        if (!controller.isOperationReady(id)) {
            revert ZerogOrchestratorRolesNotReady(id, controller.isOperationPending(id), controller.isOperationDone(id));
        }

        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = LibZerogOrchestratorRoles.batch();
        console2.log("Executing the 0G orchestrator roles batch:", vm.toString(id));
        vm.startBroadcast();
        controller.executeBatch(targets, values, payloads, bytes32(0), LibZerogOrchestratorRoles.SALT);
        vm.stopBroadcast();
        if (!controller.isOperationDone(id)) revert ZerogOrchestratorRolesNotDone(id);
        LibZerogOrchestratorRoles.assertGranted();
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x migration record: execute-zerog-orchestrator-roles";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return
            string.concat("out/20261123-execute-zerog-orchestrator-roles-record-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @inheritdoc SafeBundleScript
    /// @dev On 0G the batch has executed, and the orchestrator and the US authoriser hold every pair `LibIdealRoles`
    /// expects of them.
    function preflight() internal view override {
        address chainSafe = address(safe());
        LibStoxMigrations.assertNext(executeZerogOrchestratorRolesDeclaration(), chainSafe);
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
        if (block.chainid != LibSafeInvariants.ZEROG_CHAIN_ID) return;

        address chainTimelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        bytes32 id = LibZerogOrchestratorRoles.operationId(chainTimelock);
        if (!TimelockController(payable(chainTimelock)).isOperationDone(id)) {
            revert ZerogOrchestratorRolesNotExecuted(id);
        }
        LibZerogOrchestratorRoles.assertGranted();
        LibAuthoriserInvariants.assertExpectedGrants(
            LibAuthoriserInvariants.activeChainAuthoriser(), chainSafe, chainTimelock
        );
        LibOrchestratorInvariants.assertExpectedGrants(chainSafe, chainTimelock);
    }

    /// @inheritdoc SafeBundleScript
    function authorBundle() internal view override returns (SafeTx[] memory) {
        return LibStoxMigrations.recordOnlyBundle(executeZerogOrchestratorRolesDeclaration());
    }

    /// @inheritdoc SafeBundleScript
    function assertPostState() internal view override {
        LibStoxMigrations.assertRecorded(executeZerogOrchestratorRolesDeclaration());
    }
}

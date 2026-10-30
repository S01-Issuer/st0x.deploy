// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";

import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {
    TIMELOCK_BACKFILL_V5_SALT,
    timelockBackfillV5Batch,
    assertTimelockBackfillV5PostState
} from "./20261030-backfill-migration-registry-v5-timelock-schedule.s.sol";

/// @notice The scheduled backfill operation is not executable.
/// @param id The operation id.
/// @param pending Whether it is pending.
/// @param ready Whether it is ready.
/// @param done Whether it is done.
error TimelockBackfillV5NotExecutable(bytes32 id, bool pending, bool ready, bool done);

/// @notice The executing key holds a timelock role.
/// @param executor The key.
error TimelockBackfillV5ExecutorHoldsRole(address executor);

/// @title BackfillMigrationRegistryV5TimelockExecute
/// @notice Executes the matured batch
/// `20261030-backfill-migration-registry-v5-timelock-schedule` scheduled,
/// from the CI deploy key, then asserts every timelock V3 record is on V5.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20261030-backfill-migration-registry-v5-timelock-execute` per
/// chain. The batch is recomputed from chain state, which only its own
/// execution changes, so it hashes to the scheduled operation.
contract BackfillMigrationRegistryV5TimelockExecute is Script, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.notAMigration();
    }

    /// @notice Execute the matured backfill on the active chain.
    function run() external {
        address safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock, safe);

        address executor = msg.sender;
        if (IAccessControl(timelock).hasRole(LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE, executor)) {
            revert TimelockBackfillV5ExecutorHoldsRole(executor);
        }

        (address[] memory targets, bytes[] memory payloads) = timelockBackfillV5Batch(safe, timelock);
        uint256[] memory values = new uint256[](targets.length);
        TimelockController controller = TimelockController(payable(timelock));
        bytes32 id = controller.hashOperationBatch(targets, values, payloads, bytes32(0), TIMELOCK_BACKFILL_V5_SALT);
        bool ready = controller.isOperationReady(id);
        if (!ready) {
            revert TimelockBackfillV5NotExecutable(
                id, controller.isOperationPending(id), ready, controller.isOperationDone(id)
            );
        }

        console2.log("Executing matured operation:", vm.toString(id));
        console2.log("Chain:", block.chainid);

        vm.startBroadcast();
        controller.executeBatch(targets, values, payloads, bytes32(0), TIMELOCK_BACKFILL_V5_SALT);
        vm.stopBroadcast();

        require(controller.isOperationDone(id), "BackfillV5TimelockExecute: operation did not complete");
        assertTimelockBackfillV5PostState(timelock);
    }
}

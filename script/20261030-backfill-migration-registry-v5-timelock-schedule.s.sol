// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {IMigrationRegistryV3} from "rain-deploy-0.1.29/src/interface/deprecated/IMigrationRegistryV3.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.29/src/interface/deprecated/IMigrationRegistryV3.sol";
import {DEPLOYED_ADDRESS as REGISTRY_V3} from "rain-deploy-0.1.29/src/generated/0_1_25/MigrationRegistry.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.29/src/lib/LibMigrationRegistry.sol";
import {LibSafeTx, SafeTx} from "rain-deploy-0.1.29/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.29/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.29/src/lib/LibSafeTxBuilderJson.sol";

import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {IStoxScript, MigrationWriter, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {retireDirectSignerRolesDeclaration} from "./20260831-retire-direct-signer-roles.s.sol";

/// @dev The timelock operation's salt.
bytes32 constant TIMELOCK_BACKFILL_V5_SALT = keccak256("st0x.backfill-migration-registry-v5-timelock");

/// @notice V5 already holds every timelock record this backfill writes.
error TimelockBackfillV5NothingToSchedule();

/// @notice The backfill operation is already registered on the timelock.
/// @param id The operation id.
error TimelockBackfillV5AlreadyScheduled(bytes32 id);

/// @notice After execution, a timelock V5 record differs from its V3 record.
/// @param migration The record.
/// @param expected The V3 moment.
/// @param actual The V5 moment.
error TimelockBackfillV5RecordMismatch(bytes32 migration, uint256 expected, uint256 actual);

/// @notice After execution, V5 lacks this backfill's own timelock record.
/// @param migration The missing record.
error TimelockBackfillV5RecordMissing(bytes32 migration);

/// @notice This backfill's declaration: the timelock's first `st0x.deploy`
/// record.
/// @return The declaration.
function backfillMigrationRegistryV5TimelockDeclaration() pure returns (ScriptDeclaration memory) {
    return LibStoxMigrations.migrationOnto(
        MigrationWriter.Timelock,
        LibStoxMigrations.NAMESPACE,
        LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5_TIMELOCK,
        MIGRATION_HEAD_GENESIS,
        false
    );
}

/// @notice The timelock's lines, each in order from genesis.
/// @return The lines.
function timelockBackfillV5Lines() pure returns (ScriptDeclaration[][] memory) {
    ScriptDeclaration[][] memory all = new ScriptDeclaration[][](1);
    all[0] = new ScriptDeclaration[](1);
    all[0][0] = retireDirectSignerRolesDeclaration();
    return all;
}

/// @notice The timelock's V3 moment for `declared`.
/// @param timelock The timelock.
/// @param declared The declaration.
/// @return The moment, zero if V3 lacks it.
function timelockBackfillV5Moment(address timelock, ScriptDeclaration memory declared) view returns (uint256) {
    return IMigrationRegistryV3(REGISTRY_V3).appliedV3(timelock, declared.namespace, declared.id);
}

/// @notice Writes each timelock V3-held record V5 lacks, as history at its V3
/// moment, into `targets`/`payloads` from index 0, in line order (a record V3
/// lacks ends its line).
/// @param all The timelock's migration lines.
/// @param safe The chain's Safe.
/// @param timelock The chain's timelock.
/// @param targets The batch targets, filled in place.
/// @param payloads The batch payloads, filled in place.
/// @return The number of entries written.
function timelockBackfillV5FillHistory(
    ScriptDeclaration[][] memory all,
    address safe,
    address timelock,
    address[] memory targets,
    bytes[] memory payloads
) view returns (uint256) {
    uint256 k = 0;
    for (uint256 i = 0; i < all.length; i++) {
        for (uint256 j = 0; j < all[i].length; j++) {
            ScriptDeclaration memory declared = all[i][j];
            uint256 at = timelockBackfillV5Moment(timelock, declared);
            if (at == 0) break;
            if (LibMigrationRegistry.appliedV5(timelock, declared.namespace, declared.id) != 0) continue;
            (targets[k], payloads[k]) = LibStoxMigrations.historyCall(declared, at, safe, timelock);
            k++;
        }
    }
    return k;
}

/// @notice The batch the timelock executes: each timelock V3-held record V5
/// lacks, as history at its V3 moment, in line order (a record V3 lacks ends
/// its line), then this backfill's own record if V5 lacks it. Empty when V5
/// holds all of them.
/// @param safe The chain's Safe.
/// @param timelock The chain's timelock.
/// @return The targets.
/// @return The payloads.
function timelockBackfillV5Batch(address safe, address timelock)
    view
    returns (address[] memory, bytes[] memory)
{
    ScriptDeclaration[][] memory all = timelockBackfillV5Lines();
    ScriptDeclaration memory own = backfillMigrationRegistryV5TimelockDeclaration();
    uint256 count = 0;
    for (uint256 i = 0; i < all.length; i++) {
        for (uint256 j = 0; j < all[i].length; j++) {
            if (timelockBackfillV5Moment(timelock, all[i][j]) == 0) break;
            if (LibMigrationRegistry.appliedV5(timelock, all[i][j].namespace, all[i][j].id) != 0) continue;
            count++;
        }
    }
    bool recordOwn = LibStoxMigrations.applied(timelock, own.id) == 0;
    if (count == 0 && !recordOwn) return (new address[](0), new bytes[](0));
    if (recordOwn) count++;
    address[] memory targets = new address[](count);
    bytes[] memory payloads = new bytes[](count);
    uint256 k = timelockBackfillV5FillHistory(all, safe, timelock, targets, payloads);
    if (recordOwn) (targets[k], payloads[k]) = LibStoxMigrations.recordCall(own, safe, timelock);
    return (targets, payloads);
}

/// @notice Every timelock V3-held record has its V3 moment on V5, and V5
/// holds this backfill's own record.
/// @param timelock The chain's timelock.
function assertTimelockBackfillV5PostState(address timelock) view {
    ScriptDeclaration[][] memory all = timelockBackfillV5Lines();
    for (uint256 i = 0; i < all.length; i++) {
        for (uint256 j = 0; j < all[i].length; j++) {
            ScriptDeclaration memory declared = all[i][j];
            uint256 expected = timelockBackfillV5Moment(timelock, declared);
            if (expected == 0) break;
            uint256 actual = LibMigrationRegistry.appliedV5(timelock, declared.namespace, declared.id);
            if (actual != expected) revert TimelockBackfillV5RecordMismatch(declared.id, expected, actual);
        }
    }
    ScriptDeclaration memory own = backfillMigrationRegistryV5TimelockDeclaration();
    if (LibStoxMigrations.applied(timelock, own.id) == 0) revert TimelockBackfillV5RecordMissing(own.id);
}

/// @title BackfillMigrationRegistryV5TimelockSchedule
/// @notice Authors the per-chain Safe bundle that schedules, on the
/// governance timelock, the batch replaying the timelock's V3
/// `MigrationRegistry` records onto V5 (`timelockBackfillV5Batch`). Execute
/// it after the delay with `20261030-backfill-migration-registry-v5-timelock-execute`.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20261030-backfill-migration-registry-v5-timelock-schedule` per
/// chain. Refuses when V5 already holds every record or the operation is
/// registered. Proves the loop on the fork: schedule, warp the delay,
/// execute as a roleless address, post-state.
contract BackfillMigrationRegistryV5TimelockSchedule is Script, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return backfillMigrationRegistryV5TimelockDeclaration();
    }

    /// @notice Author the schedule bundle for the active chain.
    function run() external {
        Safe safe = Safe(payable(LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid)));
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock, address(safe));

        (address[] memory targets, bytes[] memory payloads) = timelockBackfillV5Batch(address(safe), timelock);
        if (targets.length == 0) revert TimelockBackfillV5NothingToSchedule();
        uint256[] memory values = new uint256[](targets.length);

        TimelockController controller = TimelockController(payable(timelock));
        bytes32 id = controller.hashOperationBatch(targets, values, payloads, bytes32(0), TIMELOCK_BACKFILL_V5_SALT);
        if (controller.isOperation(id)) revert TimelockBackfillV5AlreadyScheduled(id);

        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = SafeTx({
            to: timelock,
            value: 0,
            data: abi.encodeCall(
                TimelockController.scheduleBatch,
                (targets, values, payloads, bytes32(0), TIMELOCK_BACKFILL_V5_SALT, LibTimelockInvariants.TIMELOCK_MIN_DELAY)
            ),
            operation: Enum.Operation.Call
        });

        uint256 nonce = safe.nonce();
        bytes32 safeTxHash = LibSafeTx.safeTxHash(safe, txs[0], nonce);

        LibSafeFork.simulateCall(vm, safe, txs[0].to, txs[0].data);
        require(controller.isOperationPending(id), "BackfillV5TimelockSchedule: operation not registered");
        require(!controller.isOperationReady(id), "BackfillV5TimelockSchedule: ready before the delay elapsed");

        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        vm.prank(address(uint160(uint256(keccak256("st0x.backfill-v5.roleless-executor")))));
        controller.executeBatch(targets, values, payloads, bytes32(0), TIMELOCK_BACKFILL_V5_SALT);
        require(controller.isOperationDone(id), "BackfillV5TimelockSchedule: execution did not complete");
        assertTimelockBackfillV5PostState(timelock);

        string memory artifactPath = string.concat(
            "out/20261030-backfill-migration-registry-v5-timelock-schedule-", vm.toString(block.chainid), ".json"
        );
        string memory json = LibSafeTxBuilderJson.toJson(
            vm, address(safe), block.chainid, "ST0x: schedule timelock MigrationRegistry V5 backfill", txs
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
    }
}

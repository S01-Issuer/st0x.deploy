// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.38/src/abstract/SafeBundleScript.sol";
import {LibSafeFork} from "rain-deploy-0.1.38/src/lib/LibSafeFork.sol";
import {LibSafeTx, SafeTx} from "rain-deploy-0.1.38/src/lib/LibSafeTx.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.38/src/lib/LibSafeTxBuilderJson.sol";

import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibOrchestratorInvariants} from "../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {LibZerogOrchestratorRoles} from "../src/lib/LibZerogOrchestratorRoles.sol";

/// @notice The timelock does not hold `DEFAULT_ADMIN_ROLE` on the orchestrator, so the batch's orchestrator grants
/// would revert.
/// @param timelock The timelock.
error TimelockNotOrchestratorAdmin(address timelock);

/// @notice The batch is already registered on the timelock.
/// @param id The operation id.
error ZerogOrchestratorRolesAlreadyScheduled(bytes32 id);

/// @notice After the bundle the operation is not pending, or is ready inside its delay.
/// @param id The operation id.
error ZerogOrchestratorRolesNotPendingInsideDelay(bytes32 id);

/// @notice `reschedule` and `verifyReschedule` run only on 0G: no other chain schedules the batch.
/// @param chainId The active chain id.
error ZerogOrchestratorRolesRescheduleOffZerog(uint256 chainId);

/// @notice The root-line head is not this script's record, so the batch was not scheduled and cancelled: either the
/// schedule has not landed, and `run()` is the path, or a later migration has.
/// @param head The root-line head.
error ZerogOrchestratorRolesRescheduleNotAtTheSchedule(bytes32 head);

/// @notice This script's declaration on the root line: right after the 0G token creation on every chain.
/// @return The declaration.
function scheduleZerogOrchestratorRolesDeclaration() pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.SCHEDULE_ZEROG_ORCHESTRATOR_ROLES,
        onto: LibStoxMigrations.CREATE_ZEROG_TOKENS,
        history: false
    });
}

/// @title ScheduleZerogOrchestratorRoles
/// @notice Per-chain Safe bundle: on 0G, the Safe SCHEDULES the timelock batch `LibZerogOrchestratorRoles` builds,
/// which grants the service signer `MINT` and `BURN` and the Safe `EMERGENCY` on the orchestrator, and the
/// orchestrator `DEPOSIT` and `WITHDRAW` on the US authoriser, then writes its root-line record; elsewhere, where the
/// orchestrator already holds these roles, the record alone. The timelock holds every admin role these grants need,
/// so it is the only route.
///
/// The orchestrator's `DEFAULT_ADMIN_ROLE` is not enumerable, so the pre-flight can prove only that the timelock holds
/// it. 0G transaction 0x5d7b34d5f54c46ed036ec4959de1736f15af1b2b351f3dfc08f80bb1fcafc60c (block 50776661) deployed the
/// 0.1.30 set deployer and made its first `deploy(timelock)` in one Multicall3 call, so the timelock was the
/// instance's only initial admin and no one else could take the pinned address.
///
/// `reschedule()` is the recovery after the Safe cancels the scheduled batch. The record stays at the head, so `run()`
/// refuses; `reschedule()` authors the `scheduleBatch` call alone, as one direct Safe call, and
/// `verifyReschedule(string)` is its signer check.
///
/// @dev Dispatch via `Actions → run-script` with `script = 20261123-schedule-zerog-orchestrator-roles` per chain.
/// After the delay anyone executes the batch: `20261123-execute-zerog-orchestrator-roles` `execute()`. The recovery
/// is the same dispatch on `zerog` with `sig = reschedule()`.
contract ScheduleZerogOrchestratorRoles is SafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration(uint256) external pure returns (ScriptDeclaration memory) {
        return scheduleZerogOrchestratorRolesDeclaration();
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x RBAC: schedule the 0G orchestrator MINT, BURN, EMERGENCY, DEPOSIT and WITHDRAW grants";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261123-schedule-zerog-orchestrator-roles-", vm.toString(block.chainid), ".json");
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

    /// @notice Whether the active chain is 0G, the only chain the batch is for.
    /// @return True on 0G.
    function onZerog() internal view returns (bool) {
        return block.chainid == LibSafeInvariants.ZEROG_CHAIN_ID;
    }

    /// @notice Where `reschedule()` writes its one-call Safe Transaction Builder JSON.
    /// @return The path.
    function rescheduleArtifactPath() internal view virtual returns (string memory) {
        return string.concat("out/20261123-reschedule-zerog-orchestrator-roles-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    /// @dev On 0G: the orchestrator beacon set and instance are the audited 0.1.30 ones, the timelock administers the
    /// orchestrator and holds the US authoriser's map before these grants, none of the five grants is held and the
    /// batch is not registered.
    function preflight() internal view override {
        address chainSafe = address(safe());
        LibStoxMigrations.assertNext(scheduleZerogOrchestratorRolesDeclaration(), chainSafe);
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
        LibTimelockInvariants.assertTimelockState(timelock(), chainSafe);
        if (!onZerog()) return;
        assertZerogBeforeSchedule(chainSafe);
    }

    /// @notice The 0G state the batch is scheduled against, for `run()` and `reschedule()` alike.
    /// @param chainSafe The 0G Safe.
    function assertZerogBeforeSchedule(address chainSafe) internal view {
        LibOrchestratorInvariants.assertBeaconSet();
        LibOrchestratorInvariants.assertInstance();
        if (!IAccessControl(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE).hasRole(bytes32(0), timelock())) {
            revert TimelockNotOrchestratorAdmin(timelock());
        }
        LibAuthoriserInvariants.assertHeld(
            LibAuthoriserInvariants.activeChainAuthoriser(),
            LibAuthoriserInvariants.expectedGrantsWithoutOrchestrator(chainSafe, timelock())
        );
        LibZerogOrchestratorRoles.assertNoneGranted();

        bytes32 id = LibZerogOrchestratorRoles.operationId(timelock());
        if (TimelockController(payable(timelock())).isOperation(id)) revert ZerogOrchestratorRolesAlreadyScheduled(id);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev On 0G the schedule, then the record; elsewhere the record alone.
    function authorBundle() internal view override returns (SafeTx[] memory txs) {
        if (!onZerog()) {
            txs = new SafeTx[](1);
            txs[0] = LibStoxMigrations.recordTx(scheduleZerogOrchestratorRolesDeclaration());
            return txs;
        }
        txs = new SafeTx[](2);
        txs[0] = scheduleTx();
        txs[1] = LibStoxMigrations.recordTx(scheduleZerogOrchestratorRolesDeclaration());
    }

    /// @notice The `scheduleBatch` call on the 0G timelock: the bundle's first call, and the whole recovery.
    /// @return The call.
    function scheduleTx() internal view returns (SafeTx memory) {
        return SafeTx({
            to: timelock(), value: 0, data: LibZerogOrchestratorRoles.scheduleCalldata(), operation: Enum.Operation.Call
        });
    }

    /// @inheritdoc SafeBundleScript
    function assertPostState() internal view override {
        if (onZerog()) assertPendingInsideDelay();
        LibStoxMigrations.assertRecorded(scheduleZerogOrchestratorRolesDeclaration());
    }

    /// @notice Reverts unless the batch is pending and not yet ready.
    function assertPendingInsideDelay() internal view {
        TimelockController controller = TimelockController(payable(timelock()));
        bytes32 id = LibZerogOrchestratorRoles.operationId(timelock());
        if (!controller.isOperationPending(id) || controller.isOperationReady(id)) {
            revert ZerogOrchestratorRolesNotPendingInsideDelay(id);
        }
    }

    /// @notice Reverts unless the Safe can re-schedule a cancelled batch on 0G: the root-line head is this script's
    /// record, the batch is not registered on the timelock (OpenZeppelin's `cancel` deletes it, so neither pending
    /// nor done), none of its grants is held, and every other check `run()` makes on 0G before scheduling holds.
    function reschedulePreflight() internal view {
        if (!onZerog()) revert ZerogOrchestratorRolesRescheduleOffZerog(block.chainid);
        bytes32 lineHead = LibStoxMigrations.head();
        if (lineHead != LibStoxMigrations.SCHEDULE_ZEROG_ORCHESTRATOR_ROLES) {
            revert ZerogOrchestratorRolesRescheduleNotAtTheSchedule(lineHead);
        }
        address chainSafe = address(safe());
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
        LibTimelockInvariants.assertTimelockState(timelock(), chainSafe);
        assertZerogBeforeSchedule(chainSafe);
    }

    /// @notice The recovery after a Safe `cancel` of the batch, on 0G. Checks the state (`reschedulePreflight`),
    /// executes the `scheduleBatch` call alone through the Safe on the fork, requires the batch pending inside its
    /// delay and the line unchanged, proves the batch executes after the delay, then writes the one-call artifact and
    /// logs the call's fields and its `SafeTxHash` at the Safe's nonce before execution. The Safe UI proposes a
    /// one-call artifact as a direct call (operation 0), not a MultiSend, so that hash is the one the signers see.
    /// @return The direct call's `SafeTxHash` at the nonce before execution.
    function reschedule() external returns (bytes32) {
        string memory path = rescheduleArtifactPath();
        if (vm.exists(path)) vm.removeFile(path);
        reschedulePreflight();
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = scheduleTx();
        Safe chainSafe = safe();
        uint256 nonce = chainSafe.nonce();
        bytes32 safeTxHash = LibSafeTx.safeTxHash(chainSafe, txs[0], nonce);
        LibSafeFork.execute(vm, chainSafe, txs[0]);
        assertPendingInsideDelay();
        bytes32 lineHead = LibStoxMigrations.head();
        if (lineHead != LibStoxMigrations.SCHEDULE_ZEROG_ORCHESTRATOR_ROLES) {
            revert ZerogOrchestratorRolesRescheduleNotAtTheSchedule(lineHead);
        }
        assertReversible();
        string memory json = LibSafeTxBuilderJson.toJson(
            vm,
            address(chainSafe),
            block.chainid,
            "ST0x RBAC: re-schedule the cancelled 0G orchestrator MINT, BURN, EMERGENCY, DEPOSIT and WITHDRAW grants",
            txs
        );
        vm.writeFile(path, json);
        console2.log("==== TX BUILDER JSON BEGIN ====");
        console2.log(json);
        console2.log("==== TX BUILDER JSON END ====");
        logDirectCall(chainSafe, txs[0], nonce, safeTxHash);
        console2.log("Artifact:", path);
        return safeTxHash;
    }

    /// @notice The signer check for `reschedule()`: re-runs its pre-flight on live 0G, refuses an artifact that is not
    /// exactly the one `scheduleBatch` call, and logs the direct call's `SafeTxHash` at the live nonce.
    /// @param jsonPath The `reschedule()` artifact.
    /// @return safeTxHash The direct call's `SafeTxHash` at the live nonce.
    function verifyReschedule(string calldata jsonPath) external view returns (bytes32 safeTxHash) {
        reschedulePreflight();
        SafeTx[] memory expected = new SafeTx[](1);
        expected[0] = scheduleTx();
        Safe chainSafe = safe();
        LibSafeTxBuilderJson.requireMatches(vm, vm.readFile(jsonPath), address(chainSafe), expected);
        uint256 nonce = chainSafe.nonce();
        safeTxHash = LibSafeTx.safeTxHash(chainSafe, expected[0], nonce);
        console2.log("Artifact verified against live state.");
        logDirectCall(chainSafe, expected[0], nonce, safeTxHash);
    }

    /// @notice Logs the direct call's `execTransaction` fields and its hash.
    /// @param chainSafe The Safe.
    /// @param txn The call.
    /// @param nonce The nonce it consumes.
    /// @param safeTxHash Its hash at that nonce.
    function logDirectCall(Safe chainSafe, SafeTx memory txn, uint256 nonce, bytes32 safeTxHash) internal pure {
        console2.log("Safe:", address(chainSafe));
        console2.log("Nonce:", nonce);
        console2.log("To:", txn.to);
        console2.log("Value:", txn.value);
        console2.log("Operation: 0 (Call); safeTxGas, baseGas, gasPrice 0; gasToken, refundReceiver address(0)");
        console2.log("Data:", vm.toString(txn.data));
        console2.log("Data keccak256:", vm.toString(keccak256(txn.data)));
        console2.log("Operation id:", vm.toString(LibZerogOrchestratorRoles.operationId(txn.to)));
        console2.log("Direct-call SafeTxHash:", vm.toString(safeTxHash));
    }

    /// @inheritdoc SafeBundleScript
    function assertReversible() internal override {
        if (!onZerog()) return;
        uint256 postBundle = vm.snapshotState();
        proveExecution();
        vm.revertToState(postBundle);
    }

    /// @notice After the delay, executes the batch as an address with no role and checks that the orchestrator and
    /// the US authoriser then hold every pair `LibIdealRoles` expects of them.
    function proveExecution() internal {
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = LibZerogOrchestratorRoles.batch();
        vm.prank(address(0xdead));
        TimelockController(payable(timelock()))
            .executeBatch(targets, values, payloads, bytes32(0), LibZerogOrchestratorRoles.SALT);

        LibZerogOrchestratorRoles.assertGranted();
        LibAuthoriserInvariants.assertExpectedGrants(
            LibAuthoriserInvariants.authoriserForChainId(block.chainid), address(safe()), timelock()
        );
        LibOrchestratorInvariants.assertExpectedGrants(address(safe()), timelock());
        console2.log("Execution proven: 0G orchestrator MINT, BURN, EMERGENCY, DEPOSIT and WITHDRAW granted");
    }
}

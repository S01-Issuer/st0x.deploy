// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {LibSafeFork} from "rain-deploy-0.1.30/src/lib/LibSafeFork.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";
import {LibTimelockController} from "rain-deploy-0.1.30/src/lib/LibTimelockController.sol";

import {
    ExecuteRevokeServiceSignerDepositWithdraw,
    RevokeExecutorHoldsRole,
    RevokeNotExecuted,
    RevokeOperationNotReady
} from "../../script/20261109-execute-revoke-service-signer-deposit-withdraw.s.sol";
import {
    RevokeAlreadyScheduled,
    RevokeNotPendingInsideDelay,
    ServiceSignerLacksRole,
    TimelockLacksAdminRole
} from "../../script/20261109-schedule-revoke-service-signer-deposit-withdraw.s.sol";
import {ExecuteRevokeServiceSignerDepositWithdrawHarness} from "./ExecuteRevokeServiceSignerDepositWithdrawHarness.sol";
import {ScheduleRevokeServiceSignerDepositWithdrawHarness} from "./ScheduleRevokeServiceSignerDepositWithdrawHarness.sol";
import {RevokeServiceSignerDepositWithdrawFixture} from "./RevokeServiceSignerDepositWithdrawFixture.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";
import {AuthoriserNotReady, LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibServiceSignerRevoke, ServiceSignerStillHoldsRole} from "../../src/lib/LibServiceSignerRevoke.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @title RevokeServiceSignerDepositWithdrawRolloutTest
/// @notice The service-signer revoke on every deployment network. Per network,
/// at its pinned pre-backfill block, the schedule is authored, verified and
/// executed, the batch is executed from a roleless key after its delay, and the
/// execution record lands. The refusal tests cover each pre-flight check.
contract RevokeServiceSignerDepositWithdrawRolloutTest is RevokeServiceSignerDepositWithdrawFixture {
    function revokedRoles() internal pure returns (bytes32[2] memory) {
        return [keccak256("DEPOSIT"), keccak256("WITHDRAW")];
    }

    /// @notice The batch is exactly `revokeRole(DEPOSIT, signer)` then
    /// `revokeRole(WITHDRAW, signer)` on the chain's authoriser.
    function assertBatchExact(uint256 chainId, string memory network) internal pure {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            LibServiceSignerRevoke.batch(chainId);
        bytes32[2] memory roles = revokedRoles();
        assertEq(targets.length, roles.length, string.concat(network, ": targets"));
        assertEq(values.length, roles.length, string.concat(network, ": values"));
        assertEq(payloads.length, roles.length, string.concat(network, ": payloads"));
        for (uint256 callIndex = 0; callIndex < roles.length; callIndex++) {
            assertEq(
                targets[callIndex],
                LibAuthoriserInvariants.authoriserForChainId(chainId),
                string.concat(network, ": target")
            );
            assertEq(values[callIndex], 0, string.concat(network, ": value"));
            assertEq(
                payloads[callIndex],
                abi.encodeCall(
                    IAccessControl.revokeRole, (roles[callIndex], LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C)
                ),
                string.concat(network, ": payload")
            );
        }
    }

    /// @notice Schedules, executes and records the revoke on `network` and
    /// checks each step.
    function assertRollout(string memory network) internal {
        LibTestPreBackfillFork.select(vm, network);
        uint256 chainId = block.chainid;
        address timelock = LibTimelockInvariants.timelockForChainId(chainId);
        TimelockController controller = TimelockController(payable(timelock));
        bytes32 id = LibServiceSignerRevoke.operationId(timelock, chainId);
        ScheduleRevokeServiceSignerDepositWithdrawHarness schedule =
            new ScheduleRevokeServiceSignerDepositWithdrawHarness(network);
        ExecuteRevokeServiceSignerDepositWithdrawHarness execution =
            new ExecuteRevokeServiceSignerDepositWithdrawHarness(network);

        assertBatchExact(chainId, network);
        advanceRootLineToRevokeSchedule();
        assertTrue(serviceSignerHolds(keccak256("DEPOSIT")), string.concat(network, ": DEPOSIT before"));
        assertTrue(serviceSignerHolds(keccak256("WITHDRAW")), string.concat(network, ": WITHDRAW before"));
        vm.expectRevert(abi.encodeWithSelector(RevokeOperationNotReady.selector, id, false, false));
        execution.execute();
        vm.expectRevert(abi.encodeWithSelector(RevokeNotExecuted.selector, id));
        execution.callPreflight();

        authorVerifyExecute(address(schedule), schedule.callArtifactPath());
        assertEq(
            LibStoxMigrations.head(),
            LibStoxMigrations.SCHEDULE_REVOKE_SERVICE_SIGNER,
            string.concat(network, ": schedule record")
        );
        assertEq(
            LibStoxMigrations.applied(LibStoxMigrations.SCHEDULE_REVOKE_SERVICE_SIGNER),
            block.timestamp,
            string.concat(network, ": schedule record stamped at the block")
        );
        assertTrue(controller.isOperationPending(id), string.concat(network, ": pending"));
        assertFalse(controller.isOperationReady(id), string.concat(network, ": not ready inside the delay"));
        assertEq(
            controller.getTimestamp(id),
            block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY,
            string.concat(network, ": ready after the delay")
        );
        assertTrue(serviceSignerHolds(keccak256("DEPOSIT")), string.concat(network, ": DEPOSIT while pending"));
        assertTrue(serviceSignerHolds(keccak256("WITHDRAW")), string.concat(network, ": WITHDRAW while pending"));
        vm.expectRevert(abi.encodeWithSelector(RevokeNotExecuted.selector, id));
        execution.callPreflight();

        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY - 1);
        vm.expectRevert(abi.encodeWithSelector(RevokeOperationNotReady.selector, id, true, false));
        execution.execute();
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + 1);
        assertFalse(
            IAccessControl(timelock).hasRole(LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE, address(this)),
            string.concat(network, ": roleless executor")
        );
        execution.execute();

        assertTrue(controller.isOperationDone(id), string.concat(network, ": done"));
        assertFalse(serviceSignerHolds(keccak256("DEPOSIT")), string.concat(network, ": DEPOSIT revoked"));
        assertFalse(serviceSignerHolds(keccak256("WITHDRAW")), string.concat(network, ": WITHDRAW revoked"));
        assertTrue(serviceSignerHolds(keccak256("CERTIFY")), string.concat(network, ": CERTIFY kept"));
        LibAuthoriserInvariants.assertExpectedGrants(
            LibAuthoriserInvariants.authoriserForChainId(chainId), LibSafeInvariants.safeForChainId(chainId), timelock
        );
        vm.expectRevert(abi.encodeWithSelector(RevokeOperationNotReady.selector, id, false, true));
        execution.execute();

        authorVerifyExecute(address(execution), execution.callArtifactPath());
        assertEq(
            LibStoxMigrations.head(),
            LibStoxMigrations.EXECUTE_REVOKE_SERVICE_SIGNER,
            string.concat(network, ": line at the execution")
        );
    }

    function testRolloutOnEveryDeploymentNetwork() external {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            assertRollout(networks[i]);
        }
    }

    /// @notice Base with the line at the schedule's onto and a pre-flight that
    /// passes.
    function scheduleOnBase() internal returns (ScheduleRevokeServiceSignerDepositWithdrawHarness schedule) {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        advanceRootLineToRevokeSchedule();
        schedule = new ScheduleRevokeServiceSignerDepositWithdrawHarness("refusals");
        schedule.callPreflight();
    }

    /// @notice The schedule pre-flight refuses a service signer without either
    /// role, with the other held.
    function testSchedulePreflightRefusesASignerWithoutEachRole() external {
        ScheduleRevokeServiceSignerDepositWithdrawHarness schedule = scheduleOnBase();
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        IAccessControl authoriser = IAccessControl(LibAuthoriserInvariants.authoriserForChainId(block.chainid));
        bytes32[2] memory roles = revokedRoles();
        for (uint256 roleIndex = 0; roleIndex < roles.length; roleIndex++) {
            uint256 snapshot = vm.snapshotState();
            vm.prank(timelock);
            authoriser.revokeRole(roles[roleIndex], LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C);
            vm.expectRevert(abi.encodeWithSelector(ServiceSignerLacksRole.selector, roles[roleIndex]));
            schedule.callPreflight();
            vm.revertToState(snapshot);
        }
    }

    /// @notice The schedule pre-flight refuses a timelock without either admin
    /// role, with the other held.
    function testSchedulePreflightRefusesATimelockWithoutEachAdminRole() external {
        ScheduleRevokeServiceSignerDepositWithdrawHarness schedule = scheduleOnBase();
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        IAccessControl authoriser = IAccessControl(LibAuthoriserInvariants.authoriserForChainId(block.chainid));
        bytes32[2] memory adminRoles = [keccak256("DEPOSIT_ADMIN"), keccak256("WITHDRAW_ADMIN")];
        for (uint256 roleIndex = 0; roleIndex < adminRoles.length; roleIndex++) {
            uint256 snapshot = vm.snapshotState();
            vm.prank(timelock);
            authoriser.renounceRole(adminRoles[roleIndex], timelock);
            vm.expectRevert(abi.encodeWithSelector(TimelockLacksAdminRole.selector, timelock, adminRoles[roleIndex]));
            schedule.callPreflight();
            vm.revertToState(snapshot);
        }
    }

    /// @notice The schedule pre-flight refuses once the batch is registered.
    function testSchedulePreflightRefusesARegisteredBatch() external {
        ScheduleRevokeServiceSignerDepositWithdrawHarness schedule = scheduleOnBase();
        scheduleRevokeBatch();
        vm.expectRevert(
            abi.encodeWithSelector(
                RevokeAlreadyScheduled.selector,
                LibServiceSignerRevoke.operationId(
                    LibTimelockInvariants.timelockForChainId(block.chainid), block.chainid
                )
            )
        );
        schedule.callPreflight();
    }

    /// @notice The schedule pre-flight refuses an authoriser whose code is not
    /// the pinned clone.
    function testSchedulePreflightRefusesAnAuthoriserNotAtItsCodehash() external {
        ScheduleRevokeServiceSignerDepositWithdrawHarness schedule = scheduleOnBase();
        address authoriser = LibAuthoriserInvariants.authoriserForChainId(block.chainid);
        vm.etch(authoriser, hex"00");
        vm.expectRevert(abi.encodeWithSelector(AuthoriserNotReady.selector, authoriser));
        schedule.callPreflight();
    }

    /// @notice The schedule pre-flight refuses a timelock not in its pinned
    /// state.
    function testSchedulePreflightRefusesATimelockNotInItsPinnedState() external {
        ScheduleRevokeServiceSignerDepositWithdrawHarness schedule = scheduleOnBase();
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        vm.prank(timelock);
        TimelockController(payable(timelock)).revokeRole(LibTimelockInvariants.TIMELOCK_PROPOSER_ROLE, safe);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockMissingRole.selector,
                timelock,
                LibTimelockInvariants.TIMELOCK_PROPOSER_ROLE,
                safe
            )
        );
        schedule.callPreflight();
    }

    /// @notice The schedule post-state refuses the record landed without the
    /// batch, and the batch past its delay.
    function testSchedulePostStateRefusesABatchNotPendingInsideItsDelay() external {
        ScheduleRevokeServiceSignerDepositWithdrawHarness schedule = scheduleOnBase();
        bytes32 id =
            LibServiceSignerRevoke.operationId(LibTimelockInvariants.timelockForChainId(block.chainid), block.chainid);
        SafeTx[] memory txs = schedule.callAuthorBundle();

        uint256 snapshot = vm.snapshotState();
        SafeTx[] memory recordOnly = new SafeTx[](1);
        recordOnly[0] = txs[txs.length - 1];
        LibSafeFork.executeBundle(vm, Safe(payable(LibSafeInvariants.safeForChainId(block.chainid))), recordOnly);
        vm.expectRevert(abi.encodeWithSelector(RevokeNotPendingInsideDelay.selector, id));
        schedule.callAssertPostState();
        vm.revertToState(snapshot);

        executePrefix(txs, txs.length);
        schedule.callAssertPostState();
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        vm.expectRevert(abi.encodeWithSelector(RevokeNotPendingInsideDelay.selector, id));
        schedule.callAssertPostState();
    }

    /// @notice The executor refuses a key that holds the timelock's executor
    /// role, with the batch ready.
    function testExecuteRefusesAKeyHoldingTheExecutorRole() external {
        scheduleOnBase();
        scheduleRevokeBatch();
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        ExecuteRevokeServiceSignerDepositWithdraw executor = new ExecuteRevokeServiceSignerDepositWithdraw();
        bytes32 executorRole = LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE;
        vm.prank(timelock);
        TimelockController(payable(timelock)).grantRole(executorRole, address(this));
        vm.expectRevert(abi.encodeWithSelector(RevokeExecutorHoldsRole.selector, timelock, address(this)));
        executor.execute();
    }

    /// @notice After the batch executed, the record pre-flight refuses a
    /// service signer holding either role again.
    function testRecordPreflightRefusesTheSignerHoldingEitherRoleAgain() external {
        ScheduleRevokeServiceSignerDepositWithdrawHarness schedule = scheduleOnBase();
        executePrefix(schedule.callAuthorBundle(), 2);
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        ExecuteRevokeServiceSignerDepositWithdrawHarness execution =
            new ExecuteRevokeServiceSignerDepositWithdrawHarness("refusals");
        execution.execute();
        execution.callPreflight();

        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        IAccessControl authoriser = IAccessControl(LibAuthoriserInvariants.authoriserForChainId(block.chainid));
        bytes32[2] memory roles = revokedRoles();
        for (uint256 roleIndex = 0; roleIndex < roles.length; roleIndex++) {
            uint256 snapshot = vm.snapshotState();
            vm.prank(timelock);
            authoriser.grantRole(roles[roleIndex], LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C);
            vm.expectRevert(abi.encodeWithSelector(ServiceSignerStillHoldsRole.selector, roles[roleIndex]));
            execution.callPreflight();
            vm.revertToState(snapshot);
        }
    }
}

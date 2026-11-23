// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {LibSafeFork} from "rain-deploy-0.1.38/src/lib/LibSafeFork.sol";
import {LibSafeTx, SafeTx} from "rain-deploy-0.1.38/src/lib/LibSafeTx.sol";

import {
    ScheduleZerogOrchestratorRoles,
    TimelockNotOrchestratorAdmin,
    ZerogOrchestratorRolesAlreadyScheduled,
    ZerogOrchestratorRolesNotPendingInsideDelay,
    ZerogOrchestratorRolesRescheduleNotAtTheSchedule,
    ZerogOrchestratorRolesRescheduleOffZerog
} from "../../script/20261123-schedule-zerog-orchestrator-roles.s.sol";
import {
    ExecuteZerogOrchestratorRoles,
    ZerogOrchestratorRolesExecuteOffZerog,
    ZerogOrchestratorRolesExecutorHoldsRole,
    ZerogOrchestratorRolesNotExecuted,
    ZerogOrchestratorRolesNotReady
} from "../../script/20261123-execute-zerog-orchestrator-roles.s.sol";
import {MintAuthV1} from "../../src/interface/deprecated/IST0xOrchestratorV1.sol";
import {ExpectedGrantMissing, LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {ContractRoles, LibIdealRoles} from "../../src/lib/LibIdealRoles.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations, UnexpectedMigrationLine} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {
    LibZerogOrchestratorRoles,
    ZerogOrchestratorRoleAlreadyGranted,
    ZerogOrchestratorRoleNotGranted
} from "../../src/lib/LibZerogOrchestratorRoles.sol";
import {RoleGrant} from "../../src/lib/RoleGrant.sol";
import {ExecuteZerogOrchestratorRolesHarness} from "./ExecuteZerogOrchestratorRolesHarness.sol";
import {ScheduleZerogOrchestratorRolesHarness} from "./ScheduleZerogOrchestratorRolesHarness.sol";
import {ZerogOrchestratorRolesFixture} from "./ZerogOrchestratorRolesFixture.sol";

/// @title ZerogOrchestratorRolesRolloutTest
/// @notice The 0G orchestrator roles on live 0G at the token creation's record: the signers schedule, anyone executes
/// after the delay, and the issuance service then mints and burns a 0G token through the orchestrator.
contract ZerogOrchestratorRolesRolloutTest is ZerogOrchestratorRolesFixture {
    function setUp() external {
        forkZerogAtTheTokenRecord();
    }

    /// @notice The acceptance path. Before: the service cannot mint. The signers land the schedule; inside the delay
    /// no one can execute; after it a roleless key executes, the orchestrator and US authoriser hold every pair
    /// `LibIdealRoles` expects of them, the service mints to a recipient and burns the shares back, and the Safe
    /// records the execution.
    function testSignersScheduleAnyoneExecutesThenTheServiceMintsAndBurns() external {
        address vault = usVault();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C,
                keccak256("MINT")
            )
        );
        vm.prank(LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C);
        orchestrator().mint(vault, address(0xBEEF), MINT_AMOUNT, emptyAuth(), "");

        bytes32 safeTxHash = scheduleAsSigners();
        console2.log("Schedule bundle safeTxHash at Safe nonce 6:", vm.toString(safeTxHash));
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.SCHEDULE_ZEROG_ORCHESTRATOR_ROLES, "schedule recorded");

        bytes32 id = LibZerogOrchestratorRoles.operationId(zerogTimelock());
        ExecuteZerogOrchestratorRoles early = new ExecuteZerogOrchestratorRoles();
        vm.expectRevert(abi.encodeWithSelector(ZerogOrchestratorRolesNotReady.selector, id, true, false));
        early.execute();

        executeAfterTheDelay();
        assertTrue(TimelockController(payable(zerogTimelock())).isOperationDone(id), "done");
        LibZerogOrchestratorRoles.assertGranted();
        ContractRoles[] memory ideal = LibIdealRoles.contractRoles(LibSafeInvariants.ZEROG_CHAIN_ID);
        LibAuthoriserInvariants.assertHeld(ideal[0].target, ideal[0].expected);
        LibAuthoriserInvariants.assertHeld(ideal[2].target, ideal[2].expected);

        address recipient = mintAsTheService(vault);
        assertEq(IERC20(vault).balanceOf(recipient), MINT_AMOUNT, "minted to the recipient");
        burnAsTheService(vault, recipient);
        assertEq(IERC20(vault).totalSupply(), 0, "burned");

        landExecutionRecord();
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.EXECUTE_ZEROG_ORCHESTRATOR_ROLES, "execution recorded");
    }

    /// @notice `run()` authors the bundle on live 0G, as `run-script` does, and returns the hash the signers approve.
    function testRunAuthorsTheBundleTheSignersApprove() external {
        (, bytes32 expected) = scheduleSafeTx();
        ScheduleZerogOrchestratorRolesHarness schedule = new ScheduleZerogOrchestratorRolesHarness("run");
        uint256 beforeRun = vm.snapshotState();
        assertEq(schedule.run(), expected, "safeTxHash");
        vm.revertToState(beforeRun);
        assertEq(schedule.verify(schedule.callArtifactPath()), expected, "artifact verifies against live 0G");
    }

    /// @notice The bundle is the `scheduleBatch` of exactly the five grants at the minimum delay, then the record.
    function testBundleIsTheFiveGrantsScheduledThenTheRecord() external {
        ScheduleZerogOrchestratorRolesHarness schedule = new ScheduleZerogOrchestratorRolesHarness("bundle");
        SafeTx[] memory txs = schedule.callAuthorBundle();
        assertEq(txs.length, 2, "schedule then record");
        assertEq(txs[0].to, zerogTimelock(), "schedule target");
        assertEq(txs[0].value, 0, "schedule value");
        assertEq(uint8(txs[0].operation), uint8(Enum.Operation.Call), "schedule operation");

        address us = LibAuthoriserInvariants.authoriserForChainId(LibSafeInvariants.ZEROG_CHAIN_ID);
        address instance = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;
        address service = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;
        address[] memory targets = new address[](5);
        bytes[] memory payloads = new bytes[](5);
        targets[0] = instance;
        payloads[0] = abi.encodeCall(IAccessControl.grantRole, (keccak256("MINT"), service));
        targets[1] = instance;
        payloads[1] = abi.encodeCall(IAccessControl.grantRole, (keccak256("BURN"), service));
        targets[2] = instance;
        payloads[2] = abi.encodeCall(IAccessControl.grantRole, (keccak256("EMERGENCY"), address(zerogSafe())));
        targets[3] = us;
        payloads[3] = abi.encodeCall(IAccessControl.grantRole, (keccak256("DEPOSIT"), instance));
        targets[4] = us;
        payloads[4] = abi.encodeCall(IAccessControl.grantRole, (keccak256("WITHDRAW"), instance));
        assertEq(
            txs[0].data,
            abi.encodeCall(
                TimelockController.scheduleBatch,
                (
                    targets,
                    new uint256[](5),
                    payloads,
                    bytes32(0),
                    keccak256("st0x.zerog-orchestrator-roles"),
                    uint256(48 hours)
                )
            ),
            "schedule calldata"
        );
        (address registry, bytes memory record) = LibStoxMigrations.recordCall(
            new ScheduleZerogOrchestratorRoles().declaration(LibSafeInvariants.ZEROG_CHAIN_ID)
        );
        assertEq(txs[1].to, registry, "record target");
        assertEq(txs[1].data, record, "record calldata");
    }

    /// @notice On live 0G the orchestrator and US authoriser lack exactly the batch's five pairs of what
    /// `LibIdealRoles` expects of them, and the EU authoriser and the timelock already hold all of theirs.
    /// The mint-caps orchestrator is left out, by its target: it is not deployed on 0G, so it has no code to hold a
    /// role, and the batch does not grant it anything.
    function testTheBatchIsExactlyWhatZerogLacks() external view {
        ContractRoles[] memory ideal = LibIdealRoles.contractRoles(LibSafeInvariants.ZEROG_CHAIN_ID);
        (address[] memory targets, RoleGrant[] memory grants) = LibZerogOrchestratorRoles.grants();
        address mintCaps = LibOrchestratorInvariants.mintCapsInstance();
        assertEq(mintCaps.code.length, 0, "the mint-caps orchestrator is not deployed on 0G");
        uint256 lacking = 0;
        for (uint256 contractIndex = 0; contractIndex < ideal.length; contractIndex++) {
            if (ideal[contractIndex].target == mintCaps) continue;
            for (uint256 grantIndex = 0; grantIndex < ideal[contractIndex].expected.length; grantIndex++) {
                RoleGrant memory pair = ideal[contractIndex].expected[grantIndex];
                if (IAccessControl(ideal[contractIndex].target).hasRole(pair.role, pair.grantee)) continue;
                lacking++;
                assertTrue(inBatch(targets, grants, ideal[contractIndex].target, pair), "lacking pair is in the batch");
            }
        }
        assertEq(lacking, LibZerogOrchestratorRoles.GRANT_COUNT, "the batch is every lacking pair");
    }

    function inBatch(address[] memory targets, RoleGrant[] memory grants, address target, RoleGrant memory pair)
        internal
        pure
        returns (bool)
    {
        for (uint256 grantIndex = 0; grantIndex < targets.length; grantIndex++) {
            if (
                targets[grantIndex] == target && grants[grantIndex].role == pair.role
                    && grants[grantIndex].grantee == pair.grantee
            ) return true;
        }
        return false;
    }

    function emptyAuth() internal pure returns (MintAuthV1 memory) {
        return MintAuthV1({nonce: bytes32(0), signature: ""});
    }

    function testSchedulePreflightRefusesAGrantAlreadyHeld() external {
        ScheduleZerogOrchestratorRolesHarness schedule = new ScheduleZerogOrchestratorRolesHarness("held");
        schedule.callPreflight();
        (address[] memory targets, RoleGrant[] memory grants) = LibZerogOrchestratorRoles.grants();
        for (uint256 grantIndex = 0; grantIndex < targets.length; grantIndex++) {
            uint256 snapshot = vm.snapshotState();
            vm.prank(zerogTimelock());
            IAccessControl(targets[grantIndex]).grantRole(grants[grantIndex].role, grants[grantIndex].grantee);
            vm.expectRevert(
                abi.encodeWithSelector(
                    ZerogOrchestratorRoleAlreadyGranted.selector,
                    targets[grantIndex],
                    grants[grantIndex].role,
                    grants[grantIndex].grantee
                )
            );
            schedule.callPreflight();
            vm.revertToState(snapshot);
        }
    }

    function testSchedulePreflightRefusesATimelockThatIsNotTheOrchestratorAdmin() external {
        ScheduleZerogOrchestratorRolesHarness schedule = new ScheduleZerogOrchestratorRolesHarness("admin");
        vm.mockCall(
            LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE,
            abi.encodeCall(IAccessControl.hasRole, (bytes32(0), zerogTimelock())),
            abi.encode(false)
        );
        vm.expectRevert(abi.encodeWithSelector(TimelockNotOrchestratorAdmin.selector, zerogTimelock()));
        schedule.callPreflight();
    }

    function testSchedulePreflightRefusesAnAuthoriserWithoutEachAdminRole() external {
        ScheduleZerogOrchestratorRolesHarness schedule = new ScheduleZerogOrchestratorRolesHarness("auth-admin");
        address us = LibAuthoriserInvariants.authoriserForChainId(LibSafeInvariants.ZEROG_CHAIN_ID);
        bytes32[2] memory admins = [keccak256("DEPOSIT_ADMIN"), keccak256("WITHDRAW_ADMIN")];
        for (uint256 adminIndex = 0; adminIndex < admins.length; adminIndex++) {
            uint256 snapshot = vm.snapshotState();
            vm.mockCall(
                us, abi.encodeCall(IAccessControl.hasRole, (admins[adminIndex], zerogTimelock())), abi.encode(false)
            );
            vm.expectRevert(
                abi.encodeWithSelector(ExpectedGrantMissing.selector, us, admins[adminIndex], zerogTimelock())
            );
            schedule.callPreflight();
            vm.clearMockedCalls();
            vm.revertToState(snapshot);
        }
    }

    /// @notice The batch scheduled by the Safe without the record leaves the line at the token creation, so only the
    /// timelock's state refuses.
    function testSchedulePreflightRefusesARegisteredBatch() external {
        ScheduleZerogOrchestratorRolesHarness schedule = new ScheduleZerogOrchestratorRolesHarness("registered");
        vm.prank(address(zerogSafe()));
        (bool ok,) = zerogTimelock().call(LibZerogOrchestratorRoles.scheduleCalldata());
        assertTrue(ok, "scheduled");
        bytes32 id = LibZerogOrchestratorRoles.operationId(zerogTimelock());
        vm.expectRevert(abi.encodeWithSelector(ZerogOrchestratorRolesAlreadyScheduled.selector, id));
        schedule.callPreflight();
    }

    /// @notice The schedule post-state refuses a batch that is not pending inside its delay: (a) the record alone
    /// lands, with nothing scheduled; (b) both txs land, then the delay passes and the batch is ready.
    function testSchedulePostStateRefusesABatchNotPendingInsideItsDelay() external {
        ScheduleZerogOrchestratorRolesHarness schedule = new ScheduleZerogOrchestratorRolesHarness("not-pending");
        bytes32 id = LibZerogOrchestratorRoles.operationId(zerogTimelock());
        SafeTx[] memory txs = schedule.callAuthorBundle();

        uint256 snapshot = vm.snapshotState();
        SafeTx[] memory recordOnly = new SafeTx[](1);
        recordOnly[0] = txs[txs.length - 1];
        LibSafeFork.executeBundle(vm, zerogSafe(), recordOnly);
        vm.expectRevert(abi.encodeWithSelector(ZerogOrchestratorRolesNotPendingInsideDelay.selector, id));
        schedule.callAssertPostState();
        vm.revertToState(snapshot);

        LibSafeFork.executeBundle(vm, zerogSafe(), txs);
        schedule.callAssertPostState();
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        vm.expectRevert(abi.encodeWithSelector(ZerogOrchestratorRolesNotPendingInsideDelay.selector, id));
        schedule.callAssertPostState();
    }

    /// @notice The operation id docs/TIMELOCK.md gives the signers for their `isOperationPending` check.
    function testOperationIdIsTheDocumentedOne() external pure {
        assertEq(
            LibZerogOrchestratorRoles.operationId(zerogTimelock()),
            0x03862515933fa4272c3fa3ad4feebfc1533c8f5347da2b962dd7449304dc4ea3,
            "documented operation id"
        );
    }

    /// @notice The cancel recovery end to end. The signers schedule, then the Safe cancels: the line stays at the
    /// schedule record, `run()` and the execute record refuse, and `reschedule()` authors the one direct call. Its
    /// artifact verifies, the signers land it at the hash it printed, the same operation is pending inside the delay,
    /// and after it a roleless key executes and the Safe records the execution.
    function testCancelledBatchRecoversByADirectReschedule() external {
        scheduleAsSigners();
        TimelockController timelock = TimelockController(payable(zerogTimelock()));
        bytes32 id = LibZerogOrchestratorRoles.operationId(zerogTimelock());
        SafeTx memory cancel = SafeTx({
            to: zerogTimelock(),
            value: 0,
            data: abi.encodeCall(TimelockController.cancel, (id)),
            operation: Enum.Operation.Call
        });
        landAsSigners(cancel, LibSafeTx.safeTxHash(zerogSafe(), cancel, zerogSafe().nonce()));
        assertFalse(timelock.isOperation(id), "cancelled");
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.SCHEDULE_ZEROG_ORCHESTRATOR_ROLES, "head stays");

        ScheduleZerogOrchestratorRolesHarness schedule = new ScheduleZerogOrchestratorRolesHarness("reschedule");
        vm.expectRevert(
            abi.encodeWithSelector(
                UnexpectedMigrationLine.selector, LibStoxMigrations.SCHEDULE_ZEROG_ORCHESTRATOR_ROLES
            )
        );
        schedule.callPreflight();
        ExecuteZerogOrchestratorRolesHarness record = new ExecuteZerogOrchestratorRolesHarness("cancelled");
        vm.expectRevert(abi.encodeWithSelector(ZerogOrchestratorRolesNotExecuted.selector, id));
        record.callPreflight();

        SafeTx memory direct = schedule.callScheduleTx();
        assertEq(direct.to, zerogTimelock(), "to");
        assertEq(direct.value, 0, "value");
        assertEq(direct.data, LibZerogOrchestratorRoles.scheduleCalldata(), "data");
        assertEq(uint8(direct.operation), uint8(Enum.Operation.Call), "a direct call");
        bytes32 expected = LibSafeTx.safeTxHash(zerogSafe(), direct, zerogSafe().nonce());
        uint256 beforeRun = vm.snapshotState();
        assertEq(schedule.reschedule(), expected, "reschedule() prints the direct-call hash");
        vm.revertToState(beforeRun);
        assertEq(
            schedule.verifyReschedule(schedule.callRescheduleArtifactPath()), expected, "artifact verifies on live 0G"
        );

        landAsSigners(direct, expected);
        assertTrue(timelock.isOperationPending(id) && !timelock.isOperationReady(id), "same id pending in the delay");
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.SCHEDULE_ZEROG_ORCHESTRATOR_ROLES, "line unchanged");
        ExecuteZerogOrchestratorRoles early = new ExecuteZerogOrchestratorRoles();
        vm.expectRevert(abi.encodeWithSelector(ZerogOrchestratorRolesNotReady.selector, id, true, false));
        early.execute();

        executeAfterTheDelay();
        assertTrue(timelock.isOperationDone(id), "done");
        LibZerogOrchestratorRoles.assertGranted();
        landExecutionRecord();
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.EXECUTE_ZEROG_ORCHESTRATOR_ROLES, "execution recorded");
    }

    /// @notice `reschedule()` refuses unless the batch was scheduled and cancelled: before the schedule lands (the
    /// line is at the token creation), while the batch is pending, after it has executed and its record landed, and
    /// off 0G.
    function testRescheduleRefusesUnlessTheBatchWasCancelled() external {
        ScheduleZerogOrchestratorRolesHarness schedule = new ScheduleZerogOrchestratorRolesHarness("not-cancelled");
        vm.expectRevert(
            abi.encodeWithSelector(
                ZerogOrchestratorRolesRescheduleNotAtTheSchedule.selector, LibStoxMigrations.CREATE_ZEROG_TOKENS
            )
        );
        schedule.callReschedulePreflight();

        scheduleAsSigners();
        bytes32 id = LibZerogOrchestratorRoles.operationId(zerogTimelock());
        vm.expectRevert(abi.encodeWithSelector(ZerogOrchestratorRolesAlreadyScheduled.selector, id));
        schedule.callReschedulePreflight();

        executeAfterTheDelay();
        vm.expectRevert(
            abi.encodeWithSelector(
                ZerogOrchestratorRoleAlreadyGranted.selector,
                LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE,
                keccak256("MINT"),
                LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C
            )
        );
        schedule.callReschedulePreflight();
        landExecutionRecord();
        vm.expectRevert(
            abi.encodeWithSelector(
                ZerogOrchestratorRolesRescheduleNotAtTheSchedule.selector,
                LibStoxMigrations.EXECUTE_ZEROG_ORCHESTRATOR_ROLES
            )
        );
        schedule.callReschedulePreflight();

        vm.chainId(LibSafeInvariants.HYPEREVM_CHAIN_ID);
        vm.expectRevert(
            abi.encodeWithSelector(
                ZerogOrchestratorRolesRescheduleOffZerog.selector, LibSafeInvariants.HYPEREVM_CHAIN_ID
            )
        );
        schedule.callReschedulePreflight();
    }

    function testExecuteRefusesOffZerog() external {
        ExecuteZerogOrchestratorRoles executor = new ExecuteZerogOrchestratorRoles();
        vm.chainId(LibSafeInvariants.HYPEREVM_CHAIN_ID);
        vm.expectRevert(
            abi.encodeWithSelector(ZerogOrchestratorRolesExecuteOffZerog.selector, LibSafeInvariants.HYPEREVM_CHAIN_ID)
        );
        executor.execute();
    }

    function testExecuteRefusesAnUnscheduledBatch() external {
        ExecuteZerogOrchestratorRoles executor = new ExecuteZerogOrchestratorRoles();
        bytes32 id = LibZerogOrchestratorRoles.operationId(zerogTimelock());
        vm.expectRevert(abi.encodeWithSelector(ZerogOrchestratorRolesNotReady.selector, id, false, false));
        executor.execute();
    }

    function testExecuteRefusesAKeyHoldingTheExecutorRole() external {
        scheduleAsSigners();
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        ExecuteZerogOrchestratorRoles executor = new ExecuteZerogOrchestratorRoles();
        address sender = address(this);
        vm.mockCall(
            zerogTimelock(),
            abi.encodeCall(IAccessControl.hasRole, (LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE, sender)),
            abi.encode(true)
        );
        vm.expectRevert(
            abi.encodeWithSelector(ZerogOrchestratorRolesExecutorHoldsRole.selector, zerogTimelock(), sender)
        );
        executor.execute();
    }

    function testExecuteRefusesAGrantMissingAfterExecution() external {
        scheduleAsSigners();
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        ExecuteZerogOrchestratorRoles executor = new ExecuteZerogOrchestratorRoles();
        address service = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;
        vm.mockCall(
            LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE,
            abi.encodeCall(IAccessControl.hasRole, (keccak256("MINT"), service)),
            abi.encode(false)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                ZerogOrchestratorRoleNotGranted.selector,
                LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE,
                keccak256("MINT"),
                service
            )
        );
        executor.execute();
    }

    function testRecordPreflightRefusesBeforeTheBatchExecutes() external {
        scheduleAsSigners();
        ExecuteZerogOrchestratorRolesHarness record = new ExecuteZerogOrchestratorRolesHarness("early-record");
        bytes32 id = LibZerogOrchestratorRoles.operationId(zerogTimelock());
        vm.expectRevert(abi.encodeWithSelector(ZerogOrchestratorRolesNotExecuted.selector, id));
        record.callPreflight();
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        vm.expectRevert(abi.encodeWithSelector(ZerogOrchestratorRolesNotExecuted.selector, id));
        record.callPreflight();
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.30/src/lib/LibSafeFork.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibMigrationRegistryDeploy.sol";

import {
    V6FirstRenameAlreadyScheduled,
    ScheduleV6FirstRenameUnexpectedMigrationLine,
    V6FirstRenameNotPendingInsideDelay,
    ScheduleV6FirstRenameRecordMismatch,
    scheduleV6FirstRenameDeclaration
} from "../../script/20261105-schedule-v6-first-rename.s.sol";
import {
    ExecuteV6FirstRename,
    V6FirstRenameNotReady,
    V6FirstRenameExecutorHoldsRole,
    executeV6FirstRenameDeclaration
} from "../../script/20261105-execute-v6-first-rename.s.sol";
import {
    V6FirstRenameNotExecuted,
    ExecuteV6FirstRenameRecorded,
    ExecuteV6FirstRenameUnexpectedMigrationLine,
    ExecuteV6FirstRenameRecordMismatch
} from "../../script/records/20261105-record-execute-v6-first-rename.s.sol";
import {IOwnable} from "../../src/interface/IOwnable.sol";
import {IStoxAssetIdV1} from "../../src/interface/IStoxAssetIdV1.sol";
import {IStoxUnderlyingV1} from "../../src/interface/IStoxUnderlyingV1.sol";
import {LibProdTokenConfig, TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {
    LibV6FirstRename,
    AssetIdNotBoundToToken,
    V6TokenAlreadyNamed,
    V6TokenNotDeployed,
    V6TokenOwnerMismatch,
    V6TokenNameMismatch,
    V6FirstRenameTableShort
} from "../../src/lib/LibV6FirstRename.sol";
import {ST0X_NAME_SUFFIX} from "../../src/lib/LibUnderlying.sol";
import {V6ReleaseBaseFork} from "../abstract/V6ReleaseBaseFork.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {RecordExecuteV6FirstRenameHarness} from "./RecordExecuteV6FirstRenameHarness.sol";
import {ScheduleV6FirstRenameHarness} from "./ScheduleV6FirstRenameHarness.sol";

/// @title V6FirstRenameTest
/// @notice The first `setUnderlying` of every V6 token: the batch covers every V6 row, and on a Base fork with every
/// V6 token deployed the Safe schedules it on the governance timelock, a roleless key executes it after the delay,
/// and the Safe records the execution. The pre-flight binds each call to its row by asset id.
contract V6FirstRenameTest is V6ReleaseBaseFork {
    /// The batch has one `setUnderlying(underlying, underlyingName)` per V6 row, in table order, against the row's
    /// pinned token, and its id is the timelock's own hash of it.
    function testBatchNamesEveryV6RowAtItsToken() external {
        TokenConfig[] memory configs = LibV6FirstRename.rows();
        assertEq(configs.length, LibV6FirstRename.ROW_COUNT, "the leading V6 rows");
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = LibV6FirstRename.batch(configs);
        assertEq(targets.length, configs.length, "targets");
        for (uint256 i = 0; i < configs.length; i++) {
            assertEq(targets[i], LibV6FirstRename.tokenOf(configs[i]), configs[i].underlying);
            assertEq(values[i], 0, configs[i].underlying);
            assertEq(
                payloads[i],
                abi.encodeCall(IStoxUnderlyingV1.setUnderlying, (configs[i].underlying, configs[i].underlyingName)),
                configs[i].underlying
            );
            for (uint256 j = 0; j < i; j++) {
                assertTrue(targets[i] != targets[j], configs[i].underlying);
            }
        }
        TimelockController local = new TimelockController(0, new address[](0), new address[](0), address(this));
        assertEq(
            LibV6FirstRename.operationId(configs),
            local.hashOperationBatch(targets, values, payloads, bytes32(0), LibV6FirstRename.SALT),
            "operation id"
        );
    }

    /// The batch the table derives is the one this migration froze. A row edit fails here, so it needs a new dated
    /// script instead of moving a batch that may already be scheduled.
    function testOperationIdIsFrozen() external pure {
        assertEq(
            LibV6FirstRename.operationId(LibProdTokenConfig.v6TokenConfigs()),
            LibV6FirstRename.OPERATION_ID,
            "frozen batch"
        );
    }

    /// The execution migration sits onto the schedule, which sits onto the live tokens' execution.
    function testDeclarationsChainOntoTheLiveRename() external pure {
        assertEq(scheduleV6FirstRenameDeclaration().id, LibStoxMigrations.SCHEDULE_V6_FIRST_RENAME);
        assertEq(scheduleV6FirstRenameDeclaration().onto, LibStoxMigrations.EXECUTE_UNDERLYING_NAMING);
        assertEq(executeV6FirstRenameDeclaration().id, LibStoxMigrations.EXECUTE_V6_FIRST_RENAME);
        assertEq(executeV6FirstRenameDeclaration().onto, LibStoxMigrations.SCHEDULE_V6_FIRST_RENAME);
    }

    function safe() internal view returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// Base with every V6 token deployed and the root line at the schedule's `onto`. The earlier migrations of the
    /// line have their own tests, so this writes the live rename's execution record directly.
    function forkWithV6Tokens() internal {
        forkBase();
        deployAllRows();
        address safeAddress = address(safe());
        if (LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code.length == 0) {
            LibTestRootLine.etchRegistry(vm);
        }
        LibTestRootLine.approve(vm, safeAddress);
        LibTestRootLine.write(vm, safeAddress, LibStoxMigrations.EXECUTE_UNDERLYING_NAMING, LibStoxMigrations.head());
        assertEq(LibStoxMigrations.head(), scheduleV6FirstRenameDeclaration().onto, "line at the schedule onto");
    }

    /// Schedule, execute after the delay from a roleless key, then record: every V6 token is named, keeps its asset
    /// id, and the line advances through both records.
    function testScheduleExecuteAndRecordNameEveryV6Token() external {
        forkWithV6Tokens();
        ScheduleV6FirstRenameHarness schedule = new ScheduleV6FirstRenameHarness("flow");
        schedule.callPreflight();
        SafeTx[] memory txs = schedule.callAuthorBundle();
        assertEq(txs.length, 2, "schedule then record");
        assertEq(txs[0].to, LibV6FirstRename.timelock(), "schedule target");
        assertEq(
            txs[0].data,
            LibV6FirstRename.scheduleCalldata(LibV6FirstRename.rows(), LibTimelockInvariants.TIMELOCK_MIN_DELAY),
            "schedule calldata"
        );
        (address registry, bytes memory record) = LibStoxMigrations.recordCall(scheduleV6FirstRenameDeclaration());
        assertEq(txs[1].to, registry, "record target");
        assertEq(txs[1].data, record, "record calldata");
        assertEq(uint8(txs[1].operation), uint8(Enum.Operation.Call), "record operation");
        LibSafeFork.executeBundle(vm, safe(), txs);
        schedule.callAssertPostState();
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.SCHEDULE_V6_FIRST_RENAME, "schedule record heads");

        ExecuteV6FirstRename execute = new ExecuteV6FirstRename();
        bytes32 id = LibV6FirstRename.operationId(LibV6FirstRename.rows());
        vm.expectRevert(abi.encodeWithSelector(V6FirstRenameNotReady.selector, id, true, false));
        execute.run();

        RecordExecuteV6FirstRenameHarness recordExecution = new RecordExecuteV6FirstRenameHarness("flow");
        vm.expectRevert(abi.encodeWithSelector(V6FirstRenameNotExecuted.selector, id));
        recordExecution.callPreflight();

        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        execute.run();
        TokenConfig[] memory configs = LibV6FirstRename.rows();
        LibV6FirstRename.assertAllNamed(configs);
        for (uint256 i = 0; i < configs.length; i++) {
            address token = LibV6FirstRename.tokenOf(configs[i]);
            assertEq(IERC20Metadata(token).symbol(), configs[i].symbol, configs[i].underlying);
        }

        recordExecution.callPreflight();
        LibSafeFork.executeBundle(vm, safe(), recordExecution.callAuthorBundle());
        recordExecution.callAssertPostState();
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.EXECUTE_V6_FIRST_RENAME, "execution record heads");
        vm.expectRevert(
            abi.encodeWithSelector(ExecuteV6FirstRenameRecorded.selector, LibStoxMigrations.EXECUTE_V6_FIRST_RENAME)
        );
        recordExecution.callPreflight();
    }

    /// The schedule bundle's own execution proof names every V6 token.
    function testScheduleBundleProvesExecution() external {
        forkWithV6Tokens();
        ScheduleV6FirstRenameHarness schedule = new ScheduleV6FirstRenameHarness("prove");
        LibSafeFork.executeBundle(vm, safe(), schedule.callAuthorBundle());
        schedule.callProveExecution();
    }

    /// After the Safe cancels the batch inside its delay, a new dispatch authors the schedule alone, the line stays at
    /// the schedule's record, and the batch is pending again.
    function testCancelledBatchIsRescheduledWithoutASecondRecord() external {
        forkWithV6Tokens();
        ScheduleV6FirstRenameHarness schedule = new ScheduleV6FirstRenameHarness("cancel");
        LibSafeFork.executeBundle(vm, safe(), schedule.callAuthorBundle());
        bytes32 id = LibV6FirstRename.operationId(LibV6FirstRename.rows());
        uint256 recorded = LibStoxMigrations.applied(LibStoxMigrations.SCHEDULE_V6_FIRST_RENAME);

        vm.expectRevert(abi.encodeWithSelector(V6FirstRenameAlreadyScheduled.selector, id));
        schedule.callPreflight();

        vm.prank(address(safe()));
        TimelockController(payable(LibV6FirstRename.timelock())).cancel(id);
        vm.warp(block.timestamp + 1);

        schedule.callPreflight();
        SafeTx[] memory txs = schedule.callAuthorBundle();
        assertEq(txs.length, 1, "schedule only");
        LibSafeFork.executeBundle(vm, safe(), txs);
        schedule.callAssertPostState();
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.SCHEDULE_V6_FIRST_RENAME, "line unchanged");
        assertEq(LibStoxMigrations.applied(LibStoxMigrations.SCHEDULE_V6_FIRST_RENAME), recorded, "one record");
        assertTrue(TimelockController(payable(LibV6FirstRename.timelock())).isOperationPending(id), "pending again");
    }

    /// The pre-flight refuses a root line at any other head.
    function testSchedulePreflightRefusesTheWrongLineHead() external {
        forkWithV6Tokens();
        bytes32 foreign = keccak256("st0x.test.v6-first-rename.foreign-record");
        LibTestRootLine.write(vm, address(safe()), foreign, LibStoxMigrations.head());
        ScheduleV6FirstRenameHarness schedule = new ScheduleV6FirstRenameHarness("head");
        vm.expectRevert(abi.encodeWithSelector(ScheduleV6FirstRenameUnexpectedMigrationLine.selector, foreign));
        schedule.callPreflight();
    }

    /// The pre-flight refuses a token at a row's address that reports another asset id, one not owned by the
    /// governance timelock, one already named, and a row with no token.
    function testSchedulePreflightRefusesEachUnreadyToken() external {
        forkWithV6Tokens();
        ScheduleV6FirstRenameHarness schedule = new ScheduleV6FirstRenameHarness("unready");
        TokenConfig[] memory configs = LibV6FirstRename.rows();
        TokenConfig memory config = configs[configs.length - 1];
        address token = LibV6FirstRename.tokenOf(config);

        uint256 snapshot = vm.snapshotState();
        vm.mockCall(token, abi.encodeWithSelector(IStoxAssetIdV1.assetId.selector), abi.encode("US0000000000"));
        vm.expectRevert(abi.encodeWithSelector(AssetIdNotBoundToToken.selector, token, config.assetId, "US0000000000"));
        schedule.callPreflight();
        vm.revertToState(snapshot);
        vm.clearMockedCalls();

        address other = address(uint160(uint256(keccak256("st0x.test.v6-first-rename.other-owner"))));
        vm.mockCall(token, abi.encodeWithSelector(IOwnable.owner.selector), abi.encode(other));
        vm.expectRevert(abi.encodeWithSelector(V6TokenOwnerMismatch.selector, token, other));
        schedule.callPreflight();
        vm.revertToState(snapshot);
        vm.clearMockedCalls();

        vm.prank(LibV6FirstRename.timelock());
        IStoxUnderlyingV1(token).setUnderlying(config.underlying, config.underlyingName);
        vm.expectRevert(
            abi.encodeWithSelector(
                V6TokenAlreadyNamed.selector, token, IERC20Metadata(token).name(), IERC20Metadata(token).symbol()
            )
        );
        schedule.callPreflight();
        vm.revertToState(snapshot);
        vm.clearMockedCalls();

        vm.etch(token, "");
        vm.expectRevert(abi.encodeWithSelector(V6TokenNotDeployed.selector, config.underlying, token));
        schedule.callPreflight();
    }

    function prodRowsPlusOne() internal pure returns (TokenConfig[] memory configs) {
        TokenConfig[] memory table = LibProdTokenConfig.v6TokenConfigs();
        configs = new TokenConfig[](table.length + 1);
        for (uint256 i = 0; i < table.length; i++) {
            configs[i] = table[i];
        }
        configs[table.length] = TokenConfig({
            underlying: "APPENDED",
            name: "Appended ST0x",
            symbol: "tAPPENDED",
            region: table[0].region,
            underlyingName: "Appended",
            assetId: "ST0XAPPENDED"
        });
    }

    /// A row appended after the first `ROW_COUNT` does not move the batch: the leading rows and the id are unchanged.
    function testAnAppendedRowDoesNotMoveTheBatch() external pure {
        TokenConfig[] memory configs = LibV6FirstRename.leading(prodRowsPlusOne());
        assertEq(configs.length, LibV6FirstRename.ROW_COUNT, "leading rows");
        assertEq(LibV6FirstRename.operationId(configs), LibV6FirstRename.OPERATION_ID, "frozen batch");
    }

    /// A table with fewer V6 rows than the batch names is refused.
    function testAShortTableIsRefused() external {
        TokenConfig[] memory configs = LibProdTokenConfig.v6TokenConfigs();
        assembly ("memory-safe") {
            mstore(configs, sub(mload(configs), 1))
        }
        vm.expectRevert(
            abi.encodeWithSelector(
                V6FirstRenameTableShort.selector, LibV6FirstRename.ROW_COUNT, LibV6FirstRename.ROW_COUNT - 1
            )
        );
        this.externalLeading(configs);
    }

    function externalLeading(TokenConfig[] memory configs) external pure returns (TokenConfig[] memory) {
        return LibV6FirstRename.leading(configs);
    }

    function externalAssertNamed(TokenConfig memory config) external view {
        LibV6FirstRename.assertNamed(config);
    }

    /// The executor refuses a key that holds the executor role, so an execution always proves permissionless
    /// execution.
    function testExecutorRefusesAKeyHoldingTheExecutorRole() external {
        forkWithV6Tokens();
        address timelock = LibV6FirstRename.timelock();
        vm.prank(timelock);
        TimelockController(payable(timelock)).grantRole(LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE, address(this));
        ExecuteV6FirstRename execute = new ExecuteV6FirstRename();
        vm.expectRevert(abi.encodeWithSelector(V6FirstRenameExecutorHoldsRole.selector, timelock, address(this)));
        execute.run();
    }

    /// The record pre-flight refuses a line moved past the schedule's record, and the record post-state refuses a
    /// record from another moment.
    function testRecordRefusesTheWrongLineHeadAndAnotherMoment() external {
        forkWithV6Tokens();
        ScheduleV6FirstRenameHarness schedule = new ScheduleV6FirstRenameHarness("rec-head");
        LibSafeFork.executeBundle(vm, safe(), schedule.callAuthorBundle());
        vm.warp(vm.getBlockTimestamp() + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        new ExecuteV6FirstRename().run();
        RecordExecuteV6FirstRenameHarness record = new RecordExecuteV6FirstRenameHarness("rec-head");

        uint256 snapshot = vm.snapshotState();
        bytes32 foreign = keccak256("st0x.test.v6-first-rename.foreign-record");
        LibTestRootLine.write(vm, address(safe()), foreign, LibStoxMigrations.head());
        vm.expectRevert(abi.encodeWithSelector(ExecuteV6FirstRenameUnexpectedMigrationLine.selector, foreign));
        record.callPreflight();
        vm.revertToState(snapshot);

        LibSafeFork.executeBundle(vm, safe(), record.callAuthorBundle());
        uint256 recorded = vm.getBlockTimestamp();
        vm.warp(recorded + 1);
        vm.expectRevert(abi.encodeWithSelector(ExecuteV6FirstRenameRecordMismatch.selector, recorded + 1, recorded));
        record.callAssertPostState();
    }

    /// The schedule post-state refuses a batch that is not pending, and a schedule without its record.
    function testSchedulePostStateRefusesAnUnscheduledBatchAndAMissingRecord() external {
        forkWithV6Tokens();
        ScheduleV6FirstRenameHarness schedule = new ScheduleV6FirstRenameHarness("post");
        bytes32 id = LibV6FirstRename.operationId(LibV6FirstRename.rows());
        vm.expectRevert(abi.encodeWithSelector(V6FirstRenameNotPendingInsideDelay.selector, id));
        schedule.callAssertPostState();
        SafeTx[] memory txs = schedule.callAuthorBundle();
        SafeTx[] memory scheduleOnly = new SafeTx[](1);
        scheduleOnly[0] = txs[0];
        LibSafeFork.executeBundle(vm, safe(), scheduleOnly);
        vm.expectRevert(
            abi.encodeWithSelector(
                ScheduleV6FirstRenameRecordMismatch.selector, LibStoxMigrations.EXECUTE_UNDERLYING_NAMING, uint256(0)
            )
        );
        schedule.callAssertPostState();
    }

    /// The post-execution check refuses a token whose name is not the one its first rename sets.
    function testAssertNamedRefusesAWrongName() external {
        forkWithV6Tokens();
        TokenConfig memory config = LibV6FirstRename.rows()[0];
        address token = LibV6FirstRename.tokenOf(config);
        vm.prank(LibV6FirstRename.timelock());
        IStoxUnderlyingV1(token).setUnderlying(config.underlying, "Wrong Name");
        vm.expectRevert(
            abi.encodeWithSelector(
                V6TokenNameMismatch.selector,
                token,
                string.concat(config.underlyingName, ST0X_NAME_SUFFIX),
                string.concat("Wrong Name", ST0X_NAME_SUFFIX)
            )
        );
        this.externalAssertNamed(config);
    }
}

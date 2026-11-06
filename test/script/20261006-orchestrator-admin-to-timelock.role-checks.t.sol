// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {IMigrationRegistryV5, MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.30/src/lib/LibSafeFork.sol";

import {OrchestratorAdminToTimelock, RoleNotHeld} from "../../script/20261006-orchestrator-admin-to-timelock.s.sol";
import {LocalBaseOrchestratorFixture} from "./LocalBaseOrchestratorFixture.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {IST0xOrchestratorV1} from "../../src/interface/deprecated/IST0xOrchestratorV1.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {
    LibStoxMigrations,
    LineHeadMismatch,
    RecordMismatch,
    SafeNotApprovedWriter,
    UnexpectedMigrationLine
} from "../../src/lib/LibStoxMigrations.sol";

/// @title OrchestratorAdminToTimelockLocalTest
/// @notice The move on a local Base whose root line is at the V5 backfill, so
/// it runs whatever the live chains have recorded.
contract OrchestratorAdminToTimelockLocalTest is LocalBaseOrchestratorFixture {
    OrchestratorAdminToTimelockHarness internal script;

    function setUp() external {
        buildLocalBase();
        LibTestRootLine.approve(vm, address(safe));
        bytes32 emergency = ORCHESTRATOR.EMERGENCY_ROLE();
        vm.prank(address(safe));
        ORCHESTRATOR.grantRole(emergency, address(safe));
        LibTestRootLine.write(
            vm, address(safe), LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5, MIGRATION_HEAD_GENESIS
        );
        script = new OrchestratorAdminToTimelockHarness("local");
    }

    function executeMove() internal {
        LibSafeFork.executeBundle(vm, safe, script.callAuthorBundle());
    }

    function testDeclarationIsTheMoveOntoTheBackfill(uint256 chainId) external {
        ScriptDeclaration memory declared = new OrchestratorAdminToTimelock().declaration(chainId);
        assertEq(declared.id, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK);
        assertEq(declared.onto, LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5);
        assertFalse(declared.history);
    }

    function testBundleEndsWithItsRootLineRecord() external view {
        SafeTx[] memory txs = script.callAuthorBundle();
        (address recordTo, bytes memory recordData) = LibStoxMigrations.recordCall(
            ScriptDeclaration({
                id: LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK,
                onto: LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5,
                history: false
            })
        );
        SafeTx memory last = txs[txs.length - 1];
        assertEq(last.to, recordTo);
        assertEq(last.value, 0);
        assertEq(last.data, recordData);
    }

    function testPreflightRefusesALineNotAtTheBackfill(bytes32 head) external {
        vm.assume(
            head != LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5 && head != bytes32(0)
                && head != MIGRATION_HEAD_GENESIS
        );
        script.callPreflight();
        LibTestRootLine.write(vm, address(safe), head, LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, head));
        script.callPreflight();
    }

    function testPreflightRefusesASafeTheRootDoesNotApprove() external {
        script.callPreflight();
        LibTestRootLine.revoke(vm, address(safe));
        vm.expectRevert(abi.encodeWithSelector(SafeNotApprovedWriter.selector, address(safe)));
        script.callPreflight();
    }

    function assertZeroAndGenesisRefusedOnto(bytes32 onto) internal {
        vm.expectRevert(IMigrationRegistryV5.ZeroMigration.selector);
        LibTestRootLine.write(vm, address(safe), bytes32(0), onto);
        vm.expectRevert(IMigrationRegistryV5.GenesisMigration.selector);
        LibTestRootLine.write(vm, address(safe), MIGRATION_HEAD_GENESIS, onto);
    }

    function testNoZeroOrGenesisRecordLandsOnTheBackfill() external {
        assertZeroAndGenesisRefusedOnto(LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5);
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5);
    }

    function testNoZeroOrGenesisRecordLandsOnTheMove() external {
        executeMove();
        assertZeroAndGenesisRefusedOnto(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK);
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK);
    }

    function testExecutedMoveIsRecordedAtTheHeadOfTheRootLine() external {
        executeMove();
        assertTrue(ORCHESTRATOR.hasRole(bytes32(0), timelock));
        assertFalse(ORCHESTRATOR.hasRole(bytes32(0), address(safe)));
        assertEq(LibStoxMigrations.applied(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK), block.timestamp);
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK);
        script.callAssertPostState();
    }

    function testPostStateRefusesARecordFromAnotherMoment(uint32 later) external {
        vm.assume(later > 0);
        executeMove();
        uint256 recorded = block.timestamp;
        vm.warp(recorded + later);
        vm.expectRevert(
            abi.encodeWithSelector(
                RecordMismatch.selector, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK, block.timestamp, recorded
            )
        );
        script.callAssertPostState();
    }

    function testPostStateRefusesALineMovedPastTheMove(bytes32 next) external {
        vm.assume(
            next != bytes32(0) && next != MIGRATION_HEAD_GENESIS
                && next != LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK
                && next != LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5
        );
        executeMove();
        LibTestRootLine.write(vm, address(safe), next, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK);
        vm.expectRevert(abi.encodeWithSelector(LineHeadMismatch.selector, next));
        script.callAssertPostState();
    }

    function testPreflightRefusesSafeWithoutEmergency() external {
        bytes32 emergency = ORCHESTRATOR.EMERGENCY_ROLE();
        script.callPreflight();
        vm.mockCall(
            address(ORCHESTRATOR), abi.encodeCall(IAccessControl.hasRole, (emergency, address(safe))), abi.encode(false)
        );
        vm.expectRevert(abi.encodeWithSelector(RoleNotHeld.selector, emergency, address(safe)));
        script.callPreflight();
    }

    function testPostStateRefusesMissingRole() external {
        executeMove();
        script.callAssertPostState();

        bytes32[2] memory roles = [bytes32(0), ORCHESTRATOR.EMERGENCY_ROLE()];
        address[2] memory holders = [timelock, address(safe)];
        for (uint256 i = 0; i < roles.length; i++) {
            vm.clearMockedCalls();
            vm.mockCall(
                address(ORCHESTRATOR), abi.encodeCall(IST0xOrchestratorV1.vaultLogicIsExpected, ()), abi.encode(true)
            );
            vm.mockCall(
                address(ORCHESTRATOR), abi.encodeCall(IAccessControl.hasRole, (roles[i], holders[i])), abi.encode(false)
            );
            vm.expectRevert(abi.encodeWithSelector(RoleNotHeld.selector, roles[i], holders[i]));
            script.callAssertPostState();
        }
    }
}

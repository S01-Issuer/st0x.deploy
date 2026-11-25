// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeTx} from "rain-deploy-0.1.38/src/lib/LibSafeTx.sol";

import {RoleHeld, RoleNotHeld} from "../../script/20261006-orchestrator-admin-to-timelock.s.sol";
import {ORCHESTRATOR_EMERGENCY_ROLE} from "../../src/concrete/ST0xOrchestrator.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibZerogOrchestratorRoles} from "../../src/lib/LibZerogOrchestratorRoles.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {IRecordScriptHooks} from "../lib/RootLineRecordScriptTest.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {ZerogRootLineScriptTest} from "./ZerogRootLineScriptTest.sol";

/// @title OrchestratorAdminToTimelockZerogRootLineTest
/// @notice The orchestrator admin move on 0G, onto the beacon-initial-owner bind: the record alone, since the
/// orchestrator was created with the timelock as its admin. The arm refuses the Safe holding `DEFAULT_ADMIN_ROLE`, the
/// timelock not holding it, and the Safe without `EMERGENCY_ROLE`.
contract OrchestratorAdminToTimelockZerogRootLineTest is ZerogRootLineScriptTest {
    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new OrchestratorAdminToTimelockHarness("zerog-root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.BIND_BEACON_INITIAL_OWNER;
    }

    function orchestratorRoles() internal pure returns (IAccessControl) {
        return IAccessControl(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE);
    }

    function assertRolesUnmoved() internal view {
        assertTrue(orchestratorRoles().hasRole(bytes32(0), zerogTimelock()), "the timelock is the admin");
        assertFalse(orchestratorRoles().hasRole(bytes32(0), address(zerogSafe())), "the Safe is not the admin");
        assertTrue(orchestratorRoles().hasRole(ORCHESTRATOR_EMERGENCY_ROLE, address(zerogSafe())), "Safe EMERGENCY");
        LibZerogOrchestratorRoles.assertGranted();
    }

    /// After the 0G orchestrator roles batch executes, the bundle is exactly the record, and landing it moves no role.
    function testZerogBundleIsExactlyTheRecordAfterTheRolesBatch() external {
        assertRolesUnmoved();
        SafeTx[] memory txs = sScript.callAuthorBundle();
        SafeTx memory record = LibStoxMigrations.recordTx(declared());
        assertEq(txs.length, 1, "one transaction");
        assertEq(txs[0].to, record.to, "registry");
        assertEq(txs[0].value, 0, "value");
        assertEq(txs[0].data, record.data, "record calldata");
        assertEq(uint8(txs[0].operation), uint8(Enum.Operation.Call), "operation");

        sScript.callPreflight();
        executeBundle();
        sScript.callAssertPostState();
        assertEq(LibStoxMigrations.head(), declaredId(), "recorded");
        assertRolesUnmoved();
    }

    function grantTheSafeAdmin() internal {
        vm.prank(zerogTimelock());
        orchestratorRoles().grantRole(bytes32(0), address(zerogSafe()));
    }

    function expectSafeAdminRefused() internal {
        vm.expectRevert(abi.encodeWithSelector(RoleHeld.selector, bytes32(0), address(zerogSafe())));
    }

    function testZerogPreflightRefusesTheSafeAsAdmin() external {
        grantTheSafeAdmin();
        expectSafeAdminRefused();
        sScript.callPreflight();
    }

    function testZerogPostStateRefusesTheSafeAsAdmin() external {
        executeBundle();
        grantTheSafeAdmin();
        expectSafeAdminRefused();
        sScript.callAssertPostState();
    }

    function renounceTheTimelocksAdmin() internal {
        vm.prank(zerogTimelock());
        orchestratorRoles().renounceRole(bytes32(0), zerogTimelock());
    }

    function expectTimelockWithoutAdminRefused() internal {
        vm.expectRevert(abi.encodeWithSelector(RoleNotHeld.selector, bytes32(0), zerogTimelock()));
    }

    function testZerogPreflightRefusesTheTimelockWithoutAdmin() external {
        renounceTheTimelocksAdmin();
        expectTimelockWithoutAdminRefused();
        sScript.callPreflight();
    }

    function testZerogPostStateRefusesTheTimelockWithoutAdmin() external {
        executeBundle();
        renounceTheTimelocksAdmin();
        expectTimelockWithoutAdminRefused();
        sScript.callAssertPostState();
    }

    /// The line at the bind with the 0G orchestrator roles batch scheduled but not executed: the execution's record and
    /// the bind's written by the Safe.
    function landTheOntoBeforeTheRolesBatchExecutes() internal {
        forkZerogAtTheTokenRecord();
        landZerogLineThrough(LibStoxMigrations.SCHEDULE_ZEROG_ORCHESTRATOR_ROLES);
        LibTestRootLine.write(
            vm,
            address(zerogSafe()),
            LibStoxMigrations.EXECUTE_ZEROG_ORCHESTRATOR_ROLES,
            LibStoxMigrations.SCHEDULE_ZEROG_ORCHESTRATOR_ROLES
        );
        LibTestRootLine.write(
            vm,
            address(zerogSafe()),
            LibStoxMigrations.BIND_BEACON_INITIAL_OWNER,
            LibStoxMigrations.EXECUTE_ZEROG_ORCHESTRATOR_ROLES
        );
        LibZerogOrchestratorRoles.assertNoneGranted();
        sScript = newScript();
    }

    function expectSafeWithoutEmergencyRefused() internal {
        vm.expectRevert(abi.encodeWithSelector(RoleNotHeld.selector, ORCHESTRATOR_EMERGENCY_ROLE, address(zerogSafe())));
    }

    function testZerogPreflightRefusesTheSafeWithoutEmergencyBeforeTheRolesBatchExecutes() external {
        landTheOntoBeforeTheRolesBatchExecutes();
        expectSafeWithoutEmergencyRefused();
        sScript.callPreflight();
    }

    function testZerogPostStateRefusesTheSafeWithoutEmergencyBeforeTheRolesBatchExecutes() external {
        landTheOntoBeforeTheRolesBatchExecutes();
        executeBundle();
        expectSafeWithoutEmergencyRefused();
        sScript.callAssertPostState();
    }
}

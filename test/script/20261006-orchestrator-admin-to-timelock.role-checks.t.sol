// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";

import {RoleNotHeld} from "../../script/20261006-orchestrator-admin-to-timelock.s.sol";
import {LocalBaseOrchestratorFixture} from "./LocalBaseOrchestratorFixture.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {IRecordScriptHooks, RootLineRecordScriptTest} from "../lib/RootLineRecordScriptTest.sol";
import {IST0xOrchestratorV1} from "../../src/interface/deprecated/IST0xOrchestratorV1.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";

/// @title OrchestratorAdminToTimelockLocalTest
/// @notice The move on a local Base whose root line is at the V5 backfill, so
/// it runs whatever the live chains have recorded.
contract OrchestratorAdminToTimelockLocalTest is LocalBaseOrchestratorFixture, RootLineRecordScriptTest {
    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new OrchestratorAdminToTimelockHarness("local")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5;
    }

    function landBeforeOnto() internal override {
        buildLocalBase();
        LibTestRootLine.approve(vm, address(safe));
        bytes32 emergency = ORCHESTRATOR.EMERGENCY_ROLE();
        vm.prank(address(safe));
        ORCHESTRATOR.grantRole(emergency, address(safe));
    }

    function landOnto() internal override {
        LibTestRootLine.write(
            vm, address(safe), LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5, MIGRATION_HEAD_GENESIS
        );
    }

    function testExecutedMoveHandsAdminToTheTimelock() external {
        executeBundle();
        assertTrue(ORCHESTRATOR.hasRole(bytes32(0), timelock));
        assertFalse(ORCHESTRATOR.hasRole(bytes32(0), address(safe)));
    }

    function testPreflightRefusesSafeWithoutEmergency() external {
        bytes32 emergency = ORCHESTRATOR.EMERGENCY_ROLE();
        sScript.callPreflight();
        vm.mockCall(
            address(ORCHESTRATOR), abi.encodeCall(IAccessControl.hasRole, (emergency, address(safe))), abi.encode(false)
        );
        vm.expectRevert(abi.encodeWithSelector(RoleNotHeld.selector, emergency, address(safe)));
        sScript.callPreflight();
    }

    function testPostStateRefusesMissingRole() external {
        executeBundle();
        sScript.callAssertPostState();

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
            sScript.callAssertPostState();
        }
    }
}

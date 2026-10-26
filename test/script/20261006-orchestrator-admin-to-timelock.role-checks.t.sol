// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {LibSafeFork} from "rain-deploy-0.1.22/src/lib/LibSafeFork.sol";

import {
    EmergencyNotGranted,
    RoleNotHeld,
    orchestratorAdminToTimelockDeclaration
} from "../../script/20261006-orchestrator-admin-to-timelock.s.sol";
import {LocalBaseOrchestratorFixture} from "./LocalBaseOrchestratorFixture.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {IST0xOrchestratorV1} from "../../src/interface/deprecated/IST0xOrchestratorV1.sol";
import {LibMigrationLineFork} from "../lib/LibMigrationLineFork.sol";

/// @title OrchestratorAdminToTimelockLocalTest
/// @notice The move's role checks on a local Base whose root line is at
/// the emergency grant, with the Safe approved to write it and holding `EMERGENCY_ROLE`,
/// so they run whatever the live chains have recorded.
contract OrchestratorAdminToTimelockLocalTest is LocalBaseOrchestratorFixture {
    OrchestratorAdminToTimelockHarness internal script;

    function setUp() external {
        buildLocalBase();
        bytes32 emergency = ORCHESTRATOR.EMERGENCY_ROLE();
        vm.prank(address(safe));
        ORCHESTRATOR.grantRole(emergency, address(safe));
        LibMigrationLineFork.approve(vm, address(safe));
        LibMigrationLineFork.recordOnto(vm, orchestratorAdminToTimelockDeclaration());
        script = new OrchestratorAdminToTimelockHarness("local");
    }

    function testPreflightRefusesSafeWithoutEmergency() external {
        bytes32 emergency = ORCHESTRATOR.EMERGENCY_ROLE();
        script.callPreflight();
        vm.mockCall(
            address(ORCHESTRATOR), abi.encodeCall(IAccessControl.hasRole, (emergency, address(safe))), abi.encode(false)
        );
        vm.expectRevert(abi.encodeWithSelector(EmergencyNotGranted.selector));
        script.callPreflight();
    }

    function testPostStateRefusesMissingRole() external {
        LibSafeFork.executeBundle(vm, safe, script.callAuthorBundle());
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

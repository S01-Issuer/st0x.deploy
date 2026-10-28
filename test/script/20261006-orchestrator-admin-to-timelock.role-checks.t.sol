// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeTx} from "rain-deploy-0.1.25/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.25/src/lib/LibSafeFork.sol";

import {RoleNotHeld} from "../../script/20261006-orchestrator-admin-to-timelock.s.sol";
import {backfillMigrationRegistryV3Declaration} from "../../script/20261022-backfill-migration-registry-v3.s.sol";
import {GrantOrchestratorEmergencyHarness} from "./GrantOrchestratorEmergencyHarness.sol";
import {LocalBaseOrchestratorFixture} from "./LocalBaseOrchestratorFixture.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {IST0xOrchestratorV1} from "../../src/interface/deprecated/IST0xOrchestratorV1.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";

/// @title OrchestratorAdminToTimelockLocalTest
/// @notice The move's role checks on a local Base whose Safe line is at the
/// V3 backfill, so they run whatever the live chains have recorded.
contract OrchestratorAdminToTimelockLocalTest is LocalBaseOrchestratorFixture {
    OrchestratorAdminToTimelockHarness internal script;

    function setUp() external {
        buildLocalBase();
        LibSafeFork.executeBundle(vm, safe, new GrantOrchestratorEmergencyHarness().callAuthorBundle());
        (address recordTo, bytes memory recordData) =
            LibStoxMigrations.recordCall(backfillMigrationRegistryV3Declaration(), address(safe), timelock);
        SafeTx[] memory backfill = new SafeTx[](1);
        backfill[0] = SafeTx({to: recordTo, value: 0, data: recordData, operation: Enum.Operation.Call});
        LibSafeFork.executeBundle(vm, safe, backfill);
        script = new OrchestratorAdminToTimelockHarness("local");
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

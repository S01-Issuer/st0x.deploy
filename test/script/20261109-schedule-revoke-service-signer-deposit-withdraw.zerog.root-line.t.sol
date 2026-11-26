// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";

import {TimelockLacksAdminRole} from "../../script/20261109-schedule-revoke-service-signer-deposit-withdraw.s.sol";
import {RevokeBatchPending, ServiceSignerStillHoldsRole} from "../../src/lib/LibServiceSignerRevoke.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {IRecordScriptHooks} from "../lib/RootLineRecordScriptTest.sol";
import {
    ScheduleRevokeServiceSignerDepositWithdrawHarness
} from "./ScheduleRevokeServiceSignerDepositWithdrawHarness.sol";
import {ZerogServiceSignerState} from "./ZerogServiceSignerState.sol";

/// @title ScheduleRevokeServiceSignerDepositWithdrawZerogRootLineTest
/// @notice The revoke's schedule on 0G, onto the naming's stand-in records: the record alone, since 0G's US authoriser
/// never granted the service signer `DEPOSIT` or `WITHDRAW`.
contract ScheduleRevokeServiceSignerDepositWithdrawZerogRootLineTest is ZerogServiceSignerState {
    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new ScheduleRevokeServiceSignerDepositWithdrawHarness("zerog-root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.SCHEDULE_REVOKE_SERVICE_SIGNER;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.EXECUTE_UNDERLYING_NAMING;
    }

    function testZerogPreflightRefusesAScheduledRevoke() external {
        scheduleRevoke();
        vm.expectRevert(abi.encodeWithSelector(RevokeBatchPending.selector, revokeId()));
        sScript.callPreflight();
    }

    function testZerogPreflightRefusesATimelockWithoutEitherAdmin(bool deposit) external {
        bytes32 admin = deposit ? keccak256("DEPOSIT_ADMIN") : keccak256("WITHDRAW_ADMIN");
        vm.prank(zerogTimelock());
        IAccessControl(usAuthoriser()).renounceRole(admin, zerogTimelock());
        vm.expectRevert(abi.encodeWithSelector(TimelockLacksAdminRole.selector, zerogTimelock(), admin));
        sScript.callPreflight();
    }

    function testZerogPostStateRefusesASignerWithEitherRole(bool deposit) external {
        executeBundle();
        bytes32 role = grantSigner(deposit);
        vm.expectRevert(abi.encodeWithSelector(ServiceSignerStillHoldsRole.selector, role));
        sScript.callAssertPostState();
    }

    function testZerogPostStateRefusesAScheduledRevoke() external {
        executeBundle();
        scheduleRevoke();
        vm.expectRevert(abi.encodeWithSelector(RevokeBatchPending.selector, revokeId()));
        sScript.callAssertPostState();
    }
}

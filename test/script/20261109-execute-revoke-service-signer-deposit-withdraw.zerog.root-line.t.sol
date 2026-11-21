// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {
    ExecuteRevokeServiceSignerDepositWithdraw,
    ExecuteRevokeServiceSignerRecorded,
    RevokeOperationNotReady,
    ZerogRevokeScheduled
} from "../../script/20261109-execute-revoke-service-signer-deposit-withdraw.s.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {IRecordScriptHooks} from "../lib/RootLineRecordScriptTest.sol";
import {ExecuteRevokeServiceSignerDepositWithdrawHarness} from "./ExecuteRevokeServiceSignerDepositWithdrawHarness.sol";
import {ZerogServiceSignerState} from "./ZerogServiceSignerState.sol";

/// @title ExecuteRevokeServiceSignerDepositWithdrawZerogRootLineTest
/// @notice The revoke's execution record on 0G, onto the schedule's 0G record: no batch exists, so `execute()` refuses
/// and the record lands once the service signer holds neither role.
contract ExecuteRevokeServiceSignerDepositWithdrawZerogRootLineTest is ZerogServiceSignerState {
    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new ExecuteRevokeServiceSignerDepositWithdrawHarness("zerog-root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.EXECUTE_REVOKE_SERVICE_SIGNER;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.SCHEDULE_REVOKE_SERVICE_SIGNER;
    }

    function ownRecordPreflightRefusal() internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(ExecuteRevokeServiceSignerRecorded.selector, declaredId());
    }

    function testZerogPreflightRefusesAScheduledRevoke() external {
        scheduleRevoke();
        vm.expectRevert(abi.encodeWithSelector(ZerogRevokeScheduled.selector, revokeId()));
        sScript.callPreflight();
    }

    function testZerogExecuteRefusesWithNothingScheduled() external {
        ExecuteRevokeServiceSignerDepositWithdraw execution = new ExecuteRevokeServiceSignerDepositWithdraw();
        vm.expectRevert(abi.encodeWithSelector(RevokeOperationNotReady.selector, revokeId(), false, false));
        execution.execute();
    }
}

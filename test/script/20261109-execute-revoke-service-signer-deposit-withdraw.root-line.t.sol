// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";

import {
    ExecuteRevokeServiceSignerDepositWithdraw,
    ExecuteRevokeServiceSignerRecorded
} from "../../script/20261109-execute-revoke-service-signer-deposit-withdraw.s.sol";
import {ExecuteRevokeServiceSignerDepositWithdrawHarness} from "./ExecuteRevokeServiceSignerDepositWithdrawHarness.sol";
import {RevokeServiceSignerDepositWithdrawFixture} from "./RevokeServiceSignerDepositWithdrawFixture.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {IRecordScriptHooks, RootLineRecordScriptTest} from "../lib/RootLineRecordScriptTest.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @title ExecuteRevokeServiceSignerDepositWithdrawRootLineTest
/// @notice The revoke's execution record on Base, from the batch executed with
/// its schedule record not yet landed.
contract ExecuteRevokeServiceSignerDepositWithdrawRootLineTest is
    RevokeServiceSignerDepositWithdrawFixture,
    RootLineRecordScriptTest
{
    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new ExecuteRevokeServiceSignerDepositWithdrawHarness("root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.EXECUTE_REVOKE_SERVICE_SIGNER;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.SCHEDULE_REVOKE_SERVICE_SIGNER;
    }

    function landBeforeOnto() internal override {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        advanceRootLineToRevokeSchedule();
        scheduleRevokeBatch();
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        new ExecuteRevokeServiceSignerDepositWithdraw().execute();
    }

    function landOnto() internal override {
        LibTestRootLine.write(
            vm,
            safeAddress(),
            LibStoxMigrations.SCHEDULE_REVOKE_SERVICE_SIGNER,
            LibStoxMigrations.EXECUTE_UNDERLYING_NAMING
        );
    }

    function ownRecordPreflightRefusal() internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(ExecuteRevokeServiceSignerRecorded.selector, declaredId());
    }

    function testBundleIsTheRecordOnly() external view {
        assertEq(sScript.callAuthorBundle().length, 1, "record only");
    }

    function testPreflightRefusesOnceRecorded() external {
        executeBundle();
        vm.expectRevert(
            abi.encodeWithSelector(
                ExecuteRevokeServiceSignerRecorded.selector, LibStoxMigrations.EXECUTE_REVOKE_SERVICE_SIGNER
            )
        );
        sScript.callPreflight();
    }
}

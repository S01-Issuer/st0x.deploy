// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {OwnerManager} from "safe-global-safe-smart-account-1.4.1-3/contracts/base/OwnerManager.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {LibSafe} from "rain-deploy-0.1.30/src/lib/LibSafe.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {
    ScheduleRevokeServiceSignerDepositWithdrawHarness
} from "./ScheduleRevokeServiceSignerDepositWithdrawHarness.sol";
import {RevokeServiceSignerDepositWithdrawFixture} from "./RevokeServiceSignerDepositWithdrawFixture.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";
import {IRecordScriptHooks, RootLineRecordScriptTest} from "../lib/RootLineRecordScriptTest.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibServiceSignerRevoke} from "../../src/lib/LibServiceSignerRevoke.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @title ScheduleRevokeServiceSignerDepositWithdrawRootLineTest
/// @notice The revoke schedule on Base, from the line at the naming execution's
/// onto.
contract ScheduleRevokeServiceSignerDepositWithdrawRootLineTest is
    RevokeServiceSignerDepositWithdrawFixture,
    RootLineRecordScriptTest
{
    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new ScheduleRevokeServiceSignerDepositWithdrawHarness("root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.SCHEDULE_REVOKE_SERVICE_SIGNER;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.EXECUTE_UNDERLYING_NAMING;
    }

    function landBeforeOnto() internal override {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        advanceRootLineToNamingExecution();
    }

    function landOnto() internal override {
        landNamingExecutionRecord();
    }

    /// @dev Past the delay the post-state refuses the ready operation before the record.
    function latestRecordAge() internal pure override returns (uint256) {
        return LibTimelockInvariants.TIMELOCK_MIN_DELAY - 1;
    }

    function testBundleIsTheScheduleThenTheRecord() external view {
        SafeTx[] memory txs = sScript.callAuthorBundle();
        assertEq(txs.length, 2, "schedule then record");
        assertEq(txs[0].to, LibTimelockInvariants.timelockForChainId(block.chainid), "schedule target");
        assertEq(txs[0].value, 0, "schedule value");
        assertEq(txs[0].data, LibServiceSignerRevoke.scheduleCalldata(block.chainid), "schedule calldata");
        assertEq(uint8(txs[0].operation), uint8(Enum.Operation.Call), "schedule operation");
    }

    function testPreflightRefusesASafeOffPolicy() external {
        vm.mockCall(safeAddress(), abi.encodeCall(OwnerManager.getThreshold, ()), abi.encode(uint256(1)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeThresholdMismatch.selector,
                safeAddress(),
                LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD,
                1
            )
        );
        sScript.callPreflight();
    }
}

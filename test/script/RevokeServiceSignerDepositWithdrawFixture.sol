// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";

import {executeBeaconUpgradeDeclaration} from "../../script/20261021-execute-beacon-upgrade.s.sol";
import {scheduleBeaconUpgradeDeclaration} from "../../script/20261021-schedule-beacon-upgrade.s.sol";
import {
    scheduleRevokeServiceSignerDeclaration
} from "../../script/20261109-schedule-revoke-service-signer-deposit-withdraw.s.sol";
import {
    ScheduleRevokeServiceSignerDepositWithdrawHarness
} from "./ScheduleRevokeServiceSignerDepositWithdrawHarness.sol";
import {BeaconUpgradeFixture} from "./BeaconUpgradeFixture.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @title RevokeServiceSignerDepositWithdrawFixture
/// @notice Brings a forked deployment network to the service-signer revoke's
/// onto. The beacon upgrade records are written without their effects, which touch no
/// authoriser role.
abstract contract RevokeServiceSignerDepositWithdrawFixture is BeaconUpgradeFixture {
    function writeRecord(ScriptDeclaration memory declared) internal {
        LibTestRootLine.write(vm, LibSafeInvariants.safeForChainId(block.chainid), declared.id, declared.onto);
    }

    function writeTimelockRecord(ScriptDeclaration memory declared) internal {
        LibTestRootLine.write(vm, LibTimelockInvariants.timelockForChainId(block.chainid), declared.id, declared.onto);
    }

    /// @notice Lands the root line up to the beacon upgrade execution's onto: the
    /// beacon batch's record, as the timelock.
    function advanceRootLineToBeaconUpgradeExecution() internal {
        advanceRootLineToBeaconSchedule();
        writeTimelockRecord(scheduleBeaconUpgradeDeclaration());
    }

    function landBeaconUpgradeExecutionRecord() internal {
        writeRecord(executeBeaconUpgradeDeclaration());
    }

    /// @notice Lands the root line up to the revoke schedule's onto.
    function advanceRootLineToRevokeSchedule() internal {
        advanceRootLineToBeaconUpgradeExecution();
        landBeaconUpgradeExecutionRecord();
        assertEq(LibStoxMigrations.head(), scheduleRevokeServiceSignerDeclaration().onto, "line at the revoke onto");
    }

    /// @notice Lands the schedule bundle's batch without its record.
    function scheduleRevokeBatch() internal {
        executePrefix(new ScheduleRevokeServiceSignerDepositWithdrawHarness("schedule-batch").callAuthorBundle(), 1);
    }

    function serviceSignerHolds(bytes32 role) internal view returns (bool) {
        return IAccessControl(LibAuthoriserInvariants.authoriserForChainId(block.chainid))
            .hasRole(role, LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C);
    }
}

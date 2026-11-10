// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";

import {executeUnderlyingNamingDeclaration} from "../../script/20261021-execute-underlying-naming.s.sol";
import {
    scheduleUnderlyingNamingBeaconsDeclaration
} from "../../script/20261021-schedule-underlying-naming-beacons.s.sol";
import {scheduleUnderlyingNamingRenameDeclaration} from "../../script/20261021-schedule-underlying-naming-rename.s.sol";
import {
    scheduleRevokeServiceSignerDeclaration
} from "../../script/20261109-schedule-revoke-service-signer-deposit-withdraw.s.sol";
import {
    ScheduleRevokeServiceSignerDepositWithdrawHarness
} from "./ScheduleRevokeServiceSignerDepositWithdrawHarness.sol";
import {UnderlyingNamingRolloutFixture} from "./UnderlyingNamingRolloutFixture.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";

/// @title RevokeServiceSignerDepositWithdrawFixture
/// @notice Brings a forked deployment network to the service-signer revoke's
/// onto. The naming records are written without their effects, which touch no
/// authoriser role.
abstract contract RevokeServiceSignerDepositWithdrawFixture is UnderlyingNamingRolloutFixture {
    function writeRecord(ScriptDeclaration memory declared) internal {
        LibTestRootLine.write(vm, LibSafeInvariants.safeForChainId(block.chainid), declared.id, declared.onto);
    }

    /// @notice Lands the root line up to the naming execution's onto.
    function advanceRootLineToNamingExecution() internal {
        advanceRootLineToBeaconSchedule();
        writeRecord(scheduleUnderlyingNamingBeaconsDeclaration());
        writeRecord(scheduleUnderlyingNamingRenameDeclaration());
    }

    function landNamingExecutionRecord() internal {
        writeRecord(executeUnderlyingNamingDeclaration());
    }

    /// @notice Lands the root line up to the revoke schedule's onto.
    function advanceRootLineToRevokeSchedule() internal {
        advanceRootLineToNamingExecution();
        landNamingExecutionRecord();
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

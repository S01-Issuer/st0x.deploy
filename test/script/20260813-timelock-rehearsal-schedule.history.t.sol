// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    TimelockRehearsalSchedule,
    RehearsalScheduleNotHistory,
    RehearsalScheduleRecordedByBackfill
} from "../../script/20260813-timelock-rehearsal-schedule.s.sol";
import {BackfilledHistoryScriptTest} from "../lib/BackfilledHistoryScriptTest.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";

contract TimelockRehearsalScheduleHistoryTest is BackfilledHistoryScriptTest {
    function newHistoryScript() internal override returns (address) {
        return address(new TimelockRehearsalSchedule());
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.TIMELOCK_REHEARSAL_SCHEDULE;
    }

    function declaredOnto(uint256 chainId) internal pure override returns (bytes32) {
        return chainId == LibSafeInvariants.BASE_CHAIN_ID
            ? LibStoxMigrations.MULTISIG_THRESHOLD
            : LibStoxMigrations.ORCHESTRATOR_EMERGENCY;
    }

    function declaredHistory(uint256 chainId) internal pure override returns (bool) {
        return chainId == LibSafeInvariants.BASE_CHAIN_ID;
    }

    function ranOn(uint256 chainId) internal pure override returns (bool) {
        return chainId == LibSafeInvariants.BASE_CHAIN_ID;
    }

    function executedAtRefusal(uint256 chainId) internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(RehearsalScheduleNotHistory.selector, chainId);
    }

    function runRefusal(uint256 chainId) internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(RehearsalScheduleRecordedByBackfill.selector, chainId);
    }
}

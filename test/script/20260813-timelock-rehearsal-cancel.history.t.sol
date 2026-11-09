// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    TimelockRehearsalCancel,
    RehearsalCancelNotHistory,
    RehearsalCancelRecordedByBackfill
} from "../../script/20260813-timelock-rehearsal-cancel.s.sol";
import {BackfilledHistoryScriptTest} from "../lib/BackfilledHistoryScriptTest.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";

contract TimelockRehearsalCancelHistoryTest is BackfilledHistoryScriptTest {
    function newHistoryScript() internal override returns (address) {
        return address(new TimelockRehearsalCancel());
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.TIMELOCK_REHEARSAL_CANCEL;
    }

    function declaredOnto(uint256) internal pure override returns (bytes32) {
        return LibStoxMigrations.TIMELOCK_REHEARSAL_SCHEDULE;
    }

    function declaredHistory(uint256 chainId) internal pure override returns (bool) {
        return chainId == LibSafeInvariants.BASE_CHAIN_ID;
    }

    function ranOn(uint256 chainId) internal pure override returns (bool) {
        return chainId == LibSafeInvariants.BASE_CHAIN_ID;
    }

    function executedAtRefusal(uint256 chainId) internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(RehearsalCancelNotHistory.selector, chainId);
    }

    function runRefusal(uint256 chainId) internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(RehearsalCancelRecordedByBackfill.selector, chainId);
    }
}

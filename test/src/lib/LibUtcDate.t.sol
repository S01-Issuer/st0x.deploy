// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibUtcDate} from "../../../src/lib/LibUtcDate.sol";

contract LibUtcDateTest is Test {
    function testDaysFromCivilKnownDates() external pure {
        assertEq(LibUtcDate.daysFromCivil(1970, 1, 1), 0);
        assertEq(LibUtcDate.daysFromCivil(2000, 3, 1), 11017);
        assertEq(LibUtcDate.daysFromCivil(2027, 10, 15) * 86400, 1823558400);
    }

    /// @notice sft-ops: `addYearsUtc(new Date('2026-08-14T22:01:41.703Z'), 1)`
    /// is `2027-08-14`.
    function testAddYearsUtcDropsTheTimeOfDay() external pure {
        uint256 ts = 1786744901;
        assertEq(LibUtcDate.toIsoDate(ts), "2026-08-14");
        assertEq(LibUtcDate.toIsoDate(LibUtcDate.addYearsUtc(ts, 1)), "2027-08-14");
        assertEq(LibUtcDate.addYearsUtc(ts, 1) % 86400, 0);
    }

    /// @notice `Date.UTC(2029, 1, 29)` is 1 March 2029.
    function testAddYearsUtcRollsLeapDayToMarchFirst() external pure {
        uint256 leapDay = LibUtcDate.daysFromCivil(2028, 2, 29) * 86400 + 3600;
        assertEq(LibUtcDate.toIsoDate(LibUtcDate.addYearsUtc(leapDay, 1)), "2029-03-01");
        assertEq(LibUtcDate.toIsoDate(LibUtcDate.addYearsUtc(leapDay, 4)), "2032-02-29");
    }

    function testIsLeapYear() external pure {
        assertTrue(LibUtcDate.isLeapYear(2000));
        assertTrue(LibUtcDate.isLeapYear(2028));
        assertFalse(LibUtcDate.isLeapYear(1900));
        assertFalse(LibUtcDate.isLeapYear(2027));
    }

    function testToIsoDateTimeMsMatchesJavaScript() external pure {
        assertEq(LibUtcDate.toIsoDateTimeMs(1792079467450), "2026-10-15T15:51:07.450Z");
        assertEq(LibUtcDate.toIsoDateTimeMs(1823558400000), "2027-10-15T00:00:00.000Z");
        assertEq(LibUtcDate.toIsoDateTimeMs(5), "1970-01-01T00:00:00.005Z");
    }

    function testCivilRoundTrip(uint32 daysSinceEpoch) external pure {
        (uint256 y, uint256 m, uint256 d) = LibUtcDate.civilFromDays(daysSinceEpoch);
        assertEq(LibUtcDate.daysFromCivil(y, m, d), daysSinceEpoch);
        assertGe(m, 1);
        assertLe(m, 12);
        assertGe(d, 1);
        assertLe(d, 31);
    }

    /// @notice Consecutive days are consecutive dates.
    function testCivilFromDaysAdvancesOneDay(uint32 daysSinceEpoch) external pure {
        (uint256 y0, uint256 m0, uint256 d0) = LibUtcDate.civilFromDays(daysSinceEpoch);
        (uint256 y1, uint256 m1, uint256 d1) = LibUtcDate.civilFromDays(uint256(daysSinceEpoch) + 1);
        if (d1 == 1) {
            assertTrue(m1 == m0 + 1 || (m0 == 12 && m1 == 1 && y1 == y0 + 1));
        } else {
            assertEq(d1, d0 + 1);
            assertEq(m1, m0);
            assertEq(y1, y0);
        }
    }

    function testAddYearsUtcPreservesEveryNonLeapDay() external pure {
        uint8[12] memory monthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
        uint256 sourceDay = 1767225600;
        uint256 expectedDay = 1798761600;
        for (uint256 month = 0; month < monthDays.length; month++) {
            for (uint256 day = 0; day < monthDays[month]; day++) {
                assertEq(LibUtcDate.addYearsUtc(sourceDay + 43200, 1), expectedDay);
                sourceDay += 86400;
                expectedDay += 86400;
            }
        }
        assertEq(LibUtcDate.addYearsUtc(1835308800, 1), 1866931200);
    }
}

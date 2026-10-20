// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Strings} from "@openzeppelin-contracts-5.7.0/utils/Strings.sol";

/// @title LibUtcDate
/// @notice Proleptic Gregorian UTC calendar arithmetic over unix seconds, for
/// the dates the token launch writes on chain and into its ledger. Uses Howard
/// Hinnant's `days_from_civil` / `civil_from_days`, valid for every date from
/// 1970-01-01 on.
library LibUtcDate {
    uint256 internal constant SECONDS_PER_DAY = 86400;

    // The algorithm truncates on purpose: each division takes a whole number
    // of eras, years or months.
    // slither-disable-start divide-before-multiply
    /// @notice Days since 1970-01-01 of the civil date `year-month-day`.
    function daysFromCivil(uint256 year, uint256 month, uint256 day) internal pure returns (uint256) {
        uint256 y = month <= 2 ? year - 1 : year;
        uint256 era = y / 400;
        uint256 yoe = y - era * 400;
        uint256 mp = month > 2 ? month - 3 : month + 9;
        uint256 doy = (153 * mp + 2) / 5 + day - 1;
        uint256 doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        return era * 146097 + doe - 719468;
    }

    /// @notice The civil date of `daysSinceEpoch` days after 1970-01-01.
    function civilFromDays(uint256 daysSinceEpoch) internal pure returns (uint256 year, uint256 month, uint256 day) {
        uint256 z = daysSinceEpoch + 719468;
        uint256 era = z / 146097;
        uint256 doe = z - era * 146097;
        uint256 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        uint256 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        uint256 mp = (5 * doy + 2) / 153;
        day = doy - (153 * mp + 2) / 5 + 1;
        month = mp < 10 ? mp + 3 : mp - 9;
        year = yoe + era * 400 + (month <= 2 ? 1 : 0);
    }
    // slither-disable-end divide-before-multiply

    function isLeapYear(uint256 year) internal pure returns (bool) {
        return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    }

    /// @notice Midnight UTC of the calendar day `yearCount` years after the day
    /// holding `timestamp`, matching JavaScript's
    /// `Date.UTC(y + yearCount, m, d)`: 29 February rolls to 1 March when the
    /// target year is not a leap year.
    function addYearsUtc(uint256 timestamp, uint256 yearCount) internal pure returns (uint256) {
        (uint256 year, uint256 month, uint256 day) = civilFromDays(timestamp / SECONDS_PER_DAY);
        uint256 targetYear = year + yearCount;
        if (month == 2 && day == 29 && !isLeapYear(targetYear)) {
            (month, day) = (3, 1);
        }
        return daysFromCivil(targetYear, month, day) * SECONDS_PER_DAY;
    }

    /// @notice `YYYY-MM-DD` of the UTC day holding `timestamp`.
    function toIsoDate(uint256 timestamp) internal pure returns (string memory) {
        (uint256 year, uint256 month, uint256 day) = civilFromDays(timestamp / SECONDS_PER_DAY);
        return string.concat(_pad(year, 4), "-", _pad(month, 2), "-", _pad(day, 2));
    }

    /// @notice `YYYY-MM-DDTHH:MM:SS.mmmZ`, JavaScript's `Date.toISOString()`,
    /// for a time given in unix milliseconds.
    function toIsoDateTimeMs(uint256 unixMs) internal pure returns (string memory) {
        uint256 secs = unixMs / 1000;
        uint256 secOfDay = secs % SECONDS_PER_DAY;
        return string.concat(
            toIsoDate(secs),
            "T",
            _pad(secOfDay / 3600, 2),
            ":",
            _pad((secOfDay / 60) % 60, 2),
            ":",
            _pad(secOfDay % 60, 2),
            ".",
            _pad(unixMs % 1000, 3),
            "Z"
        );
    }

    function _pad(uint256 value, uint256 width) private pure returns (string memory s) {
        s = Strings.toString(value);
        while (bytes(s).length < width) {
            s = string.concat("0", s);
        }
    }
}

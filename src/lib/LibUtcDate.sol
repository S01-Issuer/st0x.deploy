// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Strings} from "@openzeppelin-contracts-5.7.0/utils/Strings.sol";

/// @title LibUtcDate
/// @notice Proleptic Gregorian UTC calendar arithmetic over unix seconds, for
/// the certification dates of the token launch. Uses Howard
/// Hinnant's `days_from_civil` / `civil_from_days`, valid for every date from
/// 1970-01-01 on.
library LibUtcDate {
    /// @notice Seconds in a UTC day; unix time has no leap seconds.
    uint256 internal constant SECONDS_PER_DAY = 86400;

    // The algorithm truncates on purpose: each division takes a whole number
    // of eras, years or months.
    // slither-disable-start divide-before-multiply
    // forge-lint: disable-start(divide-before-multiply)
    /// @notice Days since 1970-01-01 of the civil date `year-month-day`. The
    /// year is counted from 1 March, so day 29 of February in a non-leap year
    /// is 1 March.
    /// @param year The civil year, 1970 or later.
    /// @param month The month, 1 to 12.
    /// @param day The day of the month, from 1.
    /// @return The day count since 1970-01-01.
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
    /// @param daysSinceEpoch The day count since 1970-01-01.
    /// @return year The civil year.
    /// @return month The month, 1 to 12.
    /// @return day The day of the month, from 1.
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

    // forge-lint: disable-end(divide-before-multiply)
    // slither-disable-end divide-before-multiply

    /// @notice Midnight UTC of the calendar day `yearCount` years after the day
    /// holding `timestamp`, matching JavaScript's
    /// `Date.UTC(y + yearCount, m, d)`: 29 February rolls to 1 March when the
    /// target year is not a leap year, as `daysFromCivil` counts it.
    /// @param timestamp Unix seconds.
    /// @param yearCount Whole years to add.
    /// @return Unix seconds at midnight UTC of the target day.
    function addYearsUtc(uint256 timestamp, uint256 yearCount) internal pure returns (uint256) {
        (uint256 year, uint256 month, uint256 day) = civilFromDays(timestamp / SECONDS_PER_DAY);
        return daysFromCivil(year + yearCount, month, day) * SECONDS_PER_DAY;
    }

    /// @notice `YYYY-MM-DD` of the UTC day holding `timestamp`.
    /// @param timestamp Unix seconds.
    /// @return The ISO 8601 date.
    function toIsoDate(uint256 timestamp) internal pure returns (string memory) {
        (uint256 year, uint256 month, uint256 day) = civilFromDays(timestamp / SECONDS_PER_DAY);
        return string.concat(_pad(year, 4), "-", _pad(month, 2), "-", _pad(day, 2));
    }

    function _pad(uint256 value, uint256 width) private pure returns (string memory padded) {
        padded = Strings.toString(value);
        while (bytes(padded).length < width) {
            padded = string.concat("0", padded);
        }
    }
}

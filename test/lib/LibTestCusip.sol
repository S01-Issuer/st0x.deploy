// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {LibSecurity} from "../../src/lib/LibSecurity.sol";

/// @title LibTestCusip
/// @notice CUSIP check digits and the US ISIN of a CUSIP.
library LibTestCusip {
    /// @notice A digit is itself, a letter is 10 to 35.
    function charValue(bytes1 character) internal pure returns (uint256) {
        uint8 code = uint8(character);
        return code >= 0x41 ? code - 0x41 + 10 : code - 0x30;
    }

    /// @notice Whether the 9th character of `cusip` is the check digit of its first 8: every second value doubled,
    /// the digits of each value summed.
    function cusipCheckDigitHolds(bytes memory cusip) internal pure returns (bool) {
        if (cusip.length != 9) return false;
        uint256 sum = 0;
        for (uint256 i = 0; i < 8; i++) {
            uint256 value = charValue(cusip[i]);
            if (i % 2 == 1) value *= 2;
            sum += value / 10 + value % 10;
        }
        return charValue(cusip[8]) == (10 - sum % 10) % 10;
    }

    /// @notice `US`, `cusip`, then the one digit for which `LibSecurity.isinWellFormed` holds.
    function isinOf(string memory cusip) internal pure returns (string memory) {
        for (uint8 digit = 0; digit < 10; digit++) {
            string memory isin = string.concat("US", cusip, string(abi.encodePacked(bytes1(0x30 + digit))));
            if (LibSecurity.isinWellFormed(isin)) return isin;
        }
        revert("no ISIN check digit");
    }
}

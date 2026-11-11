// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

/// @title LibTestIsin
/// @notice The ISIN and CUSIP check digit rules the token table tests share.
library LibTestIsin {
    /// @notice The value of one ISIN or CUSIP character: a digit is itself, a letter is 10 to 35.
    function charValue(bytes1 character) internal pure returns (uint256) {
        uint8 code = uint8(character);
        return code >= 0x41 ? code - 0x41 + 10 : code - 0x30;
    }

    /// @notice Letters become 10 to 35, then the Luhn sum over the digits, check digit included, is a multiple of 10.
    function isinCheckDigitHolds(bytes memory id) internal pure returns (bool) {
        uint256[] memory digits = new uint256[](id.length * 2);
        uint256 count = 0;
        for (uint256 c = 0; c < id.length; c++) {
            uint256 value = charValue(id[c]);
            if (value >= 10) {
                digits[count++] = value / 10;
            }
            digits[count++] = value % 10;
        }
        uint256 sum = 0;
        for (uint256 k = 0; k < count; k++) {
            uint256 digit = digits[count - 1 - k];
            if (k % 2 == 1) {
                digit *= 2;
                if (digit > 9) digit -= 9;
            }
            sum += digit;
        }
        return sum % 10 == 0;
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

    /// @notice The ISIN of `cusip`: `US`, the CUSIP, then the one digit for which `isinCheckDigitHolds` holds.
    function isinOf(string memory cusip) internal pure returns (string memory) {
        for (uint8 digit = 0; digit < 10; digit++) {
            string memory isin = string.concat("US", cusip, string(abi.encodePacked(bytes1(0x30 + digit))));
            if (isinCheckDigitHolds(bytes(isin))) return isin;
        }
        revert("no ISIN check digit");
    }
}

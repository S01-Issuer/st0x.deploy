// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibUnderlying} from "../../../src/lib/LibUnderlying.sol";

contract LibUnderlyingTest is Test {
    bytes internal constant ALPHANUMERIC = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";

    function isLetter(bytes1 c) internal pure returns (bool) {
        return c >= "A" && c <= "Z";
    }

    function isDigit(bytes1 c) internal pure returns (bool) {
        return c >= "0" && c <= "9";
    }

    /// Expands the prefix left to right into decimal digits, then doubles
    /// every other digit starting from the rightmost.
    function luhnCheckDigit(bytes memory prefix) internal pure returns (bytes1) {
        uint8[] memory digits = new uint8[](prefix.length * 2);
        uint256 count = 0;
        for (uint256 i = 0; i < prefix.length; i++) {
            bytes1 c = prefix[i];
            if (isDigit(c)) {
                digits[count++] = uint8(c) - 48;
            } else {
                uint8 value = uint8(c) - 55;
                digits[count++] = value / 10;
                digits[count++] = value % 10;
            }
        }
        uint256 sum = 0;
        for (uint256 k = 0; k < count; k++) {
            uint256 digit = digits[count - 1 - k];
            if (k % 2 == 0) {
                digit = digit * 2;
                digit = digit / 10 + digit % 10;
            }
            sum += digit;
        }
        return bytes1(uint8(48 + (10 - sum % 10) % 10));
    }

    function withLuhnCheckDigit(bytes memory prefix) internal pure returns (bytes memory) {
        return bytes.concat(prefix, luhnCheckDigit(prefix));
    }

    function oracle(bytes memory isin) internal pure returns (bool) {
        if (isin.length != 12) return false;
        if (!isLetter(isin[0]) || !isLetter(isin[1])) return false;
        for (uint256 i = 2; i < 11; i++) {
            if (!isLetter(isin[i]) && !isDigit(isin[i])) return false;
        }
        if (!isDigit(isin[11])) return false;
        bytes memory prefix = new bytes(11);
        for (uint256 i = 0; i < 11; i++) {
            prefix[i] = isin[i];
        }
        return luhnCheckDigit(prefix) == isin[11];
    }

    function wellFormed(bytes memory isin) internal pure returns (bool) {
        return LibUnderlying.isinWellFormed(string(isin));
    }

    function testIsinAcceptsKnownValidIsins() external pure {
        string[4] memory isins = ["US0378331005", "US88160R1014", "NL0010273215", "US67066G1040"];
        for (uint256 i = 0; i < isins.length; i++) {
            assertTrue(LibUnderlying.isinWellFormed(isins[i]), isins[i]);
            assertTrue(oracle(bytes(isins[i])), isins[i]);
        }
    }

    function testIsinRejectsEveryWrongCheckDigit() external pure {
        string[4] memory isins = ["US0378331005", "US88160R1014", "NL0010273215", "US67066G1040"];
        for (uint256 i = 0; i < isins.length; i++) {
            bytes memory isin = bytes(isins[i]);
            bytes1 correct = isin[11];
            for (uint8 digit = 0; digit < 10; digit++) {
                isin[11] = bytes1(48 + digit);
                assertEq(wellFormed(isin), isin[11] == correct, string(isin));
            }
        }
    }

    /// Each candidate carries a Luhn-valid check digit, so only the length
    /// rule can refuse it.
    function testIsinRejectsEveryLengthOtherThanTwelve() external pure {
        assertFalse(LibUnderlying.isinWellFormed(""));
        assertFalse(LibUnderlying.isinWellFormed("U"));
        assertFalse(LibUnderlying.isinWellFormed("US"));
        for (uint256 length = 3; length <= 64; length++) {
            bytes memory prefix = new bytes(length - 1);
            prefix[0] = "U";
            prefix[1] = "S";
            for (uint256 i = 2; i < prefix.length; i++) {
                prefix[i] = ALPHANUMERIC[(i * 7) % 36];
            }
            bytes memory candidate = withLuhnCheckDigit(prefix);
            assertEq(wellFormed(candidate), length == 12, string(candidate));
        }
    }

    function testIsinRejectsLowercase() external pure {
        assertFalse(LibUnderlying.isinWellFormed("us0378331005"));
        assertFalse(LibUnderlying.isinWellFormed("uS0378331005"));
        assertFalse(LibUnderlying.isinWellFormed("Us0378331005"));
        assertFalse(LibUnderlying.isinWellFormed("nl0010273215"));
        assertFalse(LibUnderlying.isinWellFormed("US88160r1014"));
    }

    /// The candidates carry a Luhn-valid check digit, so only the
    /// country-code rule can refuse them.
    function testIsinRejectsADigitInTheCountryCode() external pure {
        for (uint8 digit = 0; digit < 10; digit++) {
            bytes1 c = bytes1(48 + digit);
            assertFalse(wellFormed(withLuhnCheckDigit(bytes.concat(c, "S037833100"))));
            assertFalse(wellFormed(withLuhnCheckDigit(bytes.concat("U", c, "037833100"))));
            assertFalse(wellFormed(withLuhnCheckDigit(bytes.concat(c, c, "037833100"))));
        }
    }

    /// At least one letter in last place passes the Luhn sum, so the
    /// last-character rule is what refuses it.
    function testIsinRejectsALetterAsTheLastCharacter() external pure {
        bool luhnWouldPass = false;
        for (uint8 letter = 0; letter < 26; letter++) {
            bytes memory candidate = bytes.concat("US037833100", bytes1(65 + letter));
            assertFalse(wellFormed(candidate), string(candidate));
            uint256 value = 10 + letter;
            bytes memory expanded = bytes.concat("US037833100", bytes1(uint8(48 + value / 10)));
            luhnWouldPass = luhnWouldPass || luhnCheckDigit(expanded) == bytes1(uint8(48 + value % 10));
        }
        assertTrue(luhnWouldPass);
    }

    function testIsinRejectsEveryNonAlphanumericByteInEveryPosition() external pure {
        bytes memory valid = "US0378331005";
        for (uint256 position = 0; position < 12; position++) {
            for (uint256 b = 0; b < 256; b++) {
                bytes1 c = bytes1(uint8(b));
                if (isLetter(c) || isDigit(c)) continue;
                bytes memory candidate = bytes.concat(valid);
                candidate[position] = c;
                assertFalse(wellFormed(candidate));
            }
        }
    }

    function testFuzzIsinAgreesWithLuhnOracle(bytes32 seed, bool fixCheckDigit) external pure {
        bytes memory isin = new bytes(12);
        for (uint256 i = 0; i < 12; i++) {
            isin[i] = ALPHANUMERIC[uint8(seed[i]) % 36];
        }
        if (fixCheckDigit) {
            bytes memory prefix = new bytes(11);
            for (uint256 i = 0; i < 11; i++) {
                prefix[i] = isin[i];
            }
            isin[11] = luhnCheckDigit(prefix);
        }
        assertEq(wellFormed(isin), oracle(isin), string(isin));
    }

    function testTickerShape() external pure {
        assertTrue(LibUnderlying.tickerWellFormed("NVDA"));
        assertTrue(LibUnderlying.tickerWellFormed("BRK.B"));
        assertTrue(LibUnderlying.tickerWellFormed("A"));
        assertTrue(LibUnderlying.tickerWellFormed("ABCDEFGHIJKLMNOP"));
        assertFalse(LibUnderlying.tickerWellFormed(""));
        assertFalse(LibUnderlying.tickerWellFormed("ABCDEFGHIJKLMNOPQ"));
        assertFalse(LibUnderlying.tickerWellFormed("tNVDA"));
        assertFalse(LibUnderlying.tickerWellFormed("NV DA"));
        assertFalse(LibUnderlying.tickerWellFormed("NV\"DA"));
        assertFalse(LibUnderlying.tickerWellFormed("NV\\DA"));
    }

    function testNameShape() external pure {
        assertTrue(LibUnderlying.nameWellFormed("NVIDIA Corporation"));
        assertTrue(LibUnderlying.nameWellFormed(bytes(unicode"LVMH Moët Hennessy Louis Vuitton SE")));
        assertTrue(LibUnderlying.nameWellFormed("Meta Platforms, Inc."));
        assertFalse(LibUnderlying.nameWellFormed(""));
        assertFalse(LibUnderlying.nameWellFormed("NVIDIA Corporation ST0x"));
        assertFalse(LibUnderlying.nameWellFormed("NVIDIA Corporation (ST0x)"));
        assertFalse(LibUnderlying.nameWellFormed("NVIDIA \"Corp\""));
        assertFalse(LibUnderlying.nameWellFormed("NVIDIA\\Corp"));
        assertFalse(LibUnderlying.nameWellFormed("NVIDIA\nCorp"));
        assertFalse(LibUnderlying.nameWellFormed(hex"4e56494449417f"));
    }

    /// The boundaries the NatSpec states: digits 0 and 9 are tickers, the
    /// bytes either side are not; a space is the lowest name byte, 0x1f is
    /// not; a name shorter than the suffix is checked without underflow.
    function testShapeBoundaries() external pure {
        assertTrue(LibUnderlying.tickerWellFormed("0"));
        assertTrue(LibUnderlying.tickerWellFormed("9"));
        assertTrue(LibUnderlying.tickerWellFormed("A0Z9."));
        assertFalse(LibUnderlying.tickerWellFormed("/"));
        assertFalse(LibUnderlying.tickerWellFormed(":"));
        assertFalse(LibUnderlying.tickerWellFormed("@"));
        assertFalse(LibUnderlying.tickerWellFormed("["));
        assertTrue(LibUnderlying.nameWellFormed("3M"));
        assertTrue(LibUnderlying.nameWellFormed(" "));
        assertFalse(LibUnderlying.nameWellFormed(hex"1f"));
        assertFalse(LibUnderlying.nameWellFormed("ST0x"));
    }
}

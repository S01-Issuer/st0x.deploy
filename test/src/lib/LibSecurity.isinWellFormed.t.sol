// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console} from "forge-std-1.17.0/src/Test.sol";
import {LibBytes} from "rain-solmem-0.1.28/src/lib/LibBytes.sol";
import {LibMemCpy} from "rain-solmem-0.1.28/src/lib/LibMemCpy.sol";
import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";
import {LibSecurity} from "../../../src/lib/LibSecurity.sol";
import {IsinCrateOracleTest} from "../../lib/IsinCrateOracleTest.sol";
import {GleifIsinLeiRelationshipTest} from "../../lib/GleifIsinLeiRelationshipTest.sol";

/// Expected values and check digits come from the Rust `isin` crate.
contract LibSecurityIsinWellFormedTest is IsinCrateOracleTest {
    bytes internal constant ALPHANUMERIC = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";

    function isLetter(bytes1 c) internal pure returns (bool) {
        return c >= "A" && c <= "Z";
    }

    function isDigit(bytes1 c) internal pure returns (bool) {
        return c >= "0" && c <= "9";
    }

    function wellFormed(bytes memory isin) internal pure returns (bool) {
        return LibSecurity.isinWellFormed(string(isin));
    }

    function wellFormedAgreeingWithCrate(bytes memory isin) internal returns (bool) {
        bool expected = crateValid(isin);
        assertEq(wellFormed(isin), expected, string(isin));
        return expected;
    }

    function withCheckDigit(bytes memory payload) internal returns (bytes memory) {
        return bytes.concat(payload, crateCheckDigit(payload));
    }

    function wellFormedPayload(bytes32 seed) internal pure returns (bytes memory) {
        bytes memory payload = new bytes(11);
        for (uint256 i = 0; i < 11; i++) {
            uint8 r = uint8(seed[i]);
            payload[i] = i < 2 ? bytes1(0x41 + r % 26) : ALPHANUMERIC[r % 36];
        }
        return payload;
    }

    function testIsinAcceptsKnownValidIsins() external {
        string[4] memory isins = ["US0378331005", "US88160R1014", "NL0010273215", "US67066G1040"];
        for (uint256 i = 0; i < isins.length; i++) {
            assertTrue(wellFormedAgreeingWithCrate(bytes(isins[i])), isins[i]);
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
    function testIsinRejectsEveryLengthOtherThanTwelve() external {
        assertFalse(LibSecurity.isinWellFormed(""));
        assertFalse(LibSecurity.isinWellFormed("U"));
        assertFalse(LibSecurity.isinWellFormed("US"));
        for (uint256 length = 3; length <= 64; length++) {
            bytes memory prefix = new bytes(length - 1);
            prefix[0] = "U";
            prefix[1] = "S";
            for (uint256 i = 2; i < prefix.length; i++) {
                prefix[i] = ALPHANUMERIC[(i * 7) % 36];
            }
            bytes memory candidate = withCheckDigit(prefix);
            assertEq(wellFormed(candidate), length == 12, string(candidate));
        }
    }

    function testIsinRejectsLowercase() external pure {
        assertFalse(LibSecurity.isinWellFormed("us0378331005"));
        assertFalse(LibSecurity.isinWellFormed("uS0378331005"));
        assertFalse(LibSecurity.isinWellFormed("Us0378331005"));
        assertFalse(LibSecurity.isinWellFormed("nl0010273215"));
        assertFalse(LibSecurity.isinWellFormed("US88160r1014"));
    }

    /// The candidates carry a Luhn-valid check digit, so only the
    /// country-code rule can refuse them.
    function testIsinRejectsADigitInTheCountryCode() external {
        for (uint8 digit = 0; digit < 10; digit++) {
            bytes1 c = bytes1(48 + digit);
            assertFalse(wellFormed(withCheckDigit(bytes.concat(c, "S037833100"))));
            assertFalse(wellFormed(withCheckDigit(bytes.concat("U", c, "037833100"))));
            assertFalse(wellFormed(withCheckDigit(bytes.concat(c, c, "037833100"))));
        }
    }

    /// At least one letter in last place passes the Luhn sum, so the
    /// last-character rule is what refuses it.
    function testIsinRejectsALetterAsTheLastCharacter() external {
        bool luhnWouldPass = false;
        for (uint8 letter = 0; letter < 26; letter++) {
            bytes memory candidate = bytes.concat("US037833100", bytes1(65 + letter));
            assertFalse(wellFormed(candidate), string(candidate));
            uint256 value = 10 + letter;
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes memory expanded = bytes.concat("US037833100", bytes1(uint8(48 + value / 10)));
            // forge-lint: disable-next-line(unsafe-typecast)
            luhnWouldPass = luhnWouldPass || crateCheckDigit(expanded) == bytes1(uint8(48 + value % 10));
        }
        assertTrue(luhnWouldPass);
    }

    function testIsinRejectsEveryNonAlphanumericByteInEveryPosition() external pure {
        bytes memory valid = "US0378331005";
        for (uint256 position = 0; position < 12; position++) {
            for (uint256 b = 0; b < 256; b++) {
                // forge-lint: disable-next-line(unsafe-typecast)
                bytes1 c = bytes1(uint8(b));
                if (isLetter(c) || isDigit(c)) continue;
                bytes memory candidate = bytes.concat(valid);
                candidate[position] = c;
                assertFalse(wellFormed(candidate));
            }
        }
    }

    function testFuzzIsinWellFormedOnAnyBytes(bytes memory value) external {
        wellFormedAgreeingWithCrate(value);
    }

    function testFuzzIsinWellFormedOnAnyTwelveBytes(bytes12 value) external {
        wellFormedAgreeingWithCrate(abi.encodePacked(value));
    }

    /// Reaches a digit in the country code and a letter as the check digit.
    function testFuzzIsinWellFormedOnAnyAlphanumerics(bytes32 seed, bool fixCheckDigit) external {
        bytes memory payload = new bytes(11);
        for (uint256 i = 0; i < 11; i++) {
            payload[i] = ALPHANUMERIC[uint8(seed[i]) % 36];
        }
        bytes1 last = fixCheckDigit ? crateCheckDigit(payload) : ALPHANUMERIC[uint8(seed[11]) % 36];
        wellFormedAgreeingWithCrate(bytes.concat(payload, last));
    }

    function testFuzzIsinAcceptsAWellFormedPayloadWithItsCheckDigit(bytes32 seed) external {
        assertTrue(wellFormedAgreeingWithCrate(withCheckDigit(wellFormedPayload(seed))));
    }

    function testFuzzIsinRejectsAWellFormedPayloadWithAWrongCheckDigit(bytes32 seed, uint8 offset) external {
        bytes memory payload = wellFormedPayload(seed);
        uint8 correct = uint8(crateCheckDigit(payload)) - 48;
        bytes1 wrong = bytes1(48 + (correct + 1 + offset % 9) % 10);
        assertFalse(wellFormedAgreeingWithCrate(bytes.concat(payload, wrong)));
    }

    /// Lowers the first letter at least, which `parse_loose` would accept.
    function testFuzzIsinRejectsLowercaseLetters(bytes32 seed, uint16 mask) external {
        bytes memory isin = withCheckDigit(wellFormedPayload(seed));
        mask |= 1;
        for (uint256 i = 0; i < 12; i++) {
            if ((mask >> i) & 1 == 1 && isLetter(isin[i])) {
                isin[i] = bytes1(uint8(isin[i]) | 0x20);
            }
        }
        assertFalse(wellFormedAgreeingWithCrate(isin));
    }
}

contract LibSecurityIsinWellFormedGleifTest is GleifIsinLeiRelationshipTest {
    using LibPointer for Pointer;

    function testIsinAcceptsEveryGleifIsin() external {
        bytes memory isins = gleifIsins();
        uint256 checked = 0;
        uint256 rejected = 0;
        for (uint256 start = 0; start < isins.length; checked++) {
            uint256 end = start;
            while (end < isins.length && isins[end] != "\n") end++;
            Pointer freeMemory = LibPointer.allocatedMemoryPointer();
            bytes memory isin = new bytes(end - start);
            LibMemCpy.unsafeCopyBytesTo(
                LibBytes.dataPointer(isins).unsafeAddBytes(start), LibBytes.dataPointer(isin), isin.length
            );
            if (!LibSecurity.isinWellFormed(string(isin))) {
                console.log("rejected", string(isin));
                rejected++;
            }
            assembly ("memory-safe") {
                mstore(0x40, freeMemory)
            }
            start = end + 1;
        }
        console.log("checked", checked, "rejected", rejected);
        assertGt(checked, 1_000_000);
        assertEq(rejected, 0);
    }
}

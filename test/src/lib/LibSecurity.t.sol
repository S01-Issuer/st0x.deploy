// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibSecurity} from "../../../src/lib/LibSecurity.sol";

contract LibSecurityTest is Test {
    function testTickerShape() external pure {
        assertTrue(LibSecurity.tickerWellFormed("NVDA"));
        assertTrue(LibSecurity.tickerWellFormed("BRK.B"));
        assertTrue(LibSecurity.tickerWellFormed("A"));
        assertTrue(LibSecurity.tickerWellFormed("ABCDEFGHIJKLMNOP"));
        assertFalse(LibSecurity.tickerWellFormed(""));
        assertFalse(LibSecurity.tickerWellFormed("ABCDEFGHIJKLMNOPQ"));
        assertFalse(LibSecurity.tickerWellFormed("tNVDA"));
        assertFalse(LibSecurity.tickerWellFormed("NV DA"));
        assertFalse(LibSecurity.tickerWellFormed("NV\"DA"));
        assertFalse(LibSecurity.tickerWellFormed("NV\\DA"));
    }

    function testTickerAcceptsOnlyUpperAlphanumericAndFullStopBytes() external pure {
        for (uint256 b = 0; b < 256; b++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes1 c = bytes1(uint8(b));
            bool expected = (c >= "A" && c <= "Z") || (c >= "0" && c <= "9") || c == ".";
            assertEq(LibSecurity.tickerWellFormed(bytes.concat("NV", c, "DA")), expected);
        }
    }

    function testNameShape() external pure {
        assertTrue(LibSecurity.nameWellFormed("NVIDIA Corporation"));
        assertTrue(LibSecurity.nameWellFormed(bytes(unicode"LVMH Moët Hennessy Louis Vuitton SE")));
        assertTrue(LibSecurity.nameWellFormed("Meta Platforms, Inc."));
        assertFalse(LibSecurity.nameWellFormed(""));
        assertFalse(LibSecurity.nameWellFormed("NVIDIA Corporation ST0x"));
        assertFalse(LibSecurity.nameWellFormed("NVIDIA Corporation (ST0x)"));
        assertFalse(LibSecurity.nameWellFormed("NVIDIA(ST0x)"));
        assertFalse(LibSecurity.nameWellFormed("NVIDIA \"Corp\""));
        assertFalse(LibSecurity.nameWellFormed("NVIDIA\\Corp"));
        assertFalse(LibSecurity.nameWellFormed("NVIDIA\nCorp"));
        assertFalse(LibSecurity.nameWellFormed(hex"4e56494449417f"));
    }

    /// The boundaries the NatSpec states: digits 0 and 9 are tickers, the
    /// bytes either side are not; a space is the lowest name byte, 0x1f is
    /// not; a name shorter than the suffix is checked without underflow.
    function testShapeBoundaries() external pure {
        assertTrue(LibSecurity.tickerWellFormed("0"));
        assertTrue(LibSecurity.tickerWellFormed("9"));
        assertTrue(LibSecurity.tickerWellFormed("A0Z9."));
        assertFalse(LibSecurity.tickerWellFormed("/"));
        assertFalse(LibSecurity.tickerWellFormed(":"));
        assertFalse(LibSecurity.tickerWellFormed("@"));
        assertFalse(LibSecurity.tickerWellFormed("["));
        assertTrue(LibSecurity.nameWellFormed("3M"));
        assertTrue(LibSecurity.nameWellFormed(" "));
        assertFalse(LibSecurity.nameWellFormed(hex"1f"));
        assertFalse(LibSecurity.nameWellFormed("ST0x"));
    }
}

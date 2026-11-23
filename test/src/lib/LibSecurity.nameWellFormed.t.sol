// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console} from "forge-std-1.17.0/src/Test.sol";
import {LibSecurity} from "../../../src/lib/LibSecurity.sol";
import {NasdaqSymbolDirectoryTest} from "../../lib/NasdaqSymbolDirectoryTest.sol";

contract LibSecurityNameWellFormedTest is NasdaqSymbolDirectoryTest {
    function checkEveryListedNameAccepted(string memory url) internal {
        string[] memory names = listedColumn(url, "Security Name");
        for (uint256 i = 0; i < names.length; i++) {
            assertTrue(LibSecurity.nameWellFormed(bytes(names[i])), names[i]);
        }
        console.log(url, names.length);
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

    /// A space is the lowest name byte, 0x1f is not; a name shorter than the
    /// suffix is checked without underflow.
    function testNameBoundaries() external pure {
        assertTrue(LibSecurity.nameWellFormed("3M"));
        assertTrue(LibSecurity.nameWellFormed(" "));
        assertFalse(LibSecurity.nameWellFormed(hex"1f"));
        assertFalse(LibSecurity.nameWellFormed("ST0x"));
    }

    function testNameAcceptsEveryNasdaqListedSecurityName() external {
        checkEveryListedNameAccepted(NASDAQ_LISTED);
    }

    function testNameAcceptsEveryOtherListedSecurityName() external {
        checkEveryListedNameAccepted(OTHER_LISTED);
    }
}

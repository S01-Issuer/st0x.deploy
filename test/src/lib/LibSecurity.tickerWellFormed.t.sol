// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test, Vm, console} from "forge-std-1.17.0/src/Test.sol";
import {LibSecurity} from "../../../src/lib/LibSecurity.sol";

/// Fetched at run time, never committed, because Nasdaq's terms forbid redistributing the lists.
contract LibSecurityTickerWellFormedTest is Test {
    function fetch(string memory url) internal returns (string memory) {
        string[] memory command = new string[](7);
        command[0] = "curl";
        command[1] = "-sSfL";
        command[2] = "--retry";
        command[3] = "3";
        command[4] = "-A";
        command[5] = "st0x.deploy";
        command[6] = url;
        Vm.FfiResult memory result = vm.tryFfi(command);
        assertEq(result.exitCode, 0, string(result.stderr));
        return string(result.stdout);
    }

    function column(string[] memory header, string memory name) internal pure returns (uint256) {
        for (uint256 i = 0; i < header.length; i++) {
            if (keccak256(bytes(header[i])) == keccak256(bytes(name))) return i;
        }
        revert(string.concat("no column ", name));
    }

    function hasLowercase(bytes memory symbol) internal pure returns (bool) {
        for (uint256 i = 0; i < symbol.length; i++) {
            if (symbol[i] >= "a" && symbol[i] <= "z") return true;
        }
        return false;
    }

    function checkListedSymbols(string memory url, string memory symbolColumn, bool cqs)
        internal
        returns (uint256, uint256)
    {
        string[] memory lines = vm.split(fetch(url), "\r\n");
        string[] memory header = vm.split(lines[0], "|");
        uint256 symbolIndex = column(header, symbolColumn);
        uint256 testIssueIndex = column(header, "Test Issue");
        uint256 accepted = 0;
        uint256 rejected = 0;
        for (uint256 i = 1; i < lines.length; i++) {
            if (vm.indexOf(lines[i], "File Creation Time") == 0) continue;
            string[] memory fields = vm.split(lines[i], "|");
            if (keccak256(bytes(fields[testIssueIndex])) == keccak256("Y")) continue;
            bytes memory symbol = bytes(fields[symbolIndex]);
            // CQS marks preferreds `p` and rights `r` with a lowercase suffix.
            bool expected = !(cqs && hasLowercase(symbol));
            assertEq(LibSecurity.tickerWellFormed(symbol), expected, string(symbol));
            if (expected) accepted++;
            else rejected++;
        }
        assertGt(accepted + rejected, 1000, url);
        console.log(url, accepted, rejected);
        return (accepted, rejected);
    }

    function testTickerAcceptsEveryNasdaqListedSymbol() external {
        checkListedSymbols("https://www.nasdaqtrader.com/dynamic/symdir/nasdaqlisted.txt", "Symbol", false);
    }

    function testTickerRejectsOnlyLowercaseSuffixedOtherListedCqsSymbols() external {
        checkListedSymbols("https://www.nasdaqtrader.com/dynamic/symdir/otherlisted.txt", "CQS Symbol", true);
    }
}

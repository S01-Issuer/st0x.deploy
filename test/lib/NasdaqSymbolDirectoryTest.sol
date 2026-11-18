// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

/// Fetched at run time, never committed, because Nasdaq's terms forbid redistributing the lists.
abstract contract NasdaqSymbolDirectoryTest is Test {
    string internal constant NASDAQ_LISTED = "https://www.nasdaqtrader.com/dynamic/symdir/nasdaqlisted.txt";
    string internal constant OTHER_LISTED = "https://www.nasdaqtrader.com/dynamic/symdir/otherlisted.txt";

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

    /// `columnName` of every row of the list at `url` that is not a test issue.
    function listedColumn(string memory url, string memory columnName) internal returns (string[] memory) {
        string[] memory lines = vm.split(fetch(url), "\r\n");
        string[] memory header = vm.split(lines[0], "|");
        uint256 valueIndex = column(header, columnName);
        uint256 testIssueIndex = column(header, "Test Issue");
        string[] memory values = new string[](lines.length);
        uint256 count = 0;
        for (uint256 i = 1; i < lines.length; i++) {
            if (vm.indexOf(lines[i], "File Creation Time") == 0) continue;
            string[] memory fields = vm.split(lines[i], "|");
            if (keccak256(bytes(fields[testIssueIndex])) == keccak256("Y")) continue;
            values[count++] = fields[valueIndex];
        }
        assembly ("memory-safe") {
            mstore(values, count)
        }
        assertGt(count, 1000, url);
        return values;
    }
}

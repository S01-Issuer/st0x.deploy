// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {UrlFetchTest} from "./UrlFetchTest.sol";

/// The header and the fields of every row of one Nasdaq symbol directory that is not a test issue.
struct SymbolDirectory {
    string[] header;
    string[][] rows;
}

/// Fetched at run time, never committed, because Nasdaq's terms forbid redistributing the lists.
abstract contract NasdaqSymbolDirectoryTest is UrlFetchTest {
    string internal constant NASDAQ_LISTED = "https://www.nasdaqtrader.com/dynamic/symdir/nasdaqlisted.txt";
    string internal constant OTHER_LISTED = "https://www.nasdaqtrader.com/dynamic/symdir/otherlisted.txt";

    function column(string[] memory header, string memory name) internal pure returns (uint256) {
        for (uint256 i = 0; i < header.length; i++) {
            if (keccak256(bytes(header[i])) == keccak256(bytes(name))) return i;
        }
        revert(string.concat("no column ", name));
    }

    function symbolDirectory(string memory url) internal returns (SymbolDirectory memory) {
        string[] memory lines = vm.split(fetch(url), "\r\n");
        string[] memory header = vm.split(lines[0], "|");
        uint256 testIssueIndex = column(header, "Test Issue");
        string[][] memory rows = new string[][](lines.length);
        uint256 count = 0;
        for (uint256 i = 1; i < lines.length; i++) {
            if (vm.indexOf(lines[i], "File Creation Time") == 0) continue;
            string[] memory fields = vm.split(lines[i], "|");
            if (keccak256(bytes(fields[testIssueIndex])) == keccak256("Y")) continue;
            rows[count++] = fields;
        }
        assembly ("memory-safe") {
            mstore(rows, count)
        }
        assertGt(count, 1000, url);
        return SymbolDirectory({header: header, rows: rows});
    }

    /// `columnName` of every row of the list at `url` that is not a test issue.
    function listedColumn(string memory url, string memory columnName) internal returns (string[] memory) {
        SymbolDirectory memory directory = symbolDirectory(url);
        uint256 valueIndex = column(directory.header, columnName);
        string[] memory values = new string[](directory.rows.length);
        for (uint256 i = 0; i < directory.rows.length; i++) {
            values[i] = directory.rows[i][valueIndex];
        }
        return values;
    }

    /// The fields of the row whose `symbolColumn` is `symbol`, or no fields when the directory does not list it.
    function listing(SymbolDirectory memory directory, string memory symbolColumn, string memory symbol)
        internal
        pure
        returns (string[] memory)
    {
        uint256 symbolIndex = column(directory.header, symbolColumn);
        for (uint256 i = 0; i < directory.rows.length; i++) {
            if (keccak256(bytes(directory.rows[i][symbolIndex])) == keccak256(bytes(symbol))) {
                return directory.rows[i];
            }
        }
        return new string[](0);
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console} from "forge-std-1.17.0/src/Test.sol";
import {LibSecurity} from "../../../src/lib/LibSecurity.sol";
import {NasdaqSymbolDirectoryTest} from "../../lib/NasdaqSymbolDirectoryTest.sol";

contract LibSecurityTickerWellFormedTest is NasdaqSymbolDirectoryTest {
    function hasLowercase(bytes memory symbol) internal pure returns (bool) {
        for (uint256 i = 0; i < symbol.length; i++) {
            if (symbol[i] >= "a" && symbol[i] <= "z") return true;
        }
        return false;
    }

    function checkListedSymbols(string memory url, string memory symbolColumn, bool cqs) internal {
        string[] memory symbols = listedColumn(url, symbolColumn);
        uint256 accepted = 0;
        for (uint256 i = 0; i < symbols.length; i++) {
            bytes memory symbol = bytes(symbols[i]);
            // CQS marks preferreds `p` and rights `r` with a lowercase suffix.
            bool expected = !(cqs && hasLowercase(symbol));
            assertEq(LibSecurity.tickerWellFormed(symbol), expected, symbols[i]);
            if (expected) accepted++;
        }
        console.log(url, accepted, symbols.length - accepted);
    }

    function testTickerAcceptsEveryNasdaqListedSymbol() external {
        checkListedSymbols(NASDAQ_LISTED, "Symbol", false);
    }

    function testTickerRejectsOnlyLowercaseSuffixedOtherListedCqsSymbols() external {
        checkListedSymbols(OTHER_LISTED, "CQS Symbol", true);
    }
}

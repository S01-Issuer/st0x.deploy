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

    function testNameAcceptsEveryNasdaqListedSecurityName() external {
        checkEveryListedNameAccepted(NASDAQ_LISTED);
    }

    function testNameAcceptsEveryOtherListedSecurityName() external {
        checkEveryListedNameAccepted(OTHER_LISTED);
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibSecurity} from "../../../src/lib/LibSecurity.sol";

/// Every Wikidata ISIN (P946) value, split by ISIN format plus check digit:
/// see `test/fixture/wikidata-p946/README.md`.
contract LibSecurityIsinWellFormedRealWorldTest is Test {
    function lines(string memory path) internal view returns (string[] memory) {
        string[] memory values = vm.split(vm.readFile(path), "\n");
        assertEq(values[values.length - 1], "", path);
        assembly ("memory-safe") {
            mstore(values, sub(mload(values), 1))
        }
        return values;
    }

    function testIsinAcceptsEveryWellFormedRealWorldValue() external view {
        string[] memory values = lines("test/fixture/wikidata-p946/accepted.txt");
        for (uint256 i = 0; i < values.length; i++) {
            assertTrue(LibSecurity.isinWellFormed(values[i]), values[i]);
        }
    }

    function testIsinRejectsEveryMalformedRealWorldValue() external view {
        string[] memory values = lines("test/fixture/wikidata-p946/rejected.txt");
        for (uint256 i = 0; i < values.length; i++) {
            assertFalse(LibSecurity.isinWellFormed(values[i]), values[i]);
        }
    }
}

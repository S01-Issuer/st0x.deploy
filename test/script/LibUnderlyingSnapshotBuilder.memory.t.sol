// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibUnderlyingSnapshotBuilder, UnderlyingSnapshotRow} from "../../script/LibUnderlyingSnapshotBuilder.sol";
import {LibTestUnderlyingSnapshotRows} from "../lib/LibTestUnderlyingSnapshotRows.sol";

contract LibUnderlyingSnapshotBuilderMemoryTest is Test {
    function freeMemoryPointer() internal pure returns (uint256) {
        uint256 pointer;
        assembly ("memory-safe") {
            pointer := mload(0x40)
        }
        return pointer;
    }

    function buildMemory(UnderlyingSnapshotRow[] memory rows) internal pure returns (uint256) {
        uint256 start = freeMemoryPointer();
        LibUnderlyingSnapshotBuilder.build(0, rows);
        return freeMemoryPointer() - start;
    }

    function testFiveThousandRowsBuildWithinTheDefaultMemoryLimit() external pure {
        LibUnderlyingSnapshotBuilder.build(0, LibTestUnderlyingSnapshotRows.rowsFrom(vm, "five thousand", 5000));
    }

    function testBuildMemoryAtTwiceTheRowsIsAtMostThreeTimes() external pure {
        uint256 small = buildMemory(LibTestUnderlyingSnapshotRows.rowsFrom(vm, "small", 200));
        uint256 large = buildMemory(LibTestUnderlyingSnapshotRows.rowsFrom(vm, "large", 400));
        assertLe(large, 3 * small, "memory");
    }
}

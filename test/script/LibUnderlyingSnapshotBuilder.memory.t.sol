// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";
import {LibUnderlyingSnapshotBuilder, UnderlyingSnapshotRow} from "../../script/LibUnderlyingSnapshotBuilder.sol";
import {LibTestUnderlyingSnapshotRows} from "../lib/LibTestUnderlyingSnapshotRows.sol";

contract LibUnderlyingSnapshotBuilderMemoryTest is Test {
    function buildMemory(UnderlyingSnapshotRow[] memory rows) internal pure returns (uint256) {
        uint256 start = Pointer.unwrap(LibPointer.allocatedMemoryPointer());
        LibUnderlyingSnapshotBuilder.build(0, rows);
        return Pointer.unwrap(LibPointer.allocatedMemoryPointer()) - start;
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

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";

/// @notice Shard suite keys number the shards in base 26, a to z.
contract StoxDeploySuitesUnderlyingSnapshotShardSuiteTest is Test, StoxDeploySuites {
    function testShardSuiteKeysCountInBase26() external pure {
        assertEq(underlyingSnapshotShardSuite(0), "stox-underlying-snapshot-shard-a");
        assertEq(underlyingSnapshotShardSuite(25), "stox-underlying-snapshot-shard-z");
        assertEq(underlyingSnapshotShardSuite(26), "stox-underlying-snapshot-shard-ba");
        assertEq(underlyingSnapshotShardSuite(675), "stox-underlying-snapshot-shard-zz");
        assertEq(underlyingSnapshotShardSuite(676), "stox-underlying-snapshot-shard-baa");
    }

    function testShardSuiteKeysAreDistinct(uint256 a, uint256 b) external pure {
        a = bound(a, 0, type(uint16).max);
        b = bound(b, 0, type(uint16).max);
        vm.assume(a != b);
        assertNotEq(underlyingSnapshotShardSuite(a), underlyingSnapshotShardSuite(b));
    }
}

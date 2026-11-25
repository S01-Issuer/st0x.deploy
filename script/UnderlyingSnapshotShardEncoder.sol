// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibUnderlyingSnapshotBuilder, UnderlyingSnapshotRow} from "./LibUnderlyingSnapshotBuilder.sol";

/// External entry so the builder can catch a shard's meta build revert.
contract UnderlyingSnapshotShardEncoder {
    function shardData(UnderlyingSnapshotRow[] memory rows) external pure returns (bytes memory) {
        return LibUnderlyingSnapshotBuilder.shardData(rows);
    }
}

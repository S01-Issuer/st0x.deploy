// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    LibUnderlyingSnapshot,
    UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH
} from "../../../src/lib/LibUnderlyingSnapshot.sol";
import {LibUnderlyingSnapshotBuilder, UnderlyingSnapshotRow} from "../../../script/LibUnderlyingSnapshotBuilder.sol";

/// @notice A parse meta hit whose row holds another address is a miss.
contract LibUnderlyingSnapshotAddressCheckTest is Test {
    function writeAddress(bytes memory data, uint256 offset, address value) internal pure {
        assembly ("memory-safe") {
            let p := add(add(data, 0x20), offset)
            mstore(p, or(shl(96, value), and(mload(p), 0xffffffffffffffffffffffff)))
        }
    }

    function assertNotFound(LibUnderlyingSnapshot.Lookup memory row, uint256 asOf) internal pure {
        assertEq(row.asOf, asOf, "asOf");
        assertFalse(row.found, "found");
        assertEq(row.ticker, "", "ticker");
        assertEq(row.name, "", "name");
        assertEq(row.isin, "", "isin");
    }

    function testFingerprintHitOnAnotherAddressIsNotFound(address member, address other, uint256 asOf) external {
        vm.assume(member != other);
        UnderlyingSnapshotRow[] memory rows = new UnderlyingSnapshotRow[](1);
        rows[0] = UnderlyingSnapshotRow(member, "AAPL", "Apple Inc.", "US0378331005");
        bytes memory shardData = LibUnderlyingSnapshotBuilder.shardData(rows);
        uint256 metaLength = uint256(uint8(shardData[6])) << 8 | uint8(shardData[7]);
        writeAddress(shardData, UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH + metaLength + 2, other);

        address shard = makeAddr("shard");
        vm.etch(shard, abi.encodePacked(bytes1(0), shardData));
        address[] memory shards = new address[](1);
        shards[0] = shard;
        address root = makeAddr("root");
        vm.etch(root, abi.encodePacked(bytes1(0), LibUnderlyingSnapshotBuilder.rootData(asOf, shards)));

        assertNotFound(LibUnderlyingSnapshot.lookup(root, member), asOf);
        assertNotFound(LibUnderlyingSnapshot.lookup(root, other), asOf);
    }
}

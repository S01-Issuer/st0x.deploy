// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    LibUnderlyingSnapshot,
    UNDERLYING_SNAPSHOT_ROOT_HEADER_LENGTH,
    UNDERLYING_SNAPSHOT_ROOT_MAGIC,
    UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH,
    UNDERLYING_SNAPSHOT_SHARD_MAGIC
} from "../../../src/lib/LibUnderlyingSnapshot.sol";
import {MalformedUnderlyingSnapshot} from "../../../src/error/ErrUnderlying.sol";
import {LibUnderlyingSnapshotBuilder, UnderlyingSnapshotRow} from "../../../script/LibUnderlyingSnapshotBuilder.sol";
import {UNDERLYING_SNAPSHOT_AS_OF as AS_OF} from "../../../src/lib/LibProdTokenConfig.sol";

/// @notice Root and shard bytes that do not match the snapshot format revert
/// `MalformedUnderlyingSnapshot` naming the contract, and never read past them.
contract LibUnderlyingSnapshotMalformedTest is Test {
    address constant MEMBER = address(0xA11CE);

    address internal root = makeAddr("root");
    address internal shard = makeAddr("shard");

    function lookup(address token) external view returns (LibUnderlyingSnapshot.Lookup memory) {
        return LibUnderlyingSnapshot.lookup(root, token);
    }

    function etchData(address account, bytes memory data) internal {
        vm.etch(account, abi.encodePacked(bytes1(0), data));
    }

    function etchRootOverShard() internal {
        address[] memory shards = new address[](1);
        shards[0] = shard;
        etchData(root, LibUnderlyingSnapshotBuilder.rootData(AS_OF, shards));
    }

    function memberRow(address token) internal pure returns (UnderlyingSnapshotRow memory) {
        return UnderlyingSnapshotRow(token, "AAPL", "Apple Inc.", "US0378331005");
    }

    function oneRowShard() internal pure returns (bytes memory) {
        UnderlyingSnapshotRow[] memory rows = new UnderlyingSnapshotRow[](1);
        rows[0] = memberRow(MEMBER);
        (, bytes memory shardData) = LibUnderlyingSnapshotBuilder.shardData(rows, 1);
        return shardData;
    }

    function readUint16(bytes memory data, uint256 offset) internal pure returns (uint256) {
        return uint256(uint8(data[offset])) << 8 | uint8(data[offset + 1]);
    }

    function bucketCount(bytes memory shardData) internal pure returns (uint256) {
        return readUint16(shardData, 6);
    }

    function slotCount(bytes memory shardData) internal pure returns (uint256) {
        return readUint16(shardData, 8);
    }

    function rowsStart(bytes memory shardData) internal pure returns (uint256) {
        return UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH + bucketCount(shardData) + 2 * slotCount(shardData);
    }

    /// Where a one-row shard holds the offset of the slot its row owns.
    function memberSlot(bytes memory shardData) internal pure returns (uint256) {
        uint256 offsets = UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH + bucketCount(shardData);
        for (uint256 s = 0; s < slotCount(shardData); s++) {
            if (readUint16(shardData, offsets + 2 * s) != 0) return offsets + 2 * s;
        }
        revert("no owned slot");
    }

    function writeUint16(bytes memory data, uint256 offset, uint256 value) internal pure {
        assembly ("memory-safe") {
            let p := add(add(data, 0x20), offset)
            mstore8(p, shr(8, value))
            mstore8(add(p, 1), value)
        }
    }

    function writeBytes4(bytes memory data, uint256 offset, bytes4 value) internal pure {
        assembly ("memory-safe") {
            let p := add(add(data, 0x20), offset)
            mstore(p, or(value, and(mload(p), not(shl(224, 0xffffffff)))))
        }
    }

    function truncate(bytes memory data, uint256 length) internal pure returns (bytes memory) {
        assembly ("memory-safe") {
            mstore(data, length)
        }
        return data;
    }

    function expectMalformed(address account) internal {
        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlyingSnapshot.selector, account));
    }

    function expectShardMalformed(bytes memory shardData) internal {
        etchRootOverShard();
        etchData(shard, shardData);
        expectMalformed(shard);
        this.lookup(MEMBER);
    }

    function testRootWithoutCodeIsMalformed(address token) external {
        expectMalformed(root);
        this.lookup(token);
    }

    function testRootShorterThanItsHeaderIsMalformed(uint256 length) external {
        length = bound(length, 0, UNDERLYING_SNAPSHOT_ROOT_HEADER_LENGTH - 1);
        address[] memory shards = new address[](1);
        shards[0] = shard;
        etchData(root, truncate(LibUnderlyingSnapshotBuilder.rootData(AS_OF, shards), length));
        expectMalformed(root);
        this.lookup(MEMBER);
    }

    function testRootWithAnotherMagicIsMalformed(bytes4 magic) external {
        vm.assume(magic != UNDERLYING_SNAPSHOT_ROOT_MAGIC);
        address[] memory shards = new address[](1);
        shards[0] = shard;
        bytes memory rootData = LibUnderlyingSnapshotBuilder.rootData(AS_OF, shards);
        writeBytes4(rootData, 0, magic);
        etchData(root, rootData);
        etchData(shard, oneRowShard());
        expectMalformed(root);
        this.lookup(MEMBER);
    }

    function testRootWithNoShardsIsMalformed() external {
        etchData(root, LibUnderlyingSnapshotBuilder.rootData(AS_OF, new address[](0)));
        expectMalformed(root);
        this.lookup(MEMBER);
    }

    function testRootLongerThanItsShardCountIsMalformed() external {
        address[] memory shards = new address[](1);
        shards[0] = shard;
        etchData(root, abi.encodePacked(LibUnderlyingSnapshotBuilder.rootData(AS_OF, shards), bytes1(0)));
        etchData(shard, oneRowShard());
        expectMalformed(root);
        this.lookup(MEMBER);
    }

    function testRootShorterThanItsShardCountIsMalformed() external {
        address[] memory shards = new address[](1);
        shards[0] = shard;
        bytes memory rootData = LibUnderlyingSnapshotBuilder.rootData(AS_OF, shards);
        writeUint16(rootData, 36, 2);
        etchData(root, rootData);
        etchData(shard, oneRowShard());
        expectMalformed(root);
        this.lookup(MEMBER);
    }

    function testShardWithoutCodeIsMalformed() external {
        etchRootOverShard();
        expectMalformed(shard);
        this.lookup(MEMBER);
    }

    function testShardShorterThanItsHeaderIsMalformed(uint256 length) external {
        length = bound(length, 0, UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH - 1);
        expectShardMalformed(truncate(oneRowShard(), length));
    }

    function testShardWithAnotherMagicIsMalformed(bytes4 magic) external {
        vm.assume(magic != UNDERLYING_SNAPSHOT_SHARD_MAGIC);
        bytes memory shardData = oneRowShard();
        writeBytes4(shardData, 0, magic);
        expectShardMalformed(shardData);
    }

    function testShardWithNoBucketsIsMalformed() external {
        bytes memory shardData = oneRowShard();
        writeUint16(shardData, 6, 0);
        expectShardMalformed(shardData);
    }

    function testShardWithNoSlotsIsMalformed() external {
        bytes memory shardData = oneRowShard();
        writeUint16(shardData, 8, 0);
        expectShardMalformed(shardData);
    }

    function testShardBucketsPastItsEndAreMalformed(uint256 excess) external {
        bytes memory shardData = oneRowShard();
        uint256 fill = shardData.length - UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH - 2 * slotCount(shardData);
        writeUint16(shardData, 6, fill + bound(excess, 1, type(uint16).max - fill));
        expectShardMalformed(shardData);
    }

    function testShardSlotsPastItsEndAreMalformed(uint256 excess) external {
        bytes memory shardData = oneRowShard();
        uint256 fill = (shardData.length - UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH - bucketCount(shardData)) / 2;
        writeUint16(shardData, 8, fill + bound(excess, 1, type(uint16).max - fill));
        expectShardMalformed(shardData);
    }

    /// A shard of no rows is its index alone.
    function noRowShard() internal pure returns (bytes memory) {
        (, bytes memory shardData) = LibUnderlyingSnapshotBuilder.shardData(new UnderlyingSnapshotRow[](0), 1);
        assertEq(rowsStart(shardData), shardData.length, "index fills the shard");
        return shardData;
    }

    function testShardIndexEndingAtItsDataFindsNothing(address token) external {
        etchRootOverShard();
        etchData(shard, noRowShard());
        LibUnderlyingSnapshot.Lookup memory row = this.lookup(token);
        assertEq(row.asOf, AS_OF, "asOf");
        assertFalse(row.found, "found");
    }

    function testShardIndexOneBytePastItsDataIsMalformed() external {
        bytes memory shardData = noRowShard();
        writeUint16(shardData, 6, bucketCount(shardData) + 1);
        expectShardMalformed(shardData);
    }

    function testSlotOffsetBeforeTheRowsIsMalformed() external {
        bytes memory shardData = oneRowShard();
        writeUint16(shardData, memberSlot(shardData), rowsStart(shardData) - 1);
        expectShardMalformed(shardData);
    }

    function testSlotOffsetLeavingLessThanARowHeadIsMalformed() external {
        bytes memory shardData = oneRowShard();
        writeUint16(shardData, memberSlot(shardData), shardData.length - 20);
        expectShardMalformed(shardData);
    }

    /// The 21 bytes there hold no member address, so the lookup misses.
    function testSlotOffsetLeavingExactlyARowHeadIsAddressChecked() external {
        bytes memory shardData = oneRowShard();
        writeUint16(shardData, memberSlot(shardData), shardData.length - 21);
        etchRootOverShard();
        etchData(shard, shardData);
        LibUnderlyingSnapshot.Lookup memory row = this.lookup(MEMBER);
        assertEq(row.asOf, AS_OF, "asOf");
        assertFalse(row.found, "found");
    }

    function testRowCutBeforeItsTickerLengthIsMalformed() external {
        bytes memory shardData = oneRowShard();
        expectShardMalformed(truncate(shardData, rowsStart(shardData) + 20));
    }

    function testTickerPastTheDataIsMalformed() external {
        bytes memory shardData = oneRowShard();
        shardData[rowsStart(shardData) + 20] = bytes1(0xff);
        expectShardMalformed(shardData);
    }

    function testRowCutAfterItsTickerIsMalformed() external {
        bytes memory shardData = oneRowShard();
        expectShardMalformed(truncate(shardData, rowsStart(shardData) + 21 + bytes("AAPL").length));
    }

    function testNamePastTheDataIsMalformed() external {
        bytes memory shardData = oneRowShard();
        shardData[rowsStart(shardData) + 21 + bytes("AAPL").length] = bytes1(0xff);
        expectShardMalformed(shardData);
    }

    function testRowCutAfterItsNameIsMalformed() external {
        bytes memory shardData = oneRowShard();
        expectShardMalformed(
            truncate(shardData, rowsStart(shardData) + 22 + bytes("AAPL").length + bytes("Apple Inc.").length)
        );
    }

    function testIsinPastTheDataIsMalformed() external {
        bytes memory shardData = oneRowShard();
        // One past the 12-byte ISIN.
        shardData[rowsStart(shardData) + 22 + bytes("AAPL").length + bytes("Apple Inc.").length] = bytes1(0x0d);
        expectShardMalformed(shardData);
    }

    function testRowEndingExactlyAtTheDataReads() external {
        etchRootOverShard();
        etchData(shard, oneRowShard());
        LibUnderlyingSnapshot.Lookup memory row = this.lookup(MEMBER);
        assertEq(row.asOf, AS_OF, "asOf");
        assertTrue(row.found, "found");
        assertEq(row.ticker, "AAPL", "ticker");
        assertEq(row.name, "Apple Inc.", "name");
        assertEq(row.isin, "US0378331005", "isin");
    }
}

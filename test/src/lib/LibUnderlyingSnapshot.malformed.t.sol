// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {InvalidParseMeta} from "rainlang-0.2.40/src/lib/parse/LibParseMeta.sol";
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
    address constant SECOND = address(0xB0B);

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
        return LibUnderlyingSnapshotBuilder.shardData(rows);
    }

    function metaLength(bytes memory shardData) internal pure returns (uint256) {
        return uint256(uint8(shardData[6])) << 8 | uint8(shardData[7]);
    }

    /// The only row of a one-row shard starts right after its single offset.
    function firstRow(bytes memory shardData) internal pure returns (uint256) {
        return UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH + metaLength(shardData) + 2;
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

    function testShardRowCountPastItsEndIsMalformed() external {
        bytes memory shardData = oneRowShard();
        writeUint16(shardData, 4, type(uint16).max);
        expectShardMalformed(shardData);
    }

    function testShardMetaLengthPastItsEndIsMalformed() external {
        bytes memory shardData = oneRowShard();
        writeUint16(shardData, 6, type(uint16).max);
        expectShardMalformed(shardData);
    }

    function testShardMetaShorterThanItsStructureRevertsInvalidParseMeta() external {
        bytes memory shardData = oneRowShard();
        uint256 length = metaLength(shardData);
        writeUint16(shardData, 6, length - 1);
        etchRootOverShard();
        etchData(shard, shardData);
        vm.expectRevert(abi.encodeWithSelector(InvalidParseMeta.selector, length, length - 1));
        this.lookup(MEMBER);
    }

    function testMetaIndexPastTheRowCountIsMalformed() external {
        UnderlyingSnapshotRow[] memory rows = new UnderlyingSnapshotRow[](2);
        rows[0] = memberRow(MEMBER);
        rows[1] = memberRow(SECOND);
        bytes memory shardData = LibUnderlyingSnapshotBuilder.shardData(rows);
        writeUint16(shardData, 4, 1);
        etchRootOverShard();
        etchData(shard, shardData);
        expectMalformed(shard);
        this.lookup(SECOND);
    }

    function testRowOffsetBeforeTheRowsIsMalformed() external {
        bytes memory shardData = oneRowShard();
        uint256 row = firstRow(shardData);
        writeUint16(shardData, row - 2, row - 1);
        expectShardMalformed(shardData);
    }

    function testRowCutBeforeItsTickerLengthIsMalformed() external {
        bytes memory shardData = oneRowShard();
        expectShardMalformed(truncate(shardData, firstRow(shardData) + 20));
    }

    function testTickerPastTheDataIsMalformed() external {
        bytes memory shardData = oneRowShard();
        shardData[firstRow(shardData) + 20] = bytes1(0xff);
        expectShardMalformed(shardData);
    }

    function testRowCutAfterItsTickerIsMalformed() external {
        bytes memory shardData = oneRowShard();
        expectShardMalformed(truncate(shardData, firstRow(shardData) + 21 + bytes("AAPL").length));
    }

    function testNamePastTheDataIsMalformed() external {
        bytes memory shardData = oneRowShard();
        shardData[firstRow(shardData) + 21 + bytes("AAPL").length] = bytes1(0xff);
        expectShardMalformed(shardData);
    }

    function testRowCutAfterItsNameIsMalformed() external {
        bytes memory shardData = oneRowShard();
        expectShardMalformed(
            truncate(shardData, firstRow(shardData) + 22 + bytes("AAPL").length + bytes("Apple Inc.").length)
        );
    }

    function testIsinPastTheDataIsMalformed() external {
        bytes memory shardData = oneRowShard();
        // One past the 12-byte ISIN.
        shardData[firstRow(shardData) + 22 + bytes("AAPL").length + bytes("Apple Inc.").length] = bytes1(0x0d);
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

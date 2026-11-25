// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {PREFIX_BYTES_LENGTH} from "rain-datacontract-0.2.1/src/lib/LibDataContract.sol";
import {
    LibUnderlyingSnapshot,
    UNDERLYING_SNAPSHOT_ROOT_HEADER_LENGTH,
    UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH
} from "../../src/lib/LibUnderlyingSnapshot.sol";
import {
    LibUnderlyingSnapshotBuilder,
    UnderlyingSnapshotRow,
    UnderlyingSnapshotDoesNotShard,
    UnderlyingSnapshotFieldTooLong,
    EIP170_MAX_RUNTIME
} from "../../script/LibUnderlyingSnapshotBuilder.sol";
import {LibTestDeploy} from "../lib/LibTestDeploy.sol";
import {LibTestUnderlyingSnapshotRows} from "../lib/LibTestUnderlyingSnapshotRows.sol";

contract LibUnderlyingSnapshotBuilderTest is Test {
    function build(uint256 asOf, UnderlyingSnapshotRow[] memory rows) external returns (bytes memory, bytes[] memory) {
        return LibUnderlyingSnapshotBuilder.build(asOf, rows);
    }

    function shardData(UnderlyingSnapshotRow[] memory rows) external pure returns (bytes memory) {
        return LibUnderlyingSnapshotBuilder.shardData(rows);
    }

    function filled(uint256 length) internal pure returns (string memory) {
        bytes memory out = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            out[i] = "A";
        }
        return string(out);
    }

    /// field 0, 1, 2 is the ticker, name, ISIN.
    function rowWithField(address token, uint256 field, uint256 length)
        internal
        pure
        returns (UnderlyingSnapshotRow memory)
    {
        UnderlyingSnapshotRow memory row = UnderlyingSnapshotRow(token, "AAPL", "Apple Inc.", "US0378331005");
        if (field == 0) row.ticker = filled(length);
        else if (field == 1) row.name = filled(length);
        else row.isin = filled(length);
        return row;
    }

    function one(UnderlyingSnapshotRow memory row) internal pure returns (UnderlyingSnapshotRow[] memory) {
        UnderlyingSnapshotRow[] memory rows = new UnderlyingSnapshotRow[](1);
        rows[0] = row;
        return rows;
    }

    function assertReadsBack(address root, uint256 asOf, UnderlyingSnapshotRow memory expected) internal view {
        LibUnderlyingSnapshot.Lookup memory row = LibUnderlyingSnapshot.lookup(root, expected.token);
        assertEq(row.asOf, asOf, "asOf");
        assertTrue(row.found, "found");
        assertEq(row.ticker, expected.ticker, "ticker");
        assertEq(row.name, expected.name, "name");
        assertEq(row.isin, expected.isin, "isin");
    }

    function testFieldOf255BytesReadsBack(address token, uint256 field) external {
        UnderlyingSnapshotRow memory row = rowWithField(token, bound(field, 0, 2), type(uint8).max);
        (bytes memory rootCode, bytes[] memory shardCodes) = LibUnderlyingSnapshotBuilder.build(0, one(row));
        assertReadsBack(LibTestDeploy.deployUnderlyingSnapshot(vm, rootCode, shardCodes), 0, row);
    }

    function testFieldOver255BytesReverts(address token, uint256 field, uint256 length) external {
        length = bound(length, uint256(type(uint8).max) + 1, 1024);
        UnderlyingSnapshotRow[] memory rows = one(rowWithField(token, bound(field, 0, 2), length));
        vm.expectRevert(abi.encodeWithSelector(UnderlyingSnapshotFieldTooLong.selector, token, length));
        this.shardData(rows);
    }

    /// A row's encoding error surfaces from build instead of moving on to more shards.
    function testBuildRethrowsFieldTooLong(address token, uint256 field, uint256 length) external {
        length = bound(length, uint256(type(uint8).max) + 1, 1024);
        UnderlyingSnapshotRow[] memory rows = one(rowWithField(token, bound(field, 0, 2), length));
        vm.expectRevert(abi.encodeWithSelector(UnderlyingSnapshotFieldTooLong.selector, token, length));
        this.build(0, rows);
    }

    /// Two rows for one token share a shard at every shard count, so none fits.
    function testDuplicateTokenDoesNotShard() external {
        UnderlyingSnapshotRow[] memory rows = new UnderlyingSnapshotRow[](2);
        rows[0] = rowWithField(address(0), 0, 4);
        rows[1] = rowWithField(address(0), 0, 5);
        vm.expectRevert(abi.encodeWithSelector(UnderlyingSnapshotDoesNotShard.selector, 2));
        this.build(0, rows);
    }

    function testZeroRowsBuildOneShardThatFindsNothing(uint256 asOf, address token) external {
        (bytes memory rootCode, bytes[] memory shardCodes) =
            LibUnderlyingSnapshotBuilder.build(asOf, new UnderlyingSnapshotRow[](0));
        assertEq(shardCodes.length, 1, "shard count");
        LibUnderlyingSnapshot.Lookup memory row =
            LibUnderlyingSnapshot.lookup(LibTestDeploy.deployUnderlyingSnapshot(vm, rootCode, shardCodes), token);
        assertEq(row.asOf, asOf, "asOf");
        assertFalse(row.found, "found");
    }

    /// One-byte fields, so EIP-170 never binds before the row cap.
    function shortRows(uint256 n) internal pure returns (UnderlyingSnapshotRow[] memory) {
        UnderlyingSnapshotRow[] memory rows = new UnderlyingSnapshotRow[](n);
        for (uint256 i = 0; i < n; i++) {
            address token = address(uint160(uint256(keccak256(abi.encode("row cap", i)))));
            rows[i] = UnderlyingSnapshotRow(token, "T", "N", "I");
        }
        return rows;
    }

    function testRowCapBoundsTheShardCount() external {
        (, bytes[] memory atCap) = LibUnderlyingSnapshotBuilder.build(0, shortRows(256));
        assertEq(atCap.length, 1, "256 rows");
        (, bytes[] memory pastCap) = LibUnderlyingSnapshotBuilder.build(0, shortRows(257));
        assertEq(pastCap.length, 2, "257 rows");
    }

    /// 31 rows of 255-byte fields, the last name trimmed so one shard's runtime
    /// is `extra` bytes over the EIP-170 limit.
    function rowsOverEip170By(uint256 extra) internal pure returns (UnderlyingSnapshotRow[] memory) {
        UnderlyingSnapshotRow[] memory rows = new UnderlyingSnapshotRow[](31);
        for (uint256 i = 0; i < rows.length; i++) {
            rows[i] = UnderlyingSnapshotRow(
                address(uint160(uint256(keccak256(abi.encode(i))))), filled(255), filled(255), filled(255)
            );
        }
        uint256 runtime = LibUnderlyingSnapshotBuilder.shardData(rows).length + 1;
        assertGe(runtime, EIP170_MAX_RUNTIME + extra, "rows too short");
        uint256 trim = runtime - EIP170_MAX_RUNTIME - extra;
        assertLe(trim, 255, "rows too long");
        rows[rows.length - 1].name = filled(255 - trim);
        assertEq(LibUnderlyingSnapshotBuilder.shardData(rows).length + 1, EIP170_MAX_RUNTIME + extra, "sized");
        return rows;
    }

    function testShardFillingEip170ExactlyFitsOneShard() external {
        UnderlyingSnapshotRow[] memory rows = rowsOverEip170By(0);
        (bytes memory rootCode, bytes[] memory shardCodes) = LibUnderlyingSnapshotBuilder.build(0, rows);
        assertEq(shardCodes.length, 1, "shard count");
        assertEq(shardCodes[0].length - (PREFIX_BYTES_LENGTH - 1), EIP170_MAX_RUNTIME, "runtime");
        address root = LibTestDeploy.deployUnderlyingSnapshot(vm, rootCode, shardCodes);
        for (uint256 i = 0; i < rows.length; i++) {
            assertReadsBack(root, 0, rows[i]);
        }
    }

    function testShardOneByteOverEip170Splits() external {
        UnderlyingSnapshotRow[] memory rows = rowsOverEip170By(1);
        (bytes memory rootCode, bytes[] memory shardCodes) = LibUnderlyingSnapshotBuilder.build(0, rows);
        assertEq(shardCodes.length, 2, "shard count");
        address root = LibTestDeploy.deployUnderlyingSnapshot(vm, rootCode, shardCodes);
        for (uint256 i = 0; i < rows.length; i++) {
            assertReadsBack(root, 0, rows[i]);
        }
    }

    function testRootIsItsHeaderThenOneAddressPerShard(uint256 asOf, address[] memory shards) external pure {
        assertEq(
            LibUnderlyingSnapshotBuilder.rootData(asOf, shards).length,
            UNDERLYING_SNAPSHOT_ROOT_HEADER_LENGTH + 20 * shards.length
        );
    }

    function testShardIsItsHeaderThenMetaOffsetsAndRows(bytes32 seed, uint8 count) external pure {
        UnderlyingSnapshotRow[] memory rows = LibTestUnderlyingSnapshotRows.rowsFrom(vm, seed, bound(count, 0, 40));
        bytes memory data = LibUnderlyingSnapshotBuilder.shardData(rows);
        uint256 metaLength = uint256(uint8(data[6])) << 8 | uint8(data[7]);
        uint256 rowBytes = 0;
        for (uint256 i = 0; i < rows.length; i++) {
            rowBytes += 23 + bytes(rows[i].ticker).length + bytes(rows[i].name).length + bytes(rows[i].isin).length;
        }
        assertEq(data.length, UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH + metaLength + 2 * rows.length + rowBytes);
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {PREFIX_BYTES_LENGTH} from "rain-datacontract-0.2.1/src/lib/LibDataContract.sol";
import {AuthoringMetaV2} from "rainlang-0.2.40/src/interface/IParserV2.sol";
import {LibGenParseMeta, MaxDepthExceeded} from "rainlang-0.2.40/src/lib/codegen/LibGenParseMeta.sol";
import {
    LibUnderlyingSnapshot,
    UNDERLYING_SNAPSHOT_ROOT_MAGIC,
    UNDERLYING_SNAPSHOT_SHARD_MAGIC
} from "../../src/lib/LibUnderlyingSnapshot.sol";
import {
    LibUnderlyingSnapshotBuilder,
    UnderlyingSnapshotRow,
    UnderlyingSnapshotDoesNotShard,
    UnderlyingSnapshotFieldTooLong,
    EIP170_MAX_RUNTIME,
    UNDERLYING_SNAPSHOT_META_DEPTH
} from "../../script/LibUnderlyingSnapshotBuilder.sol";
import {UnderlyingSnapshotShardEncoder} from "../../script/UnderlyingSnapshotShardEncoder.sol";
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

    function testEmptyFieldsReadBack(bytes32 seed, uint256 count) external {
        UnderlyingSnapshotRow[] memory rows = LibTestUnderlyingSnapshotRows.rowsFrom(vm, seed, bound(count, 4, 40));
        for (uint256 i = 0; i < rows.length; i++) {
            uint256 empty = i % 4;
            if (empty == 0 || empty == 3) rows[i].ticker = "";
            if (empty == 1 || empty == 3) rows[i].name = "";
            if (empty == 2 || empty == 3) rows[i].isin = "";
        }
        (bytes memory rootCode, bytes[] memory shardCodes) = LibUnderlyingSnapshotBuilder.build(0, rows);
        address root = LibTestDeploy.deployUnderlyingSnapshot(vm, rootCode, shardCodes);
        for (uint256 i = 0; i < rows.length; i++) {
            assertReadsBack(root, 0, rows[i]);
        }
    }

    function testEmptyIsinEndingTheShardReadsBack(address token) external {
        UnderlyingSnapshotRow memory row = rowWithField(token, 2, 0);
        (bytes memory rootCode, bytes[] memory shardCodes) = LibUnderlyingSnapshotBuilder.build(0, one(row));
        assertEq(shardCodes.length, 1, "shard count");
        bytes memory shardCode = shardCodes[0];
        assertEq(uint8(shardCode[shardCode.length - 1]), 0, "ISIN length is the last byte");
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

    function testMaxDepthExceededTriesTheNextShardCount(bytes32 seed) external {
        UnderlyingSnapshotRow[] memory rows = LibTestUnderlyingSnapshotRows.rowsFrom(vm, seed, 8);
        // Both parities, so neither two-shard member's calldata is the mocked one-shard call.
        rows[0].token = address(uint160(rows[0].token) | 1);
        rows[1].token = address(uint160(rows[1].token) & ~uint160(1));
        vm.mockCallRevert(
            vm.computeCreateAddress(address(this), vm.getNonce(address(this))),
            abi.encodeCall(UnderlyingSnapshotShardEncoder.shardData, (rows)),
            abi.encodeWithSelector(MaxDepthExceeded.selector, UNDERLYING_SNAPSHOT_META_DEPTH)
        );
        (bytes memory rootCode, bytes[] memory shardCodes) = LibUnderlyingSnapshotBuilder.build(0, rows);
        assertEq(shardCodes.length, 2, "shard count");
        address root = LibTestDeploy.deployUnderlyingSnapshot(vm, rootCode, shardCodes);
        for (uint256 i = 0; i < rows.length; i++) {
            assertReadsBack(root, 0, rows[i]);
        }
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

    /// One-byte fields, so EIP-170 never binds before the 256-word parse meta limit.
    function shortRows(uint256 n) internal pure returns (UnderlyingSnapshotRow[] memory) {
        UnderlyingSnapshotRow[] memory rows = new UnderlyingSnapshotRow[](n);
        for (uint256 i = 0; i < n; i++) {
            address token = address(uint160(uint256(keccak256(abi.encode("short row", i)))));
            rows[i] = UnderlyingSnapshotRow(token, "T", "N", "I");
        }
        return rows;
    }

    function testParseMetaWordLimitBoundsTheShardCount() external {
        (, bytes[] memory atLimit) = LibUnderlyingSnapshotBuilder.build(0, shortRows(256));
        assertEq(atLimit.length, 1, "256 rows");
        (, bytes[] memory pastLimit) = LibUnderlyingSnapshotBuilder.build(0, shortRows(257));
        assertEq(pastLimit.length, 2, "257 rows");
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

    function readUint(bytes memory data, uint256 start, uint256 length) internal pure returns (uint256) {
        uint256 value = 0;
        for (uint256 i = 0; i < length; i++) {
            value = value << 8 | uint8(data[start + i]);
        }
        return value;
    }

    function slice(bytes memory data, uint256 start, uint256 length) internal pure returns (bytes memory) {
        bytes memory out = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            out[i] = data[start + i];
        }
        return out;
    }

    /// Asserts a one-byte length then `field` at `at`; returns the next position.
    function assertFieldAt(bytes memory data, uint256 at, string memory field, string memory label)
        internal
        pure
        returns (uint256)
    {
        uint256 length = bytes(field).length;
        assertEq(readUint(data, at, 1), length, label);
        assertEq(slice(data, at + 1, length), bytes(field), label);
        return at + 1 + length;
    }

    function testRootIsItsHeaderThenOneAddressPerShard(uint256 asOf, address[] memory shards) external pure {
        bytes memory data = LibUnderlyingSnapshotBuilder.rootData(asOf, shards);
        assertEq(data.length, 4 + 32 + 2 + 20 * shards.length, "length");
        assertEq(readUint(data, 0, 4), uint32(UNDERLYING_SNAPSHOT_ROOT_MAGIC), "magic");
        assertEq(readUint(data, 4, 32), asOf, "asOf");
        assertEq(readUint(data, 36, 2), shards.length, "shard count");
        for (uint256 i = 0; i < shards.length; i++) {
            assertEq(readUint(data, 38 + 20 * i, 20), uint160(shards[i]), "shard");
        }
    }

    function testShardIsItsHeaderThenMetaOffsetsAndRows(bytes32 seed, uint8 count) external pure {
        UnderlyingSnapshotRow[] memory rows = LibTestUnderlyingSnapshotRows.rowsFrom(vm, seed, bound(count, 0, 40));
        AuthoringMetaV2[] memory words = new AuthoringMetaV2[](rows.length);
        for (uint256 i = 0; i < rows.length; i++) {
            words[i] = AuthoringMetaV2(bytes32(uint256(uint160(rows[i].token))), "");
        }
        bytes memory meta = LibGenParseMeta.buildParseMetaV2(words, UNDERLYING_SNAPSHOT_META_DEPTH);
        bytes memory data = LibUnderlyingSnapshotBuilder.shardData(rows);
        assertEq(readUint(data, 0, 4), uint32(UNDERLYING_SNAPSHOT_SHARD_MAGIC), "magic");
        assertEq(readUint(data, 4, 2), rows.length, "row count");
        assertEq(readUint(data, 6, 2), meta.length, "meta length");
        assertEq(slice(data, 8, meta.length), meta, "meta");
        uint256 offsets = 8 + meta.length;
        uint256 at = offsets + 2 * rows.length;
        for (uint256 i = 0; i < rows.length; i++) {
            assertEq(readUint(data, offsets + 2 * i, 2), at, "offset");
            assertEq(readUint(data, at, 20), uint160(rows[i].token), "token");
            at = assertFieldAt(data, at + 20, rows[i].ticker, "ticker");
            at = assertFieldAt(data, at, rows[i].name, "name");
            at = assertFieldAt(data, at, rows[i].isin, "isin");
        }
        assertEq(data.length, at, "length");
    }
}

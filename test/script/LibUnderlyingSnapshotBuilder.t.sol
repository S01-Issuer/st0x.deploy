// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {PREFIX_BYTES_LENGTH} from "rain-datacontract-0.2.1/src/lib/LibDataContract.sol";
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
    EIP170_MAX_RUNTIME
} from "../../script/LibUnderlyingSnapshotBuilder.sol";
import {LibTestDeploy} from "../lib/LibTestDeploy.sol";
import {LibTestUnderlyingSnapshotRows} from "../lib/LibTestUnderlyingSnapshotRows.sol";

contract LibUnderlyingSnapshotBuilderTest is Test {
    function build(uint256 asOf, UnderlyingSnapshotRow[] memory rows)
        external
        pure
        returns (bytes memory, bytes[] memory)
    {
        return LibUnderlyingSnapshotBuilder.build(asOf, rows);
    }

    function shardData(UnderlyingSnapshotRow[] memory rows, uint256 k) external pure returns (bool, bytes memory) {
        return LibUnderlyingSnapshotBuilder.shardData(rows, k);
    }

    function filled(uint256 length) internal pure returns (string memory) {
        bytes memory out = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            out[i] = "A";
        }
        return string(out);
    }

    /// field 0, 1, 2 is the ticker, name, ISIN.
    function setField(UnderlyingSnapshotRow memory row, uint256 field, uint256 length) internal pure {
        if (field == 0) row.ticker = filled(length);
        else if (field == 1) row.name = filled(length);
        else row.isin = filled(length);
    }

    function rowWithField(address token, uint256 field, uint256 length)
        internal
        pure
        returns (UnderlyingSnapshotRow memory)
    {
        UnderlyingSnapshotRow memory row = UnderlyingSnapshotRow(token, "AAPL", "Apple Inc.", "US0378331005");
        setField(row, field, length);
        return row;
    }

    /// Gives row `j` row `i`'s token, `i` and `j` bounded to distinct rows.
    function duplicateToken(UnderlyingSnapshotRow[] memory rows, uint256 i, uint256 j) internal pure {
        i = bound(i, 0, rows.length - 1);
        j = bound(j, 0, rows.length - 2);
        if (j >= i) j++;
        rows[j].token = rows[i].token;
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

    function assertEveryRowReadsBack(
        uint256 asOf,
        UnderlyingSnapshotRow[] memory rows,
        bytes memory rootCode,
        bytes[] memory shardCodes
    ) internal {
        address root = LibTestDeploy.deployUnderlyingSnapshot(vm, rootCode, shardCodes);
        for (uint256 i = 0; i < rows.length; i++) {
            assertReadsBack(root, asOf, rows[i]);
        }
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
        assertEveryRowReadsBack(0, rows, rootCode, shardCodes);
    }

    function testEmptyIsinEndingTheShardReadsBack(address token) external {
        UnderlyingSnapshotRow memory row = rowWithField(token, 2, 0);
        (bytes memory rootCode, bytes[] memory shardCodes) = LibUnderlyingSnapshotBuilder.build(0, one(row));
        assertEq(shardCodes.length, 1, "shard count");
        bytes memory shardCode = shardCodes[0];
        assertEq(uint8(shardCode[shardCode.length - 1]), 0, "ISIN length is the last byte");
        assertReadsBack(LibTestDeploy.deployUnderlyingSnapshot(vm, rootCode, shardCodes), 0, row);
    }

    function testFieldOver255BytesReverts(address token, uint256 field, uint256 length, uint256 k) external {
        length = bound(length, uint256(type(uint8).max) + 1, 1024);
        UnderlyingSnapshotRow[] memory rows = one(rowWithField(token, bound(field, 0, 2), length));
        vm.expectRevert(abi.encodeWithSelector(UnderlyingSnapshotFieldTooLong.selector, token, length));
        this.shardData(rows, bound(k, 1, type(uint16).max));
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

    function testDuplicateTokenDoesNotFitAShard(bytes32 seed, uint256 count, uint256 i, uint256 j, uint256 k)
        external
        pure
    {
        UnderlyingSnapshotRow[] memory rows = LibTestUnderlyingSnapshotRows.rowsFrom(vm, seed, bound(count, 2, 40));
        duplicateToken(rows, i, j);
        (bool fits, bytes memory data) = LibUnderlyingSnapshotBuilder.shardData(rows, bound(k, 1, type(uint16).max));
        assertFalse(fits, "fits");
        assertEq(data.length, 0, "data");
    }

    function overLong(uint256 length) internal pure returns (uint256) {
        return bound(length, uint256(type(uint8).max) + 1, 1024);
    }

    /// Sets each field after row `first` whose bit in `later` is set over 255 bytes.
    function overLongAfter(UnderlyingSnapshotRow[] memory rows, uint256 first, uint256 later) internal pure {
        for (uint256 r = first + 1; r < rows.length; r++) {
            for (uint256 f = 0; f < 3; f++) {
                if ((later >> (3 * r + f)) & 1 == 1) {
                    setField(rows[r], f, overLong(uint256(keccak256(abi.encode(later, r, f)))));
                }
            }
        }
    }

    function testFirstOffendingRowNamesFieldTooLongOverDuplicateToken(
        bytes32 seed,
        uint256 count,
        uint256 i,
        uint256 j,
        uint256 first,
        uint256 field,
        uint256 length,
        uint256 later
    ) external {
        UnderlyingSnapshotRow[] memory rows = LibTestUnderlyingSnapshotRows.rowsFrom(vm, seed, bound(count, 2, 40));
        duplicateToken(rows, i, j);
        first = bound(first, 0, rows.length - 1);
        length = overLong(length);
        setField(rows[first], bound(field, 0, 2), length);
        overLongAfter(rows, first, later);
        vm.expectRevert(abi.encodeWithSelector(UnderlyingSnapshotFieldTooLong.selector, rows[first].token, length));
        this.build(0, rows);
    }

    /// Fields run in row order, then ticker, name, ISIN within a row.
    function testFirstOverLongFieldWinsOverALaterOne(
        bytes32 seed,
        uint256 count,
        uint256 i,
        uint256 j,
        uint256 a,
        uint256 b,
        uint256 lengthA,
        uint256 lengthB
    ) external {
        UnderlyingSnapshotRow[] memory rows = LibTestUnderlyingSnapshotRows.rowsFrom(vm, seed, bound(count, 2, 40));
        duplicateToken(rows, i, j);
        a = bound(a, 0, 3 * rows.length - 2);
        b = bound(b, a + 1, 3 * rows.length - 1);
        lengthA = overLong(lengthA);
        lengthB = bound(lengthB, uint256(type(uint8).max) + 1, 1023);
        if (lengthB >= lengthA) lengthB++;
        setField(rows[a / 3], a % 3, lengthA);
        setField(rows[b / 3], b % 3, lengthB);
        vm.expectRevert(abi.encodeWithSelector(UnderlyingSnapshotFieldTooLong.selector, rows[a / 3].token, lengthA));
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

    function testManyShortRowsShareOneShard() external {
        UnderlyingSnapshotRow[] memory rows = new UnderlyingSnapshotRow[](600);
        for (uint256 i = 0; i < rows.length; i++) {
            address token = address(uint160(uint256(keccak256(abi.encode("short row", i)))));
            rows[i] = UnderlyingSnapshotRow(token, "T", "N", "I");
        }
        (bytes memory rootCode, bytes[] memory shardCodes) = LibUnderlyingSnapshotBuilder.build(0, rows);
        assertEq(shardCodes.length, 1, "shard count");
        assertEveryRowReadsBack(0, rows, rootCode, shardCodes);
    }

    /// 31 rows of 255-byte fields and a last row whose name is sized so one
    /// shard's runtime is `extra` bytes over the EIP-170 limit.
    function rowsOverEip170By(uint256 extra) internal pure returns (UnderlyingSnapshotRow[] memory) {
        UnderlyingSnapshotRow[] memory rows = new UnderlyingSnapshotRow[](32);
        for (uint256 i = 0; i < rows.length; i++) {
            rows[i] = UnderlyingSnapshotRow(
                address(uint160(uint256(keccak256(abi.encode(i))))), filled(255), filled(255), filled(255)
            );
        }
        rows[31] = UnderlyingSnapshotRow(rows[31].token, "", "", "");
        (bool fits, bytes memory data) = LibUnderlyingSnapshotBuilder.shardData(rows, 1);
        assertTrue(fits, "rows too long");
        uint256 grow = EIP170_MAX_RUNTIME + extra - (data.length + 1);
        assertLe(grow, 255, "rows too short");
        rows[31].name = filled(grow);
        (fits, data) = LibUnderlyingSnapshotBuilder.shardData(rows, 1);
        assertEq(fits, extra == 0, "fits");
        if (fits) assertEq(data.length + 1, EIP170_MAX_RUNTIME, "sized");
        return rows;
    }

    function testShardFillingEip170ExactlyFitsOneShard() external {
        UnderlyingSnapshotRow[] memory rows = rowsOverEip170By(0);
        (bytes memory rootCode, bytes[] memory shardCodes) = LibUnderlyingSnapshotBuilder.build(0, rows);
        assertEq(shardCodes.length, 1, "shard count");
        assertEq(shardCodes[0].length - (PREFIX_BYTES_LENGTH - 1), EIP170_MAX_RUNTIME, "runtime");
        assertEveryRowReadsBack(0, rows, rootCode, shardCodes);
    }

    function testShardOneByteOverEip170Splits() external {
        UnderlyingSnapshotRow[] memory rows = rowsOverEip170By(1);
        (bytes memory rootCode, bytes[] memory shardCodes) = LibUnderlyingSnapshotBuilder.build(0, rows);
        assertEq(shardCodes.length, 2, "shard count");
        assertEveryRowReadsBack(0, rows, rootCode, shardCodes);
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

    /// Asserts `rows` in input order from `at` to the end of `data`; returns where each starts.
    function assertRowsFrom(bytes memory data, uint256 at, UnderlyingSnapshotRow[] memory rows)
        internal
        pure
        returns (uint256[] memory)
    {
        uint256[] memory starts = new uint256[](rows.length);
        for (uint256 i = 0; i < rows.length; i++) {
            starts[i] = at;
            assertEq(readUint(data, at, 20), uint160(rows[i].token), "token");
            at = assertFieldAt(data, at + 20, rows[i].ticker, "ticker");
            at = assertFieldAt(data, at, rows[i].name, "name");
            at = assertFieldAt(data, at, rows[i].isin, "isin");
        }
        assertEq(data.length, at, "length");
        return starts;
    }

    function bucketsOf(UnderlyingSnapshotRow[] memory rows, uint256 k, uint256 bucketCount)
        internal
        pure
        returns (uint256[] memory)
    {
        uint256[] memory buckets = new uint256[](rows.length);
        for (uint256 i = 0; i < rows.length; i++) {
            buckets[i] = (uint256(uint160(rows[i].token)) / k) % bucketCount;
        }
        return buckets;
    }

    function slotOf(address token, bytes1 displacement, uint256 slotCount) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(token, displacement))) % slotCount;
    }

    /// Whether `bucket`'s tokens land on distinct slots not yet `taken`; takes them if so.
    function take(
        UnderlyingSnapshotRow[] memory rows,
        uint256[] memory buckets,
        uint256 bucket,
        bytes1 displacement,
        bool[] memory taken
    ) internal pure returns (bool) {
        bool[] memory mine = new bool[](taken.length);
        for (uint256 i = 0; i < rows.length; i++) {
            if (buckets[i] != bucket) continue;
            uint256 slot = slotOf(rows[i].token, displacement, taken.length);
            if (taken[slot] || mine[slot]) return false;
            mine[slot] = true;
        }
        for (uint256 s = 0; s < taken.length; s++) {
            taken[s] = taken[s] || mine[s];
        }
        return true;
    }

    /// The unplaced bucket with the most rows, the lowest index on ties.
    function nextBucket(uint256[] memory buckets, bool[] memory placed) internal pure returns (uint256) {
        uint256 best = type(uint256).max;
        uint256 bestSize = 0;
        for (uint256 b = 0; b < placed.length; b++) {
            if (placed[b]) continue;
            uint256 size = 0;
            for (uint256 i = 0; i < buckets.length; i++) {
                if (buckets[i] == b) size++;
            }
            if (best == type(uint256).max || size > bestSize) {
                best = b;
                bestSize = size;
            }
        }
        return best;
    }

    /// Each bucket, largest first, takes the first displacement placing its
    /// tokens on distinct free slots; false when a bucket has none.
    function displacementsAt(UnderlyingSnapshotRow[] memory rows, uint256 k, uint256 bucketCount, uint256 slotCount)
        internal
        pure
        returns (bool, bytes memory)
    {
        uint256[] memory buckets = bucketsOf(rows, k, bucketCount);
        bytes memory displacements = new bytes(bucketCount);
        bool[] memory placed = new bool[](bucketCount);
        bool[] memory taken = new bool[](slotCount);
        for (uint256 round = 0; round < bucketCount; round++) {
            uint256 bucket = nextBucket(buckets, placed);
            placed[bucket] = true;
            uint256 d = 0;
            // forge-lint: disable-next-line(unsafe-typecast)
            while (d <= type(uint8).max && !take(rows, buckets, bucket, bytes1(uint8(d)), taken)) d++;
            // forge-lint: disable-next-line(boolean-cst)
            if (d > type(uint8).max) return (false, displacements);
            // forge-lint: disable-next-line(unsafe-typecast)
            displacements[bucket] = bytes1(uint8(d));
        }
        // forge-lint: disable-next-line(boolean-cst)
        return (true, displacements);
    }

    /// Asserts `data` is `rows`' shard at routing divisor `k`; returns its slot count.
    function assertShardOf(UnderlyingSnapshotRow[] memory rows, uint256 k, bytes memory data)
        internal
        pure
        returns (uint256)
    {
        assertEq(readUint(data, 0, 4), uint32(UNDERLYING_SNAPSHOT_SHARD_MAGIC), "magic");
        assertEq(readUint(data, 4, 2), rows.length, "row count");
        uint256 bucketCount = readUint(data, 6, 2);
        uint256 slotCount = readUint(data, 8, 2);
        assertEq(bucketCount, rows.length == 0 ? 1 : (rows.length + 3) / 4, "bucket count");
        assertEq(
            slice(data, 10, bucketCount), firstPlacingDisplacements(rows, k, bucketCount, slotCount), "displacements"
        );
        assertSlotsOwnTheirRows(rows, k, data, bucketCount, slotCount);
        return slotCount;
    }

    /// Asserts no slot count from the minimum up to `slotCount` places every bucket, and returns the placement at it.
    function firstPlacingDisplacements(
        UnderlyingSnapshotRow[] memory rows,
        uint256 k,
        uint256 bucketCount,
        uint256 slotCount
    ) internal pure returns (bytes memory) {
        uint256 minSlots = rows.length == 0 ? 1 : (12 * rows.length + 9) / 10;
        assertGe(slotCount, minSlots, "slot count");
        for (uint256 m = minSlots; m < slotCount; m++) {
            (bool placesAll,) = displacementsAt(rows, k, bucketCount, m);
            assertFalse(placesAll, "a smaller slot count places every bucket");
        }
        (bool fits, bytes memory expected) = displacementsAt(rows, k, bucketCount, slotCount);
        assertTrue(fits, "slot count places every bucket");
        return expected;
    }

    /// Asserts each row's slot holds its absolute offset and every other slot is 0.
    function assertSlotsOwnTheirRows(
        UnderlyingSnapshotRow[] memory rows,
        uint256 k,
        bytes memory data,
        uint256 bucketCount,
        uint256 slotCount
    ) internal pure {
        uint256 offsets = 10 + bucketCount;
        uint256[] memory rowStarts = assertRowsFrom(data, offsets + 2 * slotCount, rows);
        uint256 owned = 0;
        for (uint256 s = 0; s < slotCount; s++) {
            if (readUint(data, offsets + 2 * s, 2) != 0) owned++;
        }
        assertEq(owned, rows.length, "owned slots");
        uint256[] memory buckets = bucketsOf(rows, k, bucketCount);
        for (uint256 i = 0; i < rows.length; i++) {
            uint256 slot = slotOf(rows[i].token, data[10 + buckets[i]], slotCount);
            assertEq(readUint(data, offsets + 2 * slot, 2), rowStarts[i], "slot offset");
        }
    }

    function testShardIsItsHeaderThenDisplacementsSlotOffsetsAndRows(bytes32 seed, uint8 count, uint256 k)
        external
        pure
    {
        k = bound(k, 1, type(uint16).max);
        UnderlyingSnapshotRow[] memory rows = LibTestUnderlyingSnapshotRows.rowsFrom(vm, seed, bound(count, 0, 40));
        (bool fits, bytes memory data) = LibUnderlyingSnapshotBuilder.shardData(rows, k);
        assertTrue(fits, "fits");
        assertShardOf(rows, k, data);
    }

    /// 12 rows whose tokens all route to bucket 0 of 3, so 12 tokens share
    /// one displacement over as few as 15 slots.
    function oneBucketRows(bytes32 seed) internal pure returns (UnderlyingSnapshotRow[] memory) {
        UnderlyingSnapshotRow[] memory rows = LibTestUnderlyingSnapshotRows.rowsFrom(vm, seed, 12);
        for (uint256 i = 0; i < rows.length; i++) {
            rows[i].token = address(uint160(rows[i].token) / 3 * 3);
        }
        return rows;
    }

    function testCrowdedBucketGetsTheFirstSlotCountThatPlacesIt(bytes32 seed) external pure {
        UnderlyingSnapshotRow[] memory rows = oneBucketRows(seed);
        (bool fits, bytes memory data) = LibUnderlyingSnapshotBuilder.shardData(rows, 1);
        assertTrue(fits, "fits");
        assertShardOf(rows, 1, data);
    }

    function testSlotCountGrowsWhenNoDisplacementPlacesABucket() external pure {
        UnderlyingSnapshotRow[] memory rows = oneBucketRows(bytes32(0));
        (bool fits, bytes memory data) = LibUnderlyingSnapshotBuilder.shardData(rows, 1);
        assertTrue(fits, "fits");
        assertGt(assertShardOf(rows, 1, data), 15, "slot count");
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
}

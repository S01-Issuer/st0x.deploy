// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibRainDeploy} from "rain-deploy-0.1.43/src/lib/LibRainDeploy.sol";
import {LibDataContract} from "rain-datacontract-0.2.1/src/lib/LibDataContract.sol";
import {Arrays} from "@openzeppelin-contracts-5.7.0/utils/Arrays.sol";
import {
    UNDERLYING_SNAPSHOT_ROOT_MAGIC,
    UNDERLYING_SNAPSHOT_ROOT_HEADER_LENGTH,
    UNDERLYING_SNAPSHOT_SHARD_MAGIC,
    UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH
} from "../src/lib/LibUnderlyingSnapshot.sol";

uint256 constant EIP170_MAX_RUNTIME = 24576;

/// @notice No shard count whose root fits EIP-170 fits every shard.
error UnderlyingSnapshotDoesNotShard(uint256 rows);

/// @notice A row field is longer than its one-byte length prefix can encode.
error UnderlyingSnapshotFieldTooLong(address token, uint256 length);

struct UnderlyingSnapshotRow {
    address token;
    string ticker;
    string name;
    string isin;
}

library LibUnderlyingSnapshotBuilder {
    function shardData(UnderlyingSnapshotRow[] memory rows, uint256 k) internal pure returns (bool, bytes memory) {
        // Equal tokens share every slot, so no displacement or slot count separates them.
        if (hasDuplicate(rows)) {
            // forge-lint: disable-next-line(boolean-cst)
            return (false, "");
        }
        return distinctShardData(rows, k);
    }

    function distinctShardData(UnderlyingSnapshotRow[] memory rows, uint256 k)
        internal
        pure
        returns (bool, bytes memory)
    {
        (bytes memory body, uint256[] memory rowStarts) = encodeRows(rows);
        (uint256[] memory order, uint256[][] memory bucketRows) = bucketsOf(rows, k);
        (bool fits, bytes memory displacements, uint256[] memory slotRows) = index(rows, bucketRows, order, body.length);
        if (!fits) {
            // forge-lint: disable-next-line(boolean-cst)
            return (false, "");
        }
        // forge-lint: disable-next-line(boolean-cst)
        return (true, encodeShard(rows.length, displacements, slotRows, rowStarts, body));
    }

    function bucketCountOf(uint256 rowCount) internal pure returns (uint256) {
        return rowCount == 0 ? 1 : (rowCount + 3) / 4;
    }

    function minSlotCount(uint256 rowCount) internal pure returns (uint256) {
        return rowCount == 0 ? 1 : (12 * rowCount + 9) / 10;
    }

    function bucketsOf(UnderlyingSnapshotRow[] memory rows, uint256 k)
        internal
        pure
        returns (uint256[] memory, uint256[][] memory)
    {
        uint256 bucketCount = bucketCountOf(rows.length);
        uint256[] memory rowBuckets = new uint256[](rows.length);
        uint256[] memory sizes = new uint256[](bucketCount);
        for (uint256 i = 0; i < rows.length; i++) {
            rowBuckets[i] = (uint256(uint160(rows[i].token)) / k) % bucketCount;
            sizes[rowBuckets[i]]++;
        }
        uint256[] memory order = bucketOrder(sizes);
        uint256[][] memory bucketRows = new uint256[][](bucketCount);
        for (uint256 b = 0; b < bucketCount; b++) {
            bucketRows[b] = new uint256[](sizes[b]);
            sizes[b] = 0;
        }
        for (uint256 i = 0; i < rows.length; i++) {
            uint256 b = rowBuckets[i];
            bucketRows[b][sizes[b]++] = i;
        }
        return (order, bucketRows);
    }

    function hasDuplicate(UnderlyingSnapshotRow[] memory rows) internal pure returns (bool) {
        address[] memory tokens = new address[](rows.length);
        for (uint256 i = 0; i < rows.length; i++) {
            tokens[i] = rows[i].token;
        }
        Arrays.sort(tokens);
        for (uint256 i = 1; i < tokens.length; i++) {
            if (tokens[i] == tokens[i - 1]) {
                return true;
            }
        }
        return false;
    }

    function rowLength(UnderlyingSnapshotRow memory row) internal pure returns (uint256) {
        uint256 length = 23;
        length += fieldLength(row.token, row.ticker);
        length += fieldLength(row.token, row.name);
        length += fieldLength(row.token, row.isin);
        return length;
    }

    function encodeRows(UnderlyingSnapshotRow[] memory rows) internal pure returns (bytes memory, uint256[] memory) {
        uint256[] memory rowStarts = new uint256[](rows.length);
        uint256 length = 0;
        for (uint256 i = 0; i < rows.length; i++) {
            rowStarts[i] = length;
            length += rowLength(rows[i]);
        }
        bytes memory body = new bytes(length);
        for (uint256 i = 0; i < rows.length; i++) {
            writeRow(body, rowStarts[i], rows[i]);
        }
        return (body, rowStarts);
    }

    function writeRow(bytes memory body, uint256 start, UnderlyingSnapshotRow memory row) internal pure {
        address token = row.token;
        uint256 cursor;
        assembly ("memory-safe") {
            cursor := add(add(body, 0x20), start)
            mstore(0, shl(96, token))
            mcopy(cursor, 0, 20)
            cursor := add(cursor, 20)
        }
        cursor = writeField(cursor, bytes(row.ticker));
        cursor = writeField(cursor, bytes(row.name));
        writeField(cursor, bytes(row.isin));
    }

    function writeField(uint256 cursor, bytes memory field) internal pure returns (uint256) {
        assembly ("memory-safe") {
            let length := mload(field)
            mstore8(cursor, length)
            mcopy(add(cursor, 1), add(field, 0x20), length)
            cursor := add(add(cursor, 1), length)
        }
        return cursor;
    }

    function bucketOrder(uint256[] memory sizes) internal pure returns (uint256[] memory) {
        uint256[] memory order = new uint256[](sizes.length);
        for (uint256 i = 0; i < sizes.length; i++) {
            uint256 j = i;
            while (j > 0 && sizes[order[j - 1]] < sizes[i]) {
                order[j] = order[j - 1];
                j--;
            }
            order[j] = i;
        }
        return order;
    }

    function index(
        UnderlyingSnapshotRow[] memory rows,
        uint256[][] memory bucketRows,
        uint256[] memory order,
        uint256 bodyLength
    ) internal pure returns (bool, bytes memory, uint256[] memory) {
        uint256 fixedLength =
            UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH + order.length + bodyLength + 1;
        uint256 slotCount = minSlotCount(rows.length);
        if (fixedLength + 2 * slotCount <= EIP170_MAX_RUNTIME) {
            uint256 maxSlotCount = (EIP170_MAX_RUNTIME - fixedLength) / 2;
            bytes memory displacements = new bytes(order.length);
            uint256[] memory slotRows = new uint256[](maxSlotCount);
            uint256[] memory rowSlots = new uint256[](rows.length);
            for (; slotCount <= maxSlotCount; slotCount++) {
                assembly ("memory-safe") {
                    mstore(slotRows, slotCount)
                }
                if (place(rows, bucketRows, order, displacements, slotRows, rowSlots)) {
                    // forge-lint: disable-next-line(boolean-cst)
                    return (true, displacements, slotRows);
                }
            }
        }
        // forge-lint: disable-next-line(boolean-cst)
        return (false, "", new uint256[](0));
    }

    function place(
        UnderlyingSnapshotRow[] memory rows,
        uint256[][] memory bucketRows,
        uint256[] memory order,
        bytes memory displacements,
        uint256[] memory slotRows,
        uint256[] memory rowSlots
    ) internal pure returns (bool) {
        for (uint256 s = 0; s < slotRows.length; s++) {
            slotRows[s] = 0;
        }
        for (uint256 o = 0; o < order.length; o++) {
            bool placed = false;
            for (uint256 d = 0; d <= type(uint8).max && !placed; d++) {
                // forge-lint: disable-next-line(unsafe-typecast)
                placed = displace(rows, bucketRows[order[o]], bytes1(uint8(d)), slotRows, rowSlots);
                if (placed) {
                    // forge-lint: disable-next-line(unsafe-typecast)
                    displacements[order[o]] = bytes1(uint8(d));
                }
            }
            if (!placed) {
                return false;
            }
        }
        return true;
    }

    function displace(
        UnderlyingSnapshotRow[] memory rows,
        uint256[] memory members,
        bytes1 displacement,
        uint256[] memory slotRows,
        uint256[] memory rowSlots
    ) internal pure returns (bool) {
        for (uint256 m = 0; m < members.length; m++) {
            uint256 i = members[m];
            address token = rows[i].token;
            uint256 hash;
            // keccak256(abi.encodePacked(token, displacement)) in scratch space, so probes allocate nothing.
            assembly ("memory-safe") {
                mstore(0, shl(96, token))
                mstore8(20, shr(248, displacement))
                hash := keccak256(0, 21)
            }
            uint256 slot = hash % slotRows.length;
            if (slotRows[slot] != 0) {
                for (uint256 j = 0; j < m; j++) {
                    slotRows[rowSlots[members[j]]] = 0;
                }
                return false;
            }
            slotRows[slot] = i + 1;
            rowSlots[i] = slot;
        }
        return true;
    }

    function encodeShard(
        uint256 rowCount,
        bytes memory displacements,
        uint256[] memory slotRows,
        uint256[] memory rowStarts,
        bytes memory body
    ) internal pure returns (bytes memory) {
        uint256 rowsStart = UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH + displacements.length + 2 * slotRows.length;
        bytes memory offsets = new bytes(2 * slotRows.length);
        for (uint256 s = 0; s < slotRows.length; s++) {
            if (slotRows[s] != 0) {
                // index rejects any shard whose data passes EIP-170, far below 2^16.
                // forge-lint: disable-next-line(unsafe-typecast)
                bytes2 offset = bytes2(uint16(rowsStart + rowStarts[slotRows[s] - 1]));
                offsets[2 * s] = offset[0];
                offsets[2 * s + 1] = offset[1];
            }
        }
        return abi.encodePacked(
            UNDERLYING_SNAPSHOT_SHARD_MAGIC,
            // forge-lint: disable-next-line(unsafe-typecast)
            uint16(rowCount),
            // forge-lint: disable-next-line(unsafe-typecast)
            uint16(displacements.length),
            // forge-lint: disable-next-line(unsafe-typecast)
            uint16(slotRows.length),
            displacements,
            offsets,
            body
        );
    }

    function fieldLength(address token, string memory field) internal pure returns (uint8) {
        uint256 length = bytes(field).length;
        if (length > type(uint8).max) {
            revert UnderlyingSnapshotFieldTooLong(token, length);
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint8(length);
    }

    function rootData(uint256 asOf, address[] memory shards) internal pure returns (bytes memory) {
        bytes memory out = abi.encodePacked(UNDERLYING_SNAPSHOT_ROOT_MAGIC, asOf, uint16(shards.length));
        for (uint256 i = 0; i < shards.length; i++) {
            out = abi.encodePacked(out, shards[i]);
        }
        return out;
    }

    /// Smallest shard count K for which every shard fits EIP-170; rows route
    /// to shard `uint160(token) % K`.
    function build(uint256 asOf, UnderlyingSnapshotRow[] memory rows)
        internal
        pure
        returns (bytes memory, bytes[] memory)
    {
        uint256[] memory rowLengths = new uint256[](rows.length);
        uint256 total = 0;
        for (uint256 i = 0; i < rows.length; i++) {
            rowLengths[i] = rowLength(rows[i]);
            total += rowLengths[i] + 2;
        }
        // Field validity is per row and independent of sharding, so it is checked before duplicates.
        if (hasDuplicate(rows)) {
            revert UnderlyingSnapshotDoesNotShard(rows.length);
        }
        // A shard holds its header, at least one bucket byte, the data prefix, and per row its bytes plus >= 2 offset bytes.
        uint256 capacity = EIP170_MAX_RUNTIME - UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH - 2;
        uint256 k = (total + capacity - 1) / capacity;
        for (k = k == 0 ? 1 : k; k <= (EIP170_MAX_RUNTIME - 1 - UNDERLYING_SNAPSHOT_ROOT_HEADER_LENGTH) / 20; k++) {
            (bool fits, bytes[] memory shardCodes) = shardCodesOf(rows, rowLengths, k);
            if (fits) {
                address[] memory shards = new address[](k);
                for (uint256 s = 0; s < k; s++) {
                    shards[s] = LibRainDeploy.zoltuAddress(shardCodes[s]);
                }
                return (LibDataContract.contractCreationCode(rootData(asOf, shards)), shardCodes);
            }
        }
        revert UnderlyingSnapshotDoesNotShard(rows.length);
    }

    function shardCodesOf(UnderlyingSnapshotRow[] memory rows, uint256[] memory rowLengths, uint256 k)
        internal
        pure
        returns (bool, bytes[] memory)
    {
        uint256[] memory counts = new uint256[](k);
        uint256[] memory bodyLengths = new uint256[](k);
        for (uint256 i = 0; i < rows.length; i++) {
            uint256 s = uint256(uint160(rows[i].token)) % k;
            counts[s]++;
            bodyLengths[s] += rowLengths[i];
        }
        for (uint256 s = 0; s < k; s++) {
            if (
                UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH + bucketCountOf(counts[s]) + 2 * minSlotCount(counts[s])
                        + bodyLengths[s] + 1 > EIP170_MAX_RUNTIME
            ) {
                // forge-lint: disable-next-line(boolean-cst)
                return (false, new bytes[](0));
            }
        }
        UnderlyingSnapshotRow[][] memory members = new UnderlyingSnapshotRow[][](k);
        for (uint256 s = 0; s < k; s++) {
            members[s] = new UnderlyingSnapshotRow[](counts[s]);
            counts[s] = 0;
        }
        for (uint256 i = 0; i < rows.length; i++) {
            uint256 s = uint256(uint160(rows[i].token)) % k;
            members[s][counts[s]++] = rows[i];
        }
        bytes[] memory shardCodes = new bytes[](k);
        for (uint256 s = 0; s < k; s++) {
            (bool fits, bytes memory data) = distinctShardData(members[s], k);
            if (!fits) {
                // forge-lint: disable-next-line(boolean-cst)
                return (false, new bytes[](0));
            }
            shardCodes[s] = LibDataContract.contractCreationCode(data);
        }
        // forge-lint: disable-next-line(boolean-cst)
        return (true, shardCodes);
    }
}

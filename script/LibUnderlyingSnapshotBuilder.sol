// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibRainDeploy} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";
import {LibDataContract} from "rain-datacontract-0.2.1/src/lib/LibDataContract.sol";
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
            return (false, "");
        }
        (bytes memory body, uint256[] memory rowStarts) = encodeRows(rows);
        (uint256[] memory rowBuckets, uint256[] memory order) = bucketsOf(rows, k);
        (bool fits, bytes memory displacements, uint256[] memory slotRows) =
            index(rows, rowBuckets, order, body.length);
        if (!fits) {
            return (false, "");
        }
        return (true, encodeShard(rows.length, displacements, slotRows, rowStarts, body));
    }

    function bucketsOf(UnderlyingSnapshotRow[] memory rows, uint256 k)
        internal
        pure
        returns (uint256[] memory, uint256[] memory)
    {
        uint256 bucketCount = rows.length == 0 ? 1 : (rows.length + 3) / 4;
        uint256[] memory rowBuckets = new uint256[](rows.length);
        uint256[] memory sizes = new uint256[](bucketCount);
        for (uint256 i = 0; i < rows.length; i++) {
            rowBuckets[i] = (uint256(uint160(rows[i].token)) / k) % bucketCount;
            sizes[rowBuckets[i]]++;
        }
        return (rowBuckets, bucketOrder(sizes));
    }

    function hasDuplicate(UnderlyingSnapshotRow[] memory rows) internal pure returns (bool) {
        for (uint256 i = 0; i < rows.length; i++) {
            for (uint256 j = i + 1; j < rows.length; j++) {
                if (rows[i].token == rows[j].token) {
                    return true;
                }
            }
        }
        return false;
    }

    function encodeRows(UnderlyingSnapshotRow[] memory rows) internal pure returns (bytes memory, uint256[] memory) {
        bytes memory body;
        uint256[] memory rowStarts = new uint256[](rows.length);
        for (uint256 i = 0; i < rows.length; i++) {
            rowStarts[i] = body.length;
            body = abi.encodePacked(
                body,
                rows[i].token,
                fieldLength(rows[i].token, rows[i].ticker),
                rows[i].ticker,
                fieldLength(rows[i].token, rows[i].name),
                rows[i].name,
                fieldLength(rows[i].token, rows[i].isin),
                rows[i].isin
            );
        }
        return (body, rowStarts);
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
        uint256[] memory rowBuckets,
        uint256[] memory order,
        uint256 bodyLength
    ) internal pure returns (bool, bytes memory, uint256[] memory) {
        for (
            uint256 slotCount = rows.length == 0 ? 1 : (12 * rows.length + 9) / 10;
            UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH + order.length + 2 * slotCount + bodyLength + 1
                <= EIP170_MAX_RUNTIME;
            slotCount++
        ) {
            (bool placed, bytes memory displacements, uint256[] memory slotRows) =
                place(rows, rowBuckets, order, slotCount);
            if (placed) {
                return (true, displacements, slotRows);
            }
        }
        return (false, "", new uint256[](0));
    }

    function place(
        UnderlyingSnapshotRow[] memory rows,
        uint256[] memory rowBuckets,
        uint256[] memory order,
        uint256 slotCount
    ) internal pure returns (bool, bytes memory, uint256[] memory) {
        bytes memory displacements = new bytes(order.length);
        uint256[] memory slotRows = new uint256[](slotCount);
        uint256[] memory rowSlots = new uint256[](rows.length);
        for (uint256 o = 0; o < order.length; o++) {
            bool placed = false;
            for (uint256 d = 0; d <= type(uint8).max && !placed; d++) {
                // forge-lint: disable-next-line(unsafe-typecast)
                placed = displace(rows, rowBuckets, order[o], bytes1(uint8(d)), slotRows, rowSlots);
                if (placed) {
                    // forge-lint: disable-next-line(unsafe-typecast)
                    displacements[order[o]] = bytes1(uint8(d));
                }
            }
            if (!placed) {
                return (false, displacements, slotRows);
            }
        }
        return (true, displacements, slotRows);
    }

    function displace(
        UnderlyingSnapshotRow[] memory rows,
        uint256[] memory rowBuckets,
        uint256 bucket,
        bytes1 displacement,
        uint256[] memory slotRows,
        uint256[] memory rowSlots
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < rows.length; i++) {
            if (rowBuckets[i] != bucket) {
                continue;
            }
            uint256 slot = uint256(keccak256(abi.encodePacked(rows[i].token, displacement))) % slotRows.length;
            if (slotRows[slot] != 0) {
                for (uint256 j = 0; j < i; j++) {
                    if (rowBuckets[j] == bucket) {
                        slotRows[rowSlots[j]] = 0;
                    }
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
        for (uint256 k = 1; k <= (EIP170_MAX_RUNTIME - 1 - UNDERLYING_SNAPSHOT_ROOT_HEADER_LENGTH) / 20; k++) {
            bytes[] memory shardCodes = new bytes[](k);
            address[] memory shards = new address[](k);
            bool fits = true;
            for (uint256 s = 0; s < k && fits; s++) {
                bytes memory data;
                (fits, data) = shardData(shardRows(rows, k, s), k);
                if (fits) {
                    shardCodes[s] = LibDataContract.contractCreationCode(data);
                    shards[s] = LibRainDeploy.zoltuAddress(shardCodes[s]);
                }
            }
            if (fits) {
                return (LibDataContract.contractCreationCode(rootData(asOf, shards)), shardCodes);
            }
        }
        revert UnderlyingSnapshotDoesNotShard(rows.length);
    }

    function shardRows(UnderlyingSnapshotRow[] memory rows, uint256 k, uint256 s)
        internal
        pure
        returns (UnderlyingSnapshotRow[] memory)
    {
        UnderlyingSnapshotRow[] memory member = new UnderlyingSnapshotRow[](rows.length);
        uint256 n = 0;
        for (uint256 i = 0; i < rows.length; i++) {
            if (uint256(uint160(rows[i].token)) % k == s) {
                member[n++] = rows[i];
            }
        }
        assembly ("memory-safe") {
            mstore(member, n)
        }
        return member;
    }
}

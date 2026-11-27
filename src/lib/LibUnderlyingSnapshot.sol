// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {MalformedUnderlyingSnapshot} from "../error/ErrUnderlying.sol";
import {LibDataContract} from "rain-datacontract-0.2.1/src/lib/LibDataContract.sol";

bytes4 constant UNDERLYING_SNAPSHOT_ROOT_MAGIC = bytes4(keccak256("st0x.underlying-snapshot.root.v1"));
bytes4 constant UNDERLYING_SNAPSHOT_SHARD_MAGIC = bytes4(keccak256("st0x.underlying-snapshot.shard.v1"));

/// @dev Root data: magic, asOf (32), K (2), then K shard addresses.
uint256 constant UNDERLYING_SNAPSHOT_ROOT_HEADER_LENGTH = 38;
/// @dev Shard data: magic, n (2), B (2), m (2), B displacements (1 each), m
/// slot offsets (2 each, absolute in the data, 0 empty), then rows of token
/// (20), ticker length (1), ticker, name length (1), name, ISIN length (1), ISIN.
uint256 constant UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH = 10;

/// @title LibUnderlyingSnapshot
/// @notice Reads the (token -> ticker, name, ISIN) snapshot held as pure data
/// in a root contract and its shards.
library LibUnderlyingSnapshot {
    struct Lookup {
        uint256 asOf;
        bool found;
        string ticker;
        string name;
        string isin;
    }

    function lookup(address root, address token) internal view returns (Lookup memory) {
        (uint256 asOf, uint256 shardCount) = rootHeader(root);
        address shard = readAddress(
            LibDataContract.readSlice(
                root, UNDERLYING_SNAPSHOT_ROOT_HEADER_LENGTH + 20 * (uint256(uint160(token)) % shardCount), 20
            ),
            0
        );
        (bool found, string memory ticker, string memory name, string memory isin) =
            lookupShard(shard, token, shardCount);
        return Lookup(asOf, found, ticker, name, isin);
    }

    /// @notice The shard addresses `root` names, in shard-index order.
    function shards(address root) internal view returns (address[] memory) {
        (, uint256 shardCount) = rootHeader(root);
        bytes memory list = LibDataContract.readSlice(root, UNDERLYING_SNAPSHOT_ROOT_HEADER_LENGTH, 20 * shardCount);
        address[] memory out = new address[](shardCount);
        for (uint256 i = 0; i < shardCount; i++) {
            out[i] = readAddress(list, 20 * i);
        }
        return out;
    }

    /// Returns the root's asOf and shard count.
    function rootHeader(address root) internal view returns (uint256, uint256) {
        uint256 rootLength = dataLength(root);
        if (rootLength < UNDERLYING_SNAPSHOT_ROOT_HEADER_LENGTH) {
            revert MalformedUnderlyingSnapshot(root);
        }
        bytes memory header = LibDataContract.readSlice(root, 0, UNDERLYING_SNAPSHOT_ROOT_HEADER_LENGTH);
        if (readBytes4(header, 0) != UNDERLYING_SNAPSHOT_ROOT_MAGIC) {
            revert MalformedUnderlyingSnapshot(root);
        }
        uint256 shardCount = readUint16(header, 36);
        if (shardCount == 0 || rootLength != UNDERLYING_SNAPSHOT_ROOT_HEADER_LENGTH + 20 * shardCount) {
            revert MalformedUnderlyingSnapshot(root);
        }
        return (readUint256(header, 4), shardCount);
    }

    function lookupShard(address shard, address token, uint256 shardCount)
        internal
        view
        returns (bool, string memory, string memory, string memory)
    {
        bytes memory rowData;
        {
            uint256 length = dataLength(shard);
            (bool hit, uint256 row) = rowOffset(shard, token, shardCount, length);
            if (!hit) {
                // The literal is this function's found/not-found return value, not a condition operand.
                // forge-lint: disable-next-line(boolean-cst)
                return (false, "", "", "");
            }
            uint256 rowEnd = row + 23 + 3 * uint256(type(uint8).max);
            rowData = LibDataContract.readSlice(shard, row, (rowEnd < length ? rowEnd : length) - row);
        }
        // A non-member can hash to a member's slot.
        if (readAddress(rowData, 0) != token) {
            // forge-lint: disable-next-line(boolean-cst)
            return (false, "", "", "");
        }
        return decodeRow(shard, rowData);
    }

    function rowOffset(address shard, address token, uint256 shardCount, uint256 length)
        internal
        view
        returns (bool, uint256)
    {
        if (length < UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH) {
            revert MalformedUnderlyingSnapshot(shard);
        }
        bytes memory header = LibDataContract.readSlice(shard, 0, UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH);
        if (readBytes4(header, 0) != UNDERLYING_SNAPSHOT_SHARD_MAGIC) {
            revert MalformedUnderlyingSnapshot(shard);
        }
        uint256 bucketCount = readUint16(header, 6);
        uint256 slotCount = readUint16(header, 8);
        uint256 rowsStart = UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH + bucketCount + 2 * slotCount;
        if (bucketCount == 0 || slotCount == 0 || rowsStart > length) {
            revert MalformedUnderlyingSnapshot(shard);
        }
        bytes1 displacement = LibDataContract.readSlice(
            shard, UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH + (uint256(uint160(token)) / shardCount) % bucketCount, 1
        )[0];
        uint256 slot = uint256(keccak256(abi.encodePacked(token, displacement))) % slotCount;
        uint256 row = readUint16(
            LibDataContract.readSlice(shard, UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH + bucketCount + 2 * slot, 2), 0
        );
        if (row == 0) {
            // forge-lint: disable-next-line(boolean-cst)
            return (false, 0);
        }
        if (row < rowsStart || row + 21 > length) {
            revert MalformedUnderlyingSnapshot(shard);
        }
        // forge-lint: disable-next-line(boolean-cst)
        return (true, row);
    }

    function decodeRow(address shard, bytes memory rowData)
        internal
        pure
        returns (bool, string memory, string memory, string memory)
    {
        uint256 tickerEnd = 21 + uint256(uint8(rowData[20]));
        if (tickerEnd + 1 > rowData.length) {
            revert MalformedUnderlyingSnapshot(shard);
        }
        uint256 nameEnd = tickerEnd + 1 + uint256(uint8(rowData[tickerEnd]));
        if (nameEnd + 1 > rowData.length) {
            revert MalformedUnderlyingSnapshot(shard);
        }
        uint256 isinEnd = nameEnd + 1 + uint256(uint8(rowData[nameEnd]));
        if (isinEnd > rowData.length) {
            revert MalformedUnderlyingSnapshot(shard);
        }
        return (
            // forge-lint: disable-next-line(boolean-cst)
            true,
            string(slice(rowData, 21, tickerEnd)),
            string(slice(rowData, tickerEnd + 1, nameEnd)),
            string(slice(rowData, nameEnd + 1, isinEnd))
        );
    }

    /// No code maps to MalformedUnderlyingSnapshot rather than ReadError.
    function dataLength(address pointer) internal view returns (uint256) {
        uint256 size = pointer.code.length;
        if (size == 0) {
            revert MalformedUnderlyingSnapshot(pointer);
        }
        return size - 1;
    }

    function slice(bytes memory data, uint256 start, uint256 end) internal pure returns (bytes memory) {
        bytes memory out = new bytes(end - start);
        assembly ("memory-safe") {
            mcopy(add(out, 0x20), add(add(data, 0x20), start), sub(end, start))
        }
        return out;
    }

    function readUint256(bytes memory data, uint256 offset) internal pure returns (uint256) {
        uint256 value;
        assembly ("memory-safe") {
            value := mload(add(add(data, 0x20), offset))
        }
        return value;
    }

    function readBytes4(bytes memory data, uint256 offset) internal pure returns (bytes4) {
        return bytes4(bytes32(readUint256(data, offset)));
    }

    function readUint16(bytes memory data, uint256 offset) internal pure returns (uint256) {
        return readUint256(data, offset) >> 240;
    }

    function readAddress(bytes memory data, uint256 offset) internal pure returns (address) {
        return address(bytes20(bytes32(readUint256(data, offset))));
    }
}

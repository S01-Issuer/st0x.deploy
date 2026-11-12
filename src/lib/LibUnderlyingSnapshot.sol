// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibParseMeta} from "rainlang-0.2.32/src/lib/parse/LibParseMeta.sol";
import {MalformedUnderlyingSnapshot} from "../error/ErrUnderlying.sol";

bytes4 constant UNDERLYING_SNAPSHOT_ROOT_MAGIC = bytes4(keccak256("st0x.underlying-snapshot.root.v1"));
bytes4 constant UNDERLYING_SNAPSHOT_SHARD_MAGIC = bytes4(keccak256("st0x.underlying-snapshot.shard.v1"));

/// @dev Root runtime: STOP, magic, asOf (32), K (1), then K shard addresses.
uint256 constant UNDERLYING_SNAPSHOT_ROOT_HEADER_LENGTH = 38;
/// @dev Shard runtime: STOP, magic, n (2), meta length (2), meta, n row
/// offsets (2 each, absolute in the runtime), then rows of token (20),
/// ticker length (1), ticker, name length (1), name.
uint256 constant UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH = 9;

/// @title LibUnderlyingSnapshot
/// @notice Reads the (token -> ticker, name) snapshot held as pure data in a
/// root contract and its shards.
library LibUnderlyingSnapshot {
    function lookup(address root, address token) internal view returns (uint256, bool, string memory, string memory) {
        bytes memory rootCode = root.code;
        if (
            rootCode.length < UNDERLYING_SNAPSHOT_ROOT_HEADER_LENGTH || rootCode[0] != 0x00
                || readBytes4(rootCode, 1) != UNDERLYING_SNAPSHOT_ROOT_MAGIC
        ) {
            revert MalformedUnderlyingSnapshot(root);
        }
        uint256 asOf = readUint256(rootCode, 5);
        uint256 shardCount = uint8(rootCode[37]);
        if (shardCount == 0 || rootCode.length != UNDERLYING_SNAPSHOT_ROOT_HEADER_LENGTH + 20 * shardCount) {
            revert MalformedUnderlyingSnapshot(root);
        }
        address shard =
            readAddress(rootCode, UNDERLYING_SNAPSHOT_ROOT_HEADER_LENGTH + 20 * (uint256(uint160(token)) % shardCount));
        (bool found, string memory ticker, string memory name) = lookupShard(shard, token);
        return (asOf, found, ticker, name);
    }

    function lookupShard(address shard, address token) internal view returns (bool, string memory, string memory) {
        bytes memory code = shard.code;
        if (
            code.length < UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH || code[0] != 0x00
                || readBytes4(code, 1) != UNDERLYING_SNAPSHOT_SHARD_MAGIC
        ) {
            revert MalformedUnderlyingSnapshot(shard);
        }
        uint256 n = readUint16(code, 5);
        uint256 offsetsStart = UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH + readUint16(code, 7);
        uint256 rowsStart = offsetsStart + 2 * n;
        if (rowsStart > code.length) {
            revert MalformedUnderlyingSnapshot(shard);
        }
        bytes memory meta = slice(code, UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH, offsetsStart);
        // lookupWord is UB on malformed meta.
        LibParseMeta.checkParseMetaStructure(meta);
        (bool hit, uint256 index) = LibParseMeta.lookupWord(meta, bytes32(uint256(uint160(token))));
        if (!hit) {
            return (false, "", "");
        }
        if (index >= n) {
            revert MalformedUnderlyingSnapshot(shard);
        }
        uint256 row = readUint16(code, offsetsStart + 2 * index);
        if (row < rowsStart || row + 21 > code.length) {
            revert MalformedUnderlyingSnapshot(shard);
        }
        // A fingerprint hit on a non-member lands on another member's row.
        if (readAddress(code, row) != token) {
            return (false, "", "");
        }
        uint256 tickerStart = row + 21;
        uint256 tickerEnd = tickerStart + uint8(code[row + 20]);
        if (tickerEnd + 1 > code.length) {
            revert MalformedUnderlyingSnapshot(shard);
        }
        uint256 nameEnd = tickerEnd + 1 + uint8(code[tickerEnd]);
        if (nameEnd > code.length) {
            revert MalformedUnderlyingSnapshot(shard);
        }
        return (true, string(slice(code, tickerStart, tickerEnd)), string(slice(code, tickerEnd + 1, nameEnd)));
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

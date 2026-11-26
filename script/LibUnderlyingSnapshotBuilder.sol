// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {AuthoringMetaV2} from "rainlang-0.2.40/src/interface/IParserV2.sol";
import {
    LibGenParseMeta,
    DuplicateFingerprint,
    AuthoringMetaTooLarge,
    MaxDepthExceeded
} from "rainlang-0.2.40/src/lib/codegen/LibGenParseMeta.sol";
import {LibRainDeploy} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";
import {LibDataContract} from "rain-datacontract-0.2.1/src/lib/LibDataContract.sol";
import {
    UNDERLYING_SNAPSHOT_ROOT_MAGIC,
    UNDERLYING_SNAPSHOT_ROOT_HEADER_LENGTH,
    UNDERLYING_SNAPSHOT_SHARD_MAGIC,
    UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH
} from "../src/lib/LibUnderlyingSnapshot.sol";
import {UnderlyingSnapshotShardEncoder} from "./UnderlyingSnapshotShardEncoder.sol";

uint8 constant UNDERLYING_SNAPSHOT_META_DEPTH = 3;
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
    function shardData(UnderlyingSnapshotRow[] memory rows) internal pure returns (bytes memory) {
        AuthoringMetaV2[] memory words = new AuthoringMetaV2[](rows.length);
        for (uint256 i = 0; i < rows.length; i++) {
            words[i] = AuthoringMetaV2(bytes32(uint256(uint160(rows[i].token))), "");
        }
        bytes memory meta = LibGenParseMeta.buildParseMetaV2(words, UNDERLYING_SNAPSHOT_META_DEPTH);
        uint256 rowsStart = UNDERLYING_SNAPSHOT_SHARD_HEADER_LENGTH + meta.length + 2 * rows.length;
        bytes memory offsets;
        bytes memory body;
        for (uint256 i = 0; i < rows.length; i++) {
            // build rejects any shard whose data passes EIP-170, far below 2^16.
            // forge-lint: disable-next-line(unsafe-typecast)
            offsets = abi.encodePacked(offsets, uint16(rowsStart + body.length));
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
        return abi.encodePacked(
            UNDERLYING_SNAPSHOT_SHARD_MAGIC, uint16(rows.length), uint16(meta.length), meta, offsets, body
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

    /// Smallest shard count K for which every shard fits the meta index and
    /// EIP-170; rows route to shard `uint160(token) % K`.
    function build(uint256 asOf, UnderlyingSnapshotRow[] memory rows) internal returns (bytes memory, bytes[] memory) {
        UnderlyingSnapshotShardEncoder encoder = new UnderlyingSnapshotShardEncoder();
        for (uint256 k = 1; k <= (EIP170_MAX_RUNTIME - 1 - UNDERLYING_SNAPSHOT_ROOT_HEADER_LENGTH) / 20; k++) {
            bytes[] memory shardCodes = new bytes[](k);
            address[] memory shards = new address[](k);
            bool fits = true;
            for (uint256 s = 0; s < k && fits; s++) {
                UnderlyingSnapshotRow[] memory member = shardRows(rows, k, s);
                // A meta build revert (depth, duplicate fingerprint, size) means try the next K.
                bytes memory data;
                try encoder.shardData(member) returns (bytes memory encoded) {
                    data = encoded;
                } catch (bytes memory err) {
                    // forge-lint: disable-next-line(unsafe-typecast)
                    bytes4 selector = bytes4(err);
                    if (
                        selector != DuplicateFingerprint.selector && selector != MaxDepthExceeded.selector
                            && selector != AuthoringMetaTooLarge.selector
                    ) {
                        assembly ("memory-safe") {
                            revert(add(err, 0x20), mload(err))
                        }
                    }
                    fits = false;
                    break;
                }
                if (data.length + 1 > EIP170_MAX_RUNTIME) {
                    fits = false;
                    break;
                }
                shardCodes[s] = LibDataContract.contractCreationCode(data);
                shards[s] = LibRainDeploy.zoltuAddress(shardCodes[s]);
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

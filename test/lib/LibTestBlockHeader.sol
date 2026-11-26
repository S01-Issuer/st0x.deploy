// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

/// @title LibTestBlockHeader
/// @notice Fields of an RLP-encoded block header, as `vm.getRawBlockHeader` returns it.
library LibTestBlockHeader {
    /// @notice The timestamp's index in the header's field list.
    uint256 internal constant TIMESTAMP_FIELD = 11;

    /// @notice The header's timestamp.
    function timestamp(bytes memory header) internal pure returns (uint256) {
        (uint256 cursor,) = item(header, 0);
        for (uint256 i = 0; i < TIMESTAMP_FIELD; i++) {
            (uint256 skippedStart, uint256 skippedLength) = item(header, cursor);
            cursor = skippedStart + skippedLength;
        }
        (uint256 start, uint256 length) = item(header, cursor);
        return bigEndian(header, start, length);
    }

    /// @notice The payload of the RLP item at `offset`: where it starts and its length.
    function item(bytes memory rlp, uint256 offset) private pure returns (uint256, uint256) {
        uint256 prefix = uint8(rlp[offset]);
        if (prefix < 0x80) {
            return (offset, 1);
        }
        if (prefix <= 0xb7) {
            return (offset + 1, prefix - 0x80);
        }
        if (prefix < 0xc0) {
            return (offset + 1 + prefix - 0xb7, bigEndian(rlp, offset + 1, prefix - 0xb7));
        }
        if (prefix <= 0xf7) {
            return (offset + 1, prefix - 0xc0);
        }
        return (offset + 1 + prefix - 0xf7, bigEndian(rlp, offset + 1, prefix - 0xf7));
    }

    function bigEndian(bytes memory data, uint256 start, uint256 length) private pure returns (uint256) {
        uint256 value = 0;
        for (uint256 i = 0; i < length; i++) {
            value = (value << 8) | uint8(data[start + i]);
        }
        return value;
    }
}

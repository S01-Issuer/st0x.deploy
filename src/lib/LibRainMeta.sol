// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @notice A CBOR head cannot carry a value above 2^64 - 1.
error CborValueTooLarge(uint256 value);

/// @title LibRainMeta
/// @notice sft-ops `encodeRainMeta`: a Rain meta document holding one deflated
/// JSON payload and, optionally, the IPFS CID of that JSON. The document is the
/// Rain meta magic followed by canonical CBOR maps:
///
/// - `{0: payload, 1: OA_SCHEMA_MAGIC, 2: "application/json", 3: "deflate"}`
/// - `{0: cid, 1: OA_HASH_LIST_MAGIC}`, only when a CID is given.
///
/// The payload is `deflate(JSON.stringify(x))`, produced off chain by the
/// launch helper, because only pako itself reproduces the bytes already on
/// chain.
library LibRainMeta {
    uint64 internal constant RAIN_META_DOCUMENT_MAGIC = 0xff0a89c674ee7874;
    uint64 internal constant OA_SCHEMA_MAGIC = 0xffa8e8a9b9cf4a31;
    uint64 internal constant OA_HASH_LIST_MAGIC = 0xff9fae3cc645f463;

    uint8 internal constant MAJOR_UINT = 0;
    uint8 internal constant MAJOR_BYTES = 2;
    uint8 internal constant MAJOR_TEXT = 3;
    uint8 internal constant MAJOR_MAP = 5;

    function encode(bytes memory payload, string memory cid) internal pure returns (bytes memory meta) {
        meta = abi.encodePacked(RAIN_META_DOCUMENT_MAGIC, schemaItem(payload));
        if (bytes(cid).length != 0) {
            meta = abi.encodePacked(meta, hashListItem(cid));
        }
    }

    function schemaItem(bytes memory payload) internal pure returns (bytes memory) {
        bytes memory head =
            abi.encodePacked(header(MAJOR_MAP, 4), header(MAJOR_UINT, 0), header(MAJOR_BYTES, payload.length));
        bytes memory tail = abi.encodePacked(
            header(MAJOR_UINT, 1),
            header(MAJOR_UINT, OA_SCHEMA_MAGIC),
            header(MAJOR_UINT, 2),
            text("application/json"),
            header(MAJOR_UINT, 3),
            text("deflate")
        );
        return abi.encodePacked(head, payload, tail);
    }

    function hashListItem(string memory cid) internal pure returns (bytes memory) {
        return abi.encodePacked(
            header(MAJOR_MAP, 2),
            header(MAJOR_UINT, 0),
            text(cid),
            header(MAJOR_UINT, 1),
            header(MAJOR_UINT, OA_HASH_LIST_MAGIC)
        );
    }

    function text(string memory value) internal pure returns (bytes memory) {
        return abi.encodePacked(header(MAJOR_TEXT, bytes(value).length), value);
    }

    /// @notice The shortest CBOR head for `major` and `value`, as canonical
    /// CBOR requires.
    /// Each narrowing cast is bounded by the comparison before it.
    function header(uint8 major, uint256 value) internal pure returns (bytes memory) {
        uint8 tag = major << 5;
        // forge-lint: disable-next-line(unsafe-typecast)
        if (value < 24) return abi.encodePacked(tag | uint8(value));
        // forge-lint: disable-next-line(unsafe-typecast)
        if (value <= type(uint8).max) return abi.encodePacked(tag | 24, uint8(value));
        // forge-lint: disable-next-line(unsafe-typecast)
        if (value <= type(uint16).max) return abi.encodePacked(tag | 25, uint16(value));
        // forge-lint: disable-next-line(unsafe-typecast)
        if (value <= type(uint32).max) return abi.encodePacked(tag | 26, uint32(value));
        if (value > type(uint64).max) revert CborValueTooLarge(value);
        // forge-lint: disable-next-line(unsafe-typecast)
        return abi.encodePacked(tag | 27, uint64(value));
    }
}

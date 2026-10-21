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

    /// @notice A Rain meta document holding `payload` and, when `cid` is
    /// non-empty, a hash-list item naming it.
    /// @param payload `deflate(JSON.stringify(x))`.
    /// @param cid The IPFS CID of `JSON.stringify(x)`, or empty for none.
    /// @return The magic followed by the CBOR items.
    function encode(bytes memory payload, string memory cid) internal pure returns (bytes memory) {
        bytes memory meta = bytes.concat(bytes8(RAIN_META_DOCUMENT_MAGIC), schemaItem(payload));
        if (bytes(cid).length != 0) meta = bytes.concat(meta, hashListItem(cid));
        return meta;
    }

    /// @notice The schema item: the payload, the OA schema magic, and its
    /// content type and encoding.
    /// @param payload The deflated JSON.
    /// @return The CBOR map.
    function schemaItem(bytes memory payload) internal pure returns (bytes memory) {
        bytes memory head =
            bytes.concat(header(MAJOR_MAP, 4), header(MAJOR_UINT, 0), header(MAJOR_BYTES, payload.length));
        bytes memory tail = bytes.concat(
            header(MAJOR_UINT, 1),
            header(MAJOR_UINT, OA_SCHEMA_MAGIC),
            header(MAJOR_UINT, 2),
            text("application/json"),
            header(MAJOR_UINT, 3),
            text("deflate")
        );
        return bytes.concat(head, payload, tail);
    }

    /// @notice The hash-list item naming `cid`.
    /// @param cid The IPFS CID.
    /// @return The CBOR map.
    function hashListItem(string memory cid) internal pure returns (bytes memory) {
        return bytes.concat(
            header(MAJOR_MAP, 2),
            header(MAJOR_UINT, 0),
            text(cid),
            header(MAJOR_UINT, 1),
            header(MAJOR_UINT, OA_HASH_LIST_MAGIC)
        );
    }

    /// @notice A CBOR text string.
    /// @param value The text.
    /// @return The head followed by the UTF-8 bytes.
    function text(string memory value) internal pure returns (bytes memory) {
        return bytes.concat(header(MAJOR_TEXT, bytes(value).length), bytes(value));
    }

    /// @notice The shortest CBOR head for `major` and `value`, as canonical
    /// CBOR requires. Each narrowing cast is bounded by the comparison before
    /// it.
    /// @param major The CBOR major type.
    /// @param value The length or value the head carries.
    /// @return The head. Reverts `CborValueTooLarge` above 2^64 - 1.
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

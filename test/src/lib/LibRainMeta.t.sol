// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainMeta, CborValueTooLarge} from "../../../src/lib/LibRainMeta.sol";

contract LibRainMetaTest is Test {
    /// @dev The framing that follows the payload in the schema item.
    bytes constant SCHEMA_ITEM_TAIL = hex"011bffa8e8a9b9cf4a3102706170706c69636174696f6e2f6a736f6e03676465666c617465";

    function testHeaderUsesTheShortestForm() external pure {
        assertEq(LibRainMeta.header(2, 0), hex"40");
        assertEq(LibRainMeta.header(2, 23), hex"57");
        assertEq(LibRainMeta.header(2, 24), hex"5818");
        assertEq(LibRainMeta.header(2, 255), hex"58ff");
        assertEq(LibRainMeta.header(2, 256), hex"590100");
        assertEq(LibRainMeta.header(2, 65535), hex"59ffff");
        assertEq(LibRainMeta.header(2, 65536), hex"5a00010000");
        assertEq(LibRainMeta.header(2, 0xffffffff), hex"5affffffff");
        assertEq(LibRainMeta.header(2, 0x100000000), hex"5b0000000100000000");
        assertEq(LibRainMeta.header(0, type(uint64).max), hex"1bffffffffffffffff");
        assertEq(LibRainMeta.header(3, 59), hex"783b");
        assertEq(LibRainMeta.header(5, 4), hex"a4");
        assertEq(LibRainMeta.header(0, 0xff0a89c674ee7874), hex"1bff0a89c674ee7874");
    }

    function externalHeader(uint256 value) external pure returns (bytes memory) {
        return LibRainMeta.header(0, value);
    }

    function testHeaderRevertsAboveUint64(uint256 value) external {
        value = bound(value, uint256(type(uint64).max) + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(CborValueTooLarge.selector, value));
        this.externalHeader(value);
    }

    function testEncodeWithoutCidIsTheSchemaItemOnly() external pure {
        assertEq(
            LibRainMeta.encode(hex"78da", ""),
            abi.encodePacked(hex"ff0a89c674ee7874", hex"a4004278da", SCHEMA_ITEM_TAIL)
        );
    }

    function testEncodeWithCidAppendsTheHashList() external pure {
        assertEq(
            LibRainMeta.encode(hex"78da", "bafy"),
            abi.encodePacked(
                hex"ff0a89c674ee7874", hex"a4004278da", SCHEMA_ITEM_TAIL, hex"a2006462616679011bff9fae3cc645f463"
            )
        );
    }

    /// @notice Each payload length lands its byte-string head on the right
    /// boundary and keeps the payload intact.
    function testEncodePayloadLengthsAcrossHeaderBoundaries() external pure {
        uint256[7] memory lengths = [uint256(23), 24, 255, 256, 65535, 65536, 0];
        for (uint256 i = 0; i < lengths.length; i++) {
            bytes memory payload = new bytes(lengths[i]);
            if (payload.length > 0) payload[payload.length - 1] = 0x01;
            bytes memory meta = LibRainMeta.encode(payload, "");
            bytes memory head = LibRainMeta.header(2, lengths[i]);
            assertEq(meta.length, 8 + 2 + head.length + lengths[i] + SCHEMA_ITEM_TAIL.length);
            for (uint256 j = 0; j < head.length; j++) {
                assertEq(meta[10 + j], head[j]);
            }
            if (payload.length > 0) assertEq(meta[10 + head.length + lengths[i] - 1], bytes1(0x01));
        }
    }
}

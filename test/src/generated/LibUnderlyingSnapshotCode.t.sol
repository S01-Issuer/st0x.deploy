// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {PREFIX_BYTES_LENGTH} from "rain-datacontract-0.2.1/src/lib/LibDataContract.sol";
import {LibUnderlyingSnapshotCode} from "../../../src/generated/LibUnderlyingSnapshotCode.sol";

contract LibUnderlyingSnapshotCodeTest is Test {
    address constant MSTR = 0x75793927E8406f7F56E4BE9e52a968fa883469bF;

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

    /// Expected values are an independent JavaScript hash-and-displace build over the same 59 rows.
    function testProductionShardIndexMatchesAnIndependentBuild() external pure {
        bytes[] memory codes = LibUnderlyingSnapshotCode.shardCreationCodes();
        assertEq(codes.length, 1, "shard count");
        bytes memory data = slice(codes[0], PREFIX_BYTES_LENGTH, codes[0].length - PREFIX_BYTES_LENGTH);
        assertEq(readUint(data, 4, 2), 59, "row count");
        assertEq(readUint(data, 6, 2), 15, "bucket count");
        assertEq(readUint(data, 8, 2), 71, "slot count");
        assertEq(slice(data, 10, 15), hex"02322e4c03062c0a07000202210024", "displacements");

        assertEq(uint256(uint160(MSTR)) % 15, 9, "MSTR bucket");
        assertEq(uint8(data[10 + 9]), 0, "MSTR displacement");
        assertEq(uint256(keccak256(abi.encodePacked(MSTR, bytes1(0)))) % 71, 55, "MSTR slot");
        uint256 row = readUint(data, 10 + 15 + 2 * 55, 2);
        assertEq(readUint(data, row, 20), uint160(MSTR), "MSTR row");
        assertEq(slice(data, row + 21, readUint(data, row + 20, 1)), bytes("MSTR"), "MSTR ticker");
    }
}

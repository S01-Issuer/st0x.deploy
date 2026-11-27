// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {PREFIX_BYTES_LENGTH} from "rain-datacontract-0.2.1/src/lib/LibDataContract.sol";
import {Bytes} from "@openzeppelin-contracts-5.7.0/utils/Bytes.sol";
import {LibUnderlyingSnapshotCode} from "../../../src/generated/LibUnderlyingSnapshotCode.sol";

contract LibUnderlyingSnapshotCodeTest is Test {
    address constant MSTR = 0x82583cAD4442CA1dcAB5A15EA61Db4970c71E638;

    function readUint(bytes memory data, uint256 start, uint256 length) internal pure returns (uint256) {
        uint256 value = 0;
        for (uint256 i = 0; i < length; i++) {
            value = value << 8 | uint8(data[start + i]);
        }
        return value;
    }

    /// Expected values are an independent hash-and-displace build over the same 59 rows.
    function testProductionShardIndexMatchesAnIndependentBuild() external pure {
        bytes[] memory codes = LibUnderlyingSnapshotCode.shardCreationCodes();
        assertEq(codes.length, 1, "shard count");
        bytes memory data = Bytes.slice(codes[0], PREFIX_BYTES_LENGTH);
        assertEq(readUint(data, 4, 2), 59, "row count");
        assertEq(readUint(data, 6, 2), 15, "bucket count");
        assertEq(readUint(data, 8, 2), 71, "slot count");
        assertEq(Bytes.slice(data, 10, 25), hex"0012030e1009052b0003831a100a4a", "displacements");

        assertEq(uint256(uint160(MSTR)) % 15, 6, "MSTR bucket");
        assertEq(uint8(data[10 + 6]), 5, "MSTR displacement");
        assertEq(uint256(keccak256(abi.encodePacked(MSTR, bytes1(0x05)))) % 71, 21, "MSTR slot");
        uint256 row = readUint(data, 10 + 15 + 2 * 21, 2);
        assertEq(readUint(data, row, 20), uint160(MSTR), "MSTR row");
        assertEq(Bytes.slice(data, row + 21, row + 21 + readUint(data, row + 20, 1)), bytes("MSTR"), "MSTR ticker");
    }
}

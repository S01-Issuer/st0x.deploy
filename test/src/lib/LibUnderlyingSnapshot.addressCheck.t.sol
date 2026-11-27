// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibUnderlyingSnapshot} from "../../../src/lib/LibUnderlyingSnapshot.sol";
import {LibUnderlyingSnapshotBuilder, UnderlyingSnapshotRow} from "../../../script/LibUnderlyingSnapshotBuilder.sol";

/// @notice A token that hashes to a member's slot but is not that member is a miss.
contract LibUnderlyingSnapshotAddressCheckTest is Test {
    function assertNotFound(LibUnderlyingSnapshot.Lookup memory row, uint256 asOf) internal pure {
        assertEq(row.asOf, asOf, "asOf");
        assertFalse(row.found, "found");
        assertEq(row.ticker, "", "ticker");
        assertEq(row.name, "", "name");
        assertEq(row.isin, "", "isin");
    }

    /// A one-row shard has one bucket, so every token's slot is keccak256(token, d[0]) % m.
    function slotOf(bytes memory shardData, address token) internal pure returns (uint256) {
        uint256 slotCount = uint256(uint8(shardData[8])) << 8 | uint8(shardData[9]);
        return uint256(keccak256(abi.encodePacked(token, shardData[10]))) % slotCount;
    }

    function testNonMemberOnAMembersSlotIsNotFound(address member, bytes32 seed, uint256 asOf) external {
        UnderlyingSnapshotRow[] memory rows = new UnderlyingSnapshotRow[](1);
        rows[0] = UnderlyingSnapshotRow(member, "AAPL", "Apple Inc.", "US0378331005");
        (, bytes memory shardData) = LibUnderlyingSnapshotBuilder.shardData(rows, 1);
        assertEq(uint256(uint8(shardData[6])) << 8 | uint8(shardData[7]), 1, "bucket count");
        address other;
        uint256 i = 0;
        do {
            other = address(uint160(uint256(keccak256(abi.encode(seed, i++)))));
        } while (other == member || slotOf(shardData, other) != slotOf(shardData, member));

        address shard = makeAddr("shard");
        vm.etch(shard, abi.encodePacked(bytes1(0), shardData));
        address[] memory shards = new address[](1);
        shards[0] = shard;
        address root = makeAddr("root");
        vm.etch(root, abi.encodePacked(bytes1(0), LibUnderlyingSnapshotBuilder.rootData(asOf, shards)));

        assertTrue(LibUnderlyingSnapshot.lookup(root, member).found, "member");
        assertNotFound(LibUnderlyingSnapshot.lookup(root, other), asOf);
    }
}

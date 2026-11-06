// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {TokenConfig, Region} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibTokenMetadata} from "../../../src/lib/LibTokenMetadata.sol";

/// @title LibTokenMetadataTest
/// @notice Offline coverage of the unrenamed and renamed name/symbol states
/// `LibTokenMetadata` derives.
contract LibTokenMetadataTest is Test {
    function config() internal pure returns (TokenConfig memory) {
        return TokenConfig({
            underlying: "NVDA",
            name: "NVIDIA Corporation ST0x",
            symbol: "tNVDA",
            region: Region.US,
            underlyingName: "NVIDIA Corporation"
        });
    }

    /// Of the eight combinations of initialized and renamed fields, only the
    /// all-initialized and the all-renamed ones are accepted.
    function testAcceptsOnlyCompleteMetadataStates() external pure {
        TokenConfig memory row = config();
        for (uint256 state = 0; state < 8; state++) {
            bool accepted = LibTokenMetadata.consistent(
                row,
                state & 1 == 0 ? "NVIDIA Corporation ST0x" : "NVIDIA Corporation (ST0x)",
                "tNVDA",
                state & 2 == 0 ? "Wrapped NVIDIA Corporation ST0x" : "NVIDIA Corporation (ST0x)",
                state & 4 == 0 ? "wtNVDA" : "NVDAs"
            );
            assertEq(accepted, state == 0 || state == 7);
        }
    }

    /// Each field, wrong on its own, is refused in both states.
    function testRejectsEveryWrongFieldInBothStates() external pure {
        TokenConfig memory row = config();
        for (uint256 state = 0; state < 2; state++) {
            string memory vaultName = state == 0 ? "NVIDIA Corporation ST0x" : "NVIDIA Corporation (ST0x)";
            string memory wrappedName = state == 0 ? "Wrapped NVIDIA Corporation ST0x" : "NVIDIA Corporation (ST0x)";
            string memory wrappedSymbol = state == 0 ? "wtNVDA" : "NVDAs";
            assertTrue(LibTokenMetadata.consistent(row, vaultName, "tNVDA", wrappedName, wrappedSymbol));
            assertFalse(LibTokenMetadata.consistent(row, "", "tNVDA", wrappedName, wrappedSymbol));
            assertFalse(LibTokenMetadata.consistent(row, "other", "tNVDA", wrappedName, wrappedSymbol));
            assertFalse(LibTokenMetadata.consistent(row, vaultName, "", wrappedName, wrappedSymbol));
            assertFalse(LibTokenMetadata.consistent(row, vaultName, "tMSFT", wrappedName, wrappedSymbol));
            assertFalse(LibTokenMetadata.consistent(row, vaultName, "tNVDA", "", wrappedSymbol));
            assertFalse(LibTokenMetadata.consistent(row, vaultName, "tNVDA", "other", wrappedSymbol));
            assertFalse(LibTokenMetadata.consistent(row, vaultName, "tNVDA", wrappedName, ""));
            assertFalse(LibTokenMetadata.consistent(row, vaultName, "tNVDA", wrappedName, "MSFTs"));
        }
    }

    /// The renamed values and the state classification.
    function testDerivedMetadataAndClassification() external pure {
        TokenConfig memory row = config();
        assertEq(LibTokenMetadata.renamedName(row), "NVIDIA Corporation (ST0x)");
        assertEq(LibTokenMetadata.renamedWrappedSymbol(row), "NVDAs");
        assertTrue(LibTokenMetadata.vaultRenamed(row, "NVIDIA Corporation (ST0x)"));
        assertFalse(LibTokenMetadata.vaultRenamed(row, "NVIDIA Corporation ST0x"));
        assertFalse(LibTokenMetadata.vaultRenamed(row, ""));
        assertFalse(LibTokenMetadata.vaultRenamed(row, "other"));
    }

    function testFuzzEquality(string memory left, string memory right) external pure {
        assertTrue(LibTokenMetadata.eq(left, left));
        assertEq(LibTokenMetadata.eq(left, right), keccak256(bytes(left)) == keccak256(bytes(right)));
        assertFalse(LibTokenMetadata.eq(left, string.concat(left, "x")));
    }
}

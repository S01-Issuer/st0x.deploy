// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {TokenConfig, Region} from "../../src/lib/LibProdTokenConfig.sol";
import {LibTestTokenMetadata} from "./LibTestTokenMetadata.sol";

/// @title LibTestTokenMetadataTest
/// @notice Offline coverage for the metadata states the live-fork pins
/// accept, so the renamed branch is tested before any chain renames.
contract LibTestTokenMetadataTest is Test {
    function config() internal pure returns (TokenConfig memory) {
        return TokenConfig({
            underlying: "NVDA",
            name: "NVIDIA Corporation ST0x",
            symbol: "tNVDA",
            region: Region.US,
            underlyingName: "NVIDIA Corporation",
            assetId: ""
        });
    }

    /// Of the eight combinations of initialized and renamed fields, only the
    /// all-initialized and the all-renamed ones are accepted.
    function testAcceptsOnlyCompleteMetadataStates() external pure {
        TokenConfig memory row = config();
        for (uint256 state = 0; state < 8; state++) {
            bool accepted = LibTestTokenMetadata.consistent(
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
            assertTrue(LibTestTokenMetadata.consistent(row, vaultName, "tNVDA", wrappedName, wrappedSymbol));
            assertFalse(LibTestTokenMetadata.consistent(row, "", "tNVDA", wrappedName, wrappedSymbol));
            assertFalse(LibTestTokenMetadata.consistent(row, "other", "tNVDA", wrappedName, wrappedSymbol));
            assertFalse(LibTestTokenMetadata.consistent(row, vaultName, "", wrappedName, wrappedSymbol));
            assertFalse(LibTestTokenMetadata.consistent(row, vaultName, "tMSFT", wrappedName, wrappedSymbol));
            assertFalse(LibTestTokenMetadata.consistent(row, vaultName, "tNVDA", "", wrappedSymbol));
            assertFalse(LibTestTokenMetadata.consistent(row, vaultName, "tNVDA", "other", wrappedSymbol));
            assertFalse(LibTestTokenMetadata.consistent(row, vaultName, "tNVDA", wrappedName, ""));
            assertFalse(LibTestTokenMetadata.consistent(row, vaultName, "tNVDA", wrappedName, "MSFTs"));
        }
    }

    /// The renamed values and the state classification.
    function testDerivedMetadataAndClassification() external pure {
        TokenConfig memory row = config();
        assertEq(LibTestTokenMetadata.renamedName(row), "NVIDIA Corporation (ST0x)");
        assertEq(LibTestTokenMetadata.renamedWrappedSymbol(row), "NVDAs");
        assertTrue(LibTestTokenMetadata.vaultRenamed(row, "NVIDIA Corporation (ST0x)"));
        assertFalse(LibTestTokenMetadata.vaultRenamed(row, "NVIDIA Corporation ST0x"));
        assertFalse(LibTestTokenMetadata.vaultRenamed(row, ""));
        assertFalse(LibTestTokenMetadata.vaultRenamed(row, "other"));
    }

    function testFuzzEquality(string memory left, string memory right) external pure {
        assertTrue(LibTestTokenMetadata.eq(left, left));
        assertEq(LibTestTokenMetadata.eq(left, right), keccak256(bytes(left)) == keccak256(bytes(right)));
        assertFalse(LibTestTokenMetadata.eq(left, string.concat(left, "x")));
    }
}

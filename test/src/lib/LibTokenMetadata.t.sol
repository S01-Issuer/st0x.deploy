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
            assetId: "US67066G1040",
            listingTicker: "NVDA",
            listingName: "NVIDIA Corporation",
            underlying: "NVDA",
            name: "NVIDIA Corporation ST0x",
            symbol: "tNVDA",
            region: Region.US,
            underlyingName: "NVIDIA Corporation"
        });
    }

    function testRenamedMetadata() external pure {
        TokenConfig memory row = config();
        assertEq(LibTokenMetadata.renamedName(row), "NVIDIA Corporation (ST0x)");
        assertEq(LibTokenMetadata.renamedWrappedSymbol(row), "NVDAs");
    }

    function testMetadataInBothStates() external pure {
        TokenConfig memory row = config();
        assertEq(LibTokenMetadata.vaultName(row, false), "NVIDIA Corporation ST0x");
        assertEq(LibTokenMetadata.wrappedName(row, false), "Wrapped NVIDIA Corporation ST0x");
        assertEq(LibTokenMetadata.wrappedSymbol(row, false), "wtNVDA");
        assertEq(LibTokenMetadata.vaultName(row, true), "NVIDIA Corporation (ST0x)");
        assertEq(LibTokenMetadata.wrappedName(row, true), "NVIDIA Corporation (ST0x)");
        assertEq(LibTokenMetadata.wrappedSymbol(row, true), "NVDAs");
    }
}

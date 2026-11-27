// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {AssetId, AssetIdKind} from "../../../src/interface/IStoxTokenConfigV1.sol";
import {TokenConfig, Region} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibTokenMetadata, TokenMetadataState} from "../../../src/lib/LibTokenMetadata.sol";

/// @title LibTokenMetadataTest
/// @notice Offline coverage of the initialized, listed and renamed name/symbol states
/// `LibTokenMetadata` derives.
contract LibTokenMetadataTest is Test {
    function config() internal pure returns (TokenConfig memory) {
        return TokenConfig({
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US67066G1040"}),
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

    function testMetadataInEachState() external pure {
        TokenConfig memory row = config();
        row.listingTicker = "NVDX";
        row.listingName = "NVIDIA Corp";
        TokenMetadataState initialized = TokenMetadataState.Initialized;
        assertEq(LibTokenMetadata.vaultName(row, initialized), "NVIDIA Corporation ST0x");
        assertEq(LibTokenMetadata.vaultSymbol(row, initialized), "tNVDA");
        assertEq(LibTokenMetadata.wrappedName(row, initialized), "Wrapped NVIDIA Corporation ST0x");
        assertEq(LibTokenMetadata.wrappedSymbol(row, initialized), "wtNVDA");
        TokenMetadataState listed = TokenMetadataState.Listed;
        assertEq(LibTokenMetadata.vaultName(row, listed), "NVIDIA Corp (ST0x)");
        assertEq(LibTokenMetadata.vaultSymbol(row, listed), "tNVDX");
        assertEq(LibTokenMetadata.wrappedName(row, listed), "NVIDIA Corp (ST0x)");
        assertEq(LibTokenMetadata.wrappedSymbol(row, listed), "NVDXs");
        TokenMetadataState renamed = TokenMetadataState.Renamed;
        assertEq(LibTokenMetadata.vaultName(row, renamed), "NVIDIA Corporation (ST0x)");
        assertEq(LibTokenMetadata.vaultSymbol(row, renamed), "tNVDA");
        assertEq(LibTokenMetadata.wrappedName(row, renamed), "NVIDIA Corporation (ST0x)");
        assertEq(LibTokenMetadata.wrappedSymbol(row, renamed), "NVDAs");
    }
}

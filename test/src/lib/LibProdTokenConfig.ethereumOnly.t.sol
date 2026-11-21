// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibProdTokenConfig, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";

/// @title LibProdTokenConfigEthereumOnlyTest
/// @notice `configOf` and `regionOf` resolve the six Ethereum-only rows to those rows, and the production table, which
/// every other chain's deploy reads, carries none of them.
contract LibProdTokenConfigEthereumOnlyTest is Test {
    function ethereumOnlyUnderlyings() internal pure returns (string[6] memory) {
        return ["AIR.PA", "BMW.DE", "MC.PA", "SIE.DE", "MBG.DE", "RHM.DE"];
    }

    function testEthereumOnlyRowsAreTheSixUnderlyings() external pure {
        TokenConfig[] memory rows = LibProdTokenConfig.ethereumOnlyTokenConfigs();
        string[6] memory underlyings = ethereumOnlyUnderlyings();
        assertEq(rows.length, underlyings.length, "rows");
        for (uint256 i = 0; i < rows.length; i++) {
            assertEq(rows[i].underlying, underlyings[i], "underlying");
        }
    }

    function testConfigOfReturnsEachEthereumOnlyRow() external pure {
        TokenConfig[] memory rows = LibProdTokenConfig.ethereumOnlyTokenConfigs();
        for (uint256 i = 0; i < rows.length; i++) {
            TokenConfig memory found = LibProdTokenConfig.configOf(rows[i].underlying);
            string memory label = rows[i].underlying;
            assertEq(found.assetId, rows[i].assetId, string.concat(label, " assetId"));
            assertEq(found.listingTicker, rows[i].listingTicker, string.concat(label, " listingTicker"));
            assertEq(found.listingName, rows[i].listingName, string.concat(label, " listingName"));
            assertEq(found.underlying, rows[i].underlying, string.concat(label, " underlying"));
            assertEq(found.name, rows[i].name, string.concat(label, " name"));
            assertEq(found.symbol, rows[i].symbol, string.concat(label, " symbol"));
            assertEq(uint8(found.region), uint8(rows[i].region), string.concat(label, " region"));
            assertEq(found.underlyingName, rows[i].underlyingName, string.concat(label, " underlyingName"));
        }
    }

    function testRegionOfReturnsEachEthereumOnlyRowsRegion() external pure {
        TokenConfig[] memory rows = LibProdTokenConfig.ethereumOnlyTokenConfigs();
        for (uint256 i = 0; i < rows.length; i++) {
            assertEq(uint8(LibProdTokenConfig.regionOf(rows[i].underlying)), uint8(rows[i].region), rows[i].underlying);
        }
    }

    function testProductionTableCarriesNoEthereumOnlyRow() external pure {
        TokenConfig[] memory production = LibProdTokenConfig.productionTokenConfigs();
        string[6] memory underlyings = ethereumOnlyUnderlyings();
        for (uint256 i = 0; i < underlyings.length; i++) {
            for (uint256 j = 0; j < production.length; j++) {
                assertNotEq(
                    keccak256(bytes(production[j].underlying)), keccak256(bytes(underlyings[i])), underlyings[i]
                );
            }
        }
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";
import {LibProdTokenConfig, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibSecurity} from "../../../src/lib/LibSecurity.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTokenInvariants, TokenInstance} from "../../../src/lib/LibTokenInvariants.sol";

/// @title LibProdTokenConfigListingWellFormedTest
/// @notice Every production row, in the table and on every chain, and every off-Base row has a well-formed ISIN,
/// listing ticker and listing name.
contract LibProdTokenConfigListingWellFormedTest is Test {
    function assertListingWellFormed(string memory rowName, TokenConfig memory config) internal pure {
        assertTrue(LibSecurity.isinWellFormed(config.assetId), string.concat(rowName, " assetId"));
        assertTrue(LibSecurity.tickerWellFormed(bytes(config.listingTicker)), string.concat(rowName, " listingTicker"));
        assertTrue(LibSecurity.nameWellFormed(bytes(config.listingName)), string.concat(rowName, " listingName"));
    }

    /// Each off-Base row's listing is well formed, and so are the ticker and name `setUnderlying` takes from it.
    function testEveryOffBaseRowHasAWellFormedListingAndUnderlying() external pure {
        TokenConfig[] memory rows = LibProdTokenConfig.offBaseTokenConfigs();
        assertGt(rows.length, 0, "rows");
        for (uint256 i = 0; i < rows.length; i++) {
            assertListingWellFormed(rows[i].underlying, rows[i]);
            assertTrue(
                LibSecurity.tickerWellFormed(bytes(rows[i].underlying)),
                string.concat(rows[i].underlying, " underlying")
            );
            assertTrue(
                LibSecurity.nameWellFormed(bytes(rows[i].underlyingName)),
                string.concat(rows[i].underlying, " underlyingName")
            );
        }
    }

    function testEveryRowOnEveryChainHasAWellFormedListing() external pure {
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        for (uint256 rowIndex = 0; rowIndex < configs.length; rowIndex++) {
            assertListingWellFormed(configs[rowIndex].underlying, configs[rowIndex]);
        }
        SupportedNetwork[] memory nets =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        for (uint256 netIndex = 0; netIndex < nets.length; netIndex++) {
            if (!LibTokenInvariants.tokenTableHydrated(nets[netIndex].chainId)) continue;
            TokenInstance[] memory tokens = LibTokenInvariants.productionTokensForChainId(nets[netIndex].chainId);
            for (uint256 rowIndex = 0; rowIndex < tokens.length; rowIndex++) {
                assertListingWellFormed(
                    string.concat(nets[netIndex].name, " ", tokens[rowIndex].underlying),
                    LibProdTokenConfig.configOf(tokens[rowIndex].underlying)
                );
            }
        }
    }
}

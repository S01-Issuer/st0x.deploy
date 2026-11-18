// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {St0xRegistryBaseListTest, RegistryToken} from "../../lib/St0xRegistryBaseListTest.sol";
import {LibProdTokenConfig, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";

/// An underlying and the ISIN of the share line it tracks.
struct UnderlyingIsin {
    string underlying;
    string isin;
}

/// @title LibProdTokenConfigIsinTest
/// @notice Every production row's asset id is the ISIN of the share line it tracks, and each row has one source.
contract LibProdTokenConfigIsinTest is St0xRegistryBaseListTest {
    /// The rows the registry Base list has no ISIN for. Each is the ISIN of the share line that trades under the
    /// ticker, with its check digit validated. Sources:
    /// - IBHG: BlackRock's fund page gives CUSIP 46436E478; Pensions & Investments gives ISIN US46436E4787. The
    ///   registry's Ethereum, HyperEVM and Robinhood lists carry US46436E3128, which no other source ties to IBHG.
    /// - RKLB: the issuer's May 2025 8-K12B gives the new CUSIP 773121108 of Rocket Lab Corporation after the holding
    ///   company reorganization; getquin and GuruFocus give ISIN US7731211089. The older US7731221062 is the
    ///   Rocket Lab USA line that the reorganization replaced.
    /// - BIRD: Allbirds' 2024 reverse split notice gives CUSIP 01675A208, and the June 2026 8-K for the rename to
    ///   Smartbird, Inc. says the CUSIP is unchanged; Fidelity and Hargreaves Lansdown give ISIN US01675A2087.
    /// - SNES: the issuer's July 2024 8-K gives CUSIP 81720R604 after the 1-for-10 reverse split; wallstreet-online
    ///   and GuruFocus give ISIN US81720R6045.
    /// - DIS: CUSIP 254687106 in Disney's SEC filings; StockAnalysis and the Mexican exchange (BMV) give ISIN
    ///   US2546871060.
    function sourcedIsins() internal pure returns (UnderlyingIsin[] memory) {
        UnderlyingIsin[] memory isins = new UnderlyingIsin[](5);
        isins[0] = UnderlyingIsin({underlying: "IBHG", isin: "US46436E4787"});
        isins[1] = UnderlyingIsin({underlying: "RKLB", isin: "US7731211089"});
        isins[2] = UnderlyingIsin({underlying: "BIRD", isin: "US01675A2087"});
        isins[3] = UnderlyingIsin({underlying: "SNES", isin: "US81720R6045"});
        isins[4] = UnderlyingIsin({underlying: "DIS", isin: "US2546871060"});
        return isins;
    }

    /// The rows the registry has no ISIN for carry the sourced ISIN.
    function testRowsCarryTheSourcedIsin() external pure {
        UnderlyingIsin[] memory isins = sourcedIsins();
        for (uint256 i = 0; i < isins.length; i++) {
            TokenConfig memory config = LibProdTokenConfig.configOf(isins[i].underlying);
            assertEq(config.assetId, isins[i].isin, isins[i].underlying);
        }
    }

    /// The registry Base list and the sourced list are disjoint and together cover every production row, so no row
    /// has an unsourced asset id.
    function testEveryRowIsSourcedOnce() external {
        RegistryToken[] memory registry = registryBaseTokens();
        UnderlyingIsin[] memory sourced = sourcedIsins();
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        for (uint256 i = 0; i < configs.length; i++) {
            uint256 matches = registryIndexOf(registry, configs[i].underlying) == NOT_IN_REGISTRY ? 0 : 1;
            for (uint256 j = 0; j < sourced.length; j++) {
                if (keccak256(bytes(sourced[j].underlying)) == keccak256(bytes(configs[i].underlying))) matches++;
            }
            assertEq(matches, 1, configs[i].underlying);
        }
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibProdTokenConfig, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";

/// An underlying and the ISIN of the share line it tracks.
struct UnderlyingIsin {
    string underlying;
    string isin;
}

/// @title LibProdTokenConfigIsinTest
/// @notice Every production row's asset id is the ISIN of the share line it tracks, and each row has one source.
contract LibProdTokenConfigIsinTest is Test {
    /// `extensions.isin` of every `wt<TICKER>` in st0x.registry `token-lists/base.json` at commit `e9e47a6`, keyed by
    /// the ticker. The other chains' lists agree with it except wtSMCI, where they still carry the pre-split ISIN
    /// `US86800U1043`: SMCI's 8-K of 2024-09-26 gives the post-split CUSIP `86800U302`, and Exhibit 1.1 of its 8-K of
    /// 2026-06-15 gives "CUSIP / ISIN for the Common Stock 86800U302 / US86800U3023", the Base value.
    function registryBaseIsins() internal pure returns (UnderlyingIsin[] memory) {
        UnderlyingIsin[] memory isins = new UnderlyingIsin[](54);
        isins[0] = UnderlyingIsin({underlying: "MSTR", isin: "US5949724083"});
        isins[1] = UnderlyingIsin({underlying: "TSLA", isin: "US88160R1014"});
        isins[2] = UnderlyingIsin({underlying: "COIN", isin: "US19260Q1076"});
        isins[3] = UnderlyingIsin({underlying: "SPYM", isin: "US78464A8541"});
        isins[4] = UnderlyingIsin({underlying: "SIVR", isin: "US0032641088"});
        isins[5] = UnderlyingIsin({underlying: "CRCL", isin: "US1725731079"});
        isins[6] = UnderlyingIsin({underlying: "NVDA", isin: "US67066G1040"});
        isins[7] = UnderlyingIsin({underlying: "IAU", isin: "US4642852044"});
        isins[8] = UnderlyingIsin({underlying: "PPLT", isin: "US0032601066"});
        isins[9] = UnderlyingIsin({underlying: "AMZN", isin: "US0231351067"});
        isins[10] = UnderlyingIsin({underlying: "BMNR", isin: "US09175A2069"});
        isins[11] = UnderlyingIsin({underlying: "SGOV", isin: "US46436E7186"});
        isins[12] = UnderlyingIsin({underlying: "QQQM", isin: "US46138G6492"});
        isins[13] = UnderlyingIsin({underlying: "VWO", isin: "US9220428588"});
        isins[14] = UnderlyingIsin({underlying: "ARKK", isin: "US00214Q1040"});
        isins[15] = UnderlyingIsin({underlying: "SPCX", isin: "US84615Q1031"});
        isins[16] = UnderlyingIsin({underlying: "CEG", isin: "US21037T1097"});
        isins[17] = UnderlyingIsin({underlying: "DRAM", isin: "US77926X3200"});
        isins[18] = UnderlyingIsin({underlying: "TSM", isin: "US8740391003"});
        isins[19] = UnderlyingIsin({underlying: "SKHY", isin: "US78392B2060"});
        isins[20] = UnderlyingIsin({underlying: "ASML", isin: "USN070592100"});
        isins[21] = UnderlyingIsin({underlying: "MU", isin: "US5951121038"});
        isins[22] = UnderlyingIsin({underlying: "AMD", isin: "US0079031078"});
        isins[23] = UnderlyingIsin({underlying: "AVGO", isin: "US11135F1012"});
        isins[24] = UnderlyingIsin({underlying: "AMAT", isin: "US0382221051"});
        isins[25] = UnderlyingIsin({underlying: "LRCX", isin: "US5128073062"});
        isins[26] = UnderlyingIsin({underlying: "TTWO", isin: "US8740541094"});
        isins[27] = UnderlyingIsin({underlying: "GOOGL", isin: "US02079K3059"});
        isins[28] = UnderlyingIsin({underlying: "AAPL", isin: "US0378331005"});
        isins[29] = UnderlyingIsin({underlying: "MSFT", isin: "US5949181045"});
        isins[30] = UnderlyingIsin({underlying: "LLY", isin: "US5324571083"});
        isins[31] = UnderlyingIsin({underlying: "PTY", isin: "US72201B1017"});
        isins[32] = UnderlyingIsin({underlying: "INTC", isin: "US4581401001"});
        isins[33] = UnderlyingIsin({underlying: "HOOD", isin: "US7707001027"});
        isins[34] = UnderlyingIsin({underlying: "ORCL", isin: "US68389X1054"});
        isins[35] = UnderlyingIsin({underlying: "SMCI", isin: "US86800U3023"});
        isins[36] = UnderlyingIsin({underlying: "BABA", isin: "US01609W1027"});
        isins[37] = UnderlyingIsin({underlying: "TQQQ", isin: "US74347X8314"});
        isins[38] = UnderlyingIsin({underlying: "FTF", isin: "US35472T1016"});
        isins[39] = UnderlyingIsin({underlying: "CBRS", isin: "US15675D1037"});
        isins[40] = UnderlyingIsin({underlying: "MCD", isin: "US5801351017"});
        isins[41] = UnderlyingIsin({underlying: "NKE", isin: "US6541061031"});
        isins[42] = UnderlyingIsin({underlying: "GRND", isin: "US39854F1012"});
        isins[43] = UnderlyingIsin({underlying: "DNUT", isin: "US50101L1061"});
        isins[44] = UnderlyingIsin({underlying: "PLBY", isin: "US72814P1093"});
        isins[45] = UnderlyingIsin({underlying: "TR", isin: "US8905161076"});
        isins[46] = UnderlyingIsin({underlying: "WEN", isin: "US95058W1009"});
        isins[47] = UnderlyingIsin({underlying: "FGI", isin: "KYG3302D2024"});
        isins[48] = UnderlyingIsin({underlying: "SPY", isin: "US78462F1030"});
        isins[49] = UnderlyingIsin({underlying: "WMT", isin: "US9311421039"});
        isins[50] = UnderlyingIsin({underlying: "MC", isin: "FR0000121014"});
        isins[51] = UnderlyingIsin({underlying: "IFX", isin: "DE0006231004"});
        isins[52] = UnderlyingIsin({underlying: "SOI", isin: "FR0013227113"});
        isins[53] = UnderlyingIsin({underlying: "TPRO", isin: "IT0005482333"});
        return isins;
    }

    /// The rows the registry Base list has no ISIN for. Each is the ISIN of the share line that trades under the
    /// ticker, with its check digit validated. Sources:
    /// - IBHG: BlackRock's fund page gives CUSIP 46436E478, and the iShares Trust N-PORT-P filed 2026-09-23
    ///   (accession 0001004726-26-008843) lists the fund with ISIN US46436E4787. The registry's Ethereum, HyperEVM and
    ///   Robinhood lists carry wtIBHG as US46436E3128, the ISIN of the iShares iBonds Dec 2032 Term Corporate ETF.
    /// - RKLB: the issuer's 8-K12B of 2025-05-23 gives the new CUSIP 773121108 of Rocket Lab Corporation after the
    ///   holding company reorganization, and its 10-Q filed 2026-11-09 keeps that name. The older US7731221062 is the
    ///   Rocket Lab USA line that the reorganization replaced.
    /// - BIRD: Allbirds' 8-K of 2024-08-30 gives CUSIP 01675A208 after the reverse split, and Exhibit 99.1 of the 8-K
    ///   of 2026-06-17 for the rename to Smartbird, Inc. says the CUSIP is unchanged.
    /// - SNES: the issuer's 8-K of 2024-07-23 gives CUSIP 81720R604 after the 1-for-10 reverse split.
    /// - DIS: Disney's proxy of 2015-01-16 gives common CUSIP 254687106; the 8-K12B of 2019-03-20 keeps the DIS line
    ///   under the successor registrant, and its 2026 notes keep the 254687 issuer number.
    function sourcedIsins() internal pure returns (UnderlyingIsin[] memory) {
        UnderlyingIsin[] memory isins = new UnderlyingIsin[](5);
        isins[0] = UnderlyingIsin({underlying: "IBHG", isin: "US46436E4787"});
        isins[1] = UnderlyingIsin({underlying: "RKLB", isin: "US7731211089"});
        isins[2] = UnderlyingIsin({underlying: "BIRD", isin: "US01675A2087"});
        isins[3] = UnderlyingIsin({underlying: "SNES", isin: "US81720R6045"});
        isins[4] = UnderlyingIsin({underlying: "DIS", isin: "US2546871060"});
        return isins;
    }

    function assertRowsHaveIsins(UnderlyingIsin[] memory isins) internal pure {
        for (uint256 i = 0; i < isins.length; i++) {
            TokenConfig memory config = LibProdTokenConfig.configOf(isins[i].underlying);
            assertEq(config.assetId, isins[i].isin, isins[i].underlying);
        }
    }

    /// The rows in st0x.registry's Base list carry the ISIN it gives.
    function testRowsCarryTheRegistryBaseIsin() external pure {
        assertRowsHaveIsins(registryBaseIsins());
    }

    /// The rows the registry has no ISIN for carry the sourced ISIN.
    function testRowsCarryTheSourcedIsin() external pure {
        assertRowsHaveIsins(sourcedIsins());
    }

    /// The two lists are disjoint and together cover every production row, so no row has an unsourced asset id.
    function testEveryRowIsSourcedOnce() external pure {
        UnderlyingIsin[] memory registry = registryBaseIsins();
        UnderlyingIsin[] memory sourced = sourcedIsins();
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        assertEq(registry.length + sourced.length, configs.length, "count");
        for (uint256 i = 0; i < configs.length; i++) {
            uint256 matches = 0;
            for (uint256 j = 0; j < registry.length; j++) {
                if (keccak256(bytes(registry[j].underlying)) == keccak256(bytes(configs[i].underlying))) matches++;
            }
            for (uint256 j = 0; j < sourced.length; j++) {
                if (keccak256(bytes(sourced[j].underlying)) == keccak256(bytes(configs[i].underlying))) matches++;
            }
            assertEq(matches, 1, configs[i].underlying);
        }
    }
}

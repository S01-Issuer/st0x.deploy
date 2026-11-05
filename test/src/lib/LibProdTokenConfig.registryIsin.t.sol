// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibProdTokenConfig, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";

/// An underlying and the ISIN a source gives for it.
struct RegistryIsin {
    string underlying;
    string isin;
}

/// @title LibProdTokenConfigRegistryIsinTest
/// @notice Every production row's asset id is an ISIN from a pinned source. 54 rows take the ISIN from the
/// st0x.registry Base token list. The other 5 have no ISIN there and are sourced by hand.
contract LibProdTokenConfigRegistryIsinTest is Test {
    /// `extensions.isin` of every `wt<TICKER>` in st0x.registry `token-lists/base.json` at commit `e9e47a6`, keyed by
    /// the ticker. The other chains' lists agree with it except wtSMCI, where they still carry the pre-split ISIN
    /// `US86800U1043`. SMCI's current CUSIP after its 2024 10-for-1 split is `86800U302`, which is the Base value.
    function registryBaseIsins() internal pure returns (RegistryIsin[] memory isins) {
        isins = new RegistryIsin[](54);
        isins[0] = RegistryIsin({underlying: "MSTR", isin: "US5949724083"});
        isins[1] = RegistryIsin({underlying: "TSLA", isin: "US88160R1014"});
        isins[2] = RegistryIsin({underlying: "COIN", isin: "US19260Q1076"});
        isins[3] = RegistryIsin({underlying: "SPYM", isin: "US78464A8541"});
        isins[4] = RegistryIsin({underlying: "SIVR", isin: "US0032641088"});
        isins[5] = RegistryIsin({underlying: "CRCL", isin: "US1725731079"});
        isins[6] = RegistryIsin({underlying: "NVDA", isin: "US67066G1040"});
        isins[7] = RegistryIsin({underlying: "IAU", isin: "US4642852044"});
        isins[8] = RegistryIsin({underlying: "PPLT", isin: "US0032601066"});
        isins[9] = RegistryIsin({underlying: "AMZN", isin: "US0231351067"});
        isins[10] = RegistryIsin({underlying: "BMNR", isin: "US09175A2069"});
        isins[11] = RegistryIsin({underlying: "SGOV", isin: "US46436E7186"});
        isins[12] = RegistryIsin({underlying: "QQQM", isin: "US46138G6492"});
        isins[13] = RegistryIsin({underlying: "VWO", isin: "US9220428588"});
        isins[14] = RegistryIsin({underlying: "ARKK", isin: "US00214Q1040"});
        isins[15] = RegistryIsin({underlying: "SPCX", isin: "US84615Q1031"});
        isins[16] = RegistryIsin({underlying: "CEG", isin: "US21037T1097"});
        isins[17] = RegistryIsin({underlying: "DRAM", isin: "US77926X3200"});
        isins[18] = RegistryIsin({underlying: "TSM", isin: "US8740391003"});
        isins[19] = RegistryIsin({underlying: "SKHY", isin: "US78392B2060"});
        isins[20] = RegistryIsin({underlying: "ASML", isin: "USN070592100"});
        isins[21] = RegistryIsin({underlying: "MU", isin: "US5951121038"});
        isins[22] = RegistryIsin({underlying: "AMD", isin: "US0079031078"});
        isins[23] = RegistryIsin({underlying: "AVGO", isin: "US11135F1012"});
        isins[24] = RegistryIsin({underlying: "AMAT", isin: "US0382221051"});
        isins[25] = RegistryIsin({underlying: "LRCX", isin: "US5128073062"});
        isins[26] = RegistryIsin({underlying: "TTWO", isin: "US8740541094"});
        isins[27] = RegistryIsin({underlying: "GOOGL", isin: "US02079K3059"});
        isins[28] = RegistryIsin({underlying: "AAPL", isin: "US0378331005"});
        isins[29] = RegistryIsin({underlying: "MSFT", isin: "US5949181045"});
        isins[30] = RegistryIsin({underlying: "LLY", isin: "US5324571083"});
        isins[31] = RegistryIsin({underlying: "PTY", isin: "US72201B1017"});
        isins[32] = RegistryIsin({underlying: "INTC", isin: "US4581401001"});
        isins[33] = RegistryIsin({underlying: "HOOD", isin: "US7707001027"});
        isins[34] = RegistryIsin({underlying: "ORCL", isin: "US68389X1054"});
        isins[35] = RegistryIsin({underlying: "SMCI", isin: "US86800U3023"});
        isins[36] = RegistryIsin({underlying: "BABA", isin: "US01609W1027"});
        isins[37] = RegistryIsin({underlying: "TQQQ", isin: "US74347X8314"});
        isins[38] = RegistryIsin({underlying: "FTF", isin: "US35472T1016"});
        isins[39] = RegistryIsin({underlying: "CBRS", isin: "US15675D1037"});
        isins[40] = RegistryIsin({underlying: "MCD", isin: "US5801351017"});
        isins[41] = RegistryIsin({underlying: "NKE", isin: "US6541061031"});
        isins[42] = RegistryIsin({underlying: "GRND", isin: "US39854F1012"});
        isins[43] = RegistryIsin({underlying: "DNUT", isin: "US50101L1061"});
        isins[44] = RegistryIsin({underlying: "PLBY", isin: "US72814P1093"});
        isins[45] = RegistryIsin({underlying: "TR", isin: "US8905161076"});
        isins[46] = RegistryIsin({underlying: "WEN", isin: "US95058W1009"});
        isins[47] = RegistryIsin({underlying: "FGI", isin: "KYG3302D2024"});
        isins[48] = RegistryIsin({underlying: "SPY", isin: "US78462F1030"});
        isins[49] = RegistryIsin({underlying: "WMT", isin: "US9311421039"});
        isins[50] = RegistryIsin({underlying: "MC", isin: "FR0000121014"});
        isins[51] = RegistryIsin({underlying: "IFX", isin: "DE0006231004"});
        isins[52] = RegistryIsin({underlying: "SOI", isin: "FR0013227113"});
        isins[53] = RegistryIsin({underlying: "TPRO", isin: "IT0005482333"});
    }

    /// The rows the registry Base list has no ISIN for. Each is the ISIN of the share line that trades under the
    /// ticker today, with its check digit validated. Sources, checked 2026-11-05:
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
    function sourcedIsins() internal pure returns (RegistryIsin[] memory isins) {
        isins = new RegistryIsin[](5);
        isins[0] = RegistryIsin({underlying: "IBHG", isin: "US46436E4787"});
        isins[1] = RegistryIsin({underlying: "RKLB", isin: "US7731211089"});
        isins[2] = RegistryIsin({underlying: "BIRD", isin: "US01675A2087"});
        isins[3] = RegistryIsin({underlying: "SNES", isin: "US81720R6045"});
        isins[4] = RegistryIsin({underlying: "DIS", isin: "US2546871060"});
    }

    function assertRowsHaveIsins(RegistryIsin[] memory isins) internal pure {
        for (uint256 i = 0; i < isins.length; i++) {
            TokenConfig memory config = LibProdTokenConfig.configOf(isins[i].underlying);
            assertEq(config.assetId, isins[i].isin, isins[i].underlying);
        }
    }

    function testRegistryRowsCarryTheRegistryIsin() external pure {
        assertRowsHaveIsins(registryBaseIsins());
    }

    function testSourcedRowsCarryTheSourcedIsin() external pure {
        assertRowsHaveIsins(sourcedIsins());
    }

    /// The two lists are disjoint and together cover every production row, so no row has an unsourced asset id.
    function testEveryRowIsSourcedOnce() external pure {
        RegistryIsin[] memory registry = registryBaseIsins();
        RegistryIsin[] memory sourced = sourcedIsins();
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

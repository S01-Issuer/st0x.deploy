// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {AssetId, AssetIdKind, Region} from "../interface/IStoxTokenConfigV1.sol";

/// @notice The deploy-time configuration for one production token — the
/// inputs `StoxUnifiedDeployer.newTokenAndWrapperVault` needs to reproduce
/// a Base token instance on another chain.
/// @dev For tokens deployed before `StoxTokenConfigV1`, only `name` + `symbol`
/// were captured: the offchain-asset receipt vault takes `asset = address(0)` (the asset is offchain) and
/// `receipt = address(0)` (the beacon-set deployer wires the receipt),
/// `initialAdmin` is the target chain's Safe (supplied by the deploy
/// script, not the table), `decimals` is fixed by the shared vault
/// implementation bytecode, and the wrapped token vault derives its own
/// name/symbol on-chain from the receipt vault. So the receipt vault's
/// `name` + `symbol` were their only free initialization inputs.
///
/// The underlying ticker and name are not deploy inputs: the vault owner sets
/// them after deployment with `IStoxUnderlyingV2.setUnderlying`. The ticker
/// is the row's `ticker` and the name is `underlyingName`. Once both are set,
/// the receipt vault reports `"t" + ticker` / `underlyingName + " (ST0x)"`
/// and the wrapped token vault `ticker + "s"` / the receipt vault's name.
/// Until then a token deployed before `StoxTokenConfigV1` reports the
/// `name` + `symbol` it was initialized with, and its wrapper
/// `"Wrapped " + name` / `"w" + symbol`; a `StoxTokenConfigV1` token reports
/// its listing (`LibTokenMetadata`).
///
/// `assetId`, `listingTicker` and `listingName` record the listing each
/// token tracks, and are the token's `StoxTokenConfigV1` init data.
///
/// The underlying snapshot is built from `ticker`, `underlyingName` and
/// `isin`; the vault owner overrides them per token with
/// `IStoxUnderlyingV2.setUnderlying`.
/// @param assetId The listing-time id of the share line the token tracks.
/// @param listingTicker The underlying's ticker as listed.
/// @param listingName The underlying's name as listed.
/// @param underlying The frozen chain-agnostic join key, matching
/// `LibTokenInvariants.TokenInstance.underlying`.
/// @param ticker The current underlying ticker, as the snapshot records it.
/// @param name The receipt vault's ERC-20 `name()`, verbatim from Base.
/// @param symbol The receipt vault's ERC-20 `symbol()`, verbatim from Base.
/// @param region The issuance region, which picks the token's RBAC and
/// authoriser. It is not the listing venue: tMC.PA is Paris-listed and issued
/// under US.
/// @param underlyingName The issuer's current legal name, without any ST0x
/// suffix: the `name` argument of `setUnderlying`. Usually the live `name`
/// without " ST0x"; it differs where the issuer has since been renamed
/// (MSTR, RKLB).
/// @param isin The underlying share line's current ISIN.
struct TokenConfig {
    AssetId assetId;
    string listingTicker;
    string listingName;
    string underlying;
    string ticker;
    string name;
    string symbol;
    Region region;
    string underlyingName;
    string isin;
}

/// @dev Unix seconds the underlying snapshot was cut from this table.
uint256 constant UNDERLYING_SNAPSHOT_AS_OF = 1795635132;

/// @notice The underlying has no row in the production token table.
error UnknownUnderlying(string underlying);

/// @title LibProdTokenConfig
/// @notice The canonical name/symbol table for the ST0x production
/// tokens, captured verbatim from the live Base receipt vaults so a new
/// chain's token set can be deployed byte-identical to Base. This is the
/// deploy-input companion to `LibTokenInvariants` (which holds the deployed
/// addresses): the deploy script reads this to author the
/// `newTokenAndWrapperVault` calls, and it is the expected `name`/`symbol`
/// per token in expected-state.json.
///
/// @dev Entries are in the same order as
/// `LibTokenInvariants.productionTokensBase()` so the two tables pair by
/// index as well as by `underlying` key; `LibProdTokenConfigTest` pins that
/// alignment over every row Base carries. The table may run AHEAD of Base —
/// a row is authored when a ticker is chosen and Base is pinned when its
/// deploy lands, and `_selectMissing` reads only the rows Base carries — but
/// never behind it. Strings are reproduced EXACTLY, including quirks that exist on
/// Base — notably `SGOV`'s name has a leading space. Matching Base "exactly"
/// means carrying that space forward; the parity pin would flag it as a
/// divergence otherwise.
library LibProdTokenConfig {
    /// @notice The production token deploy configs, Base table order.
    /// @return configs The name/symbol table.
    function productionTokenConfigs() internal pure returns (TokenConfig[] memory configs) {
        configs = new TokenConfig[](59);
        configs[0] = TokenConfig({
            underlying: "MSTR",
            ticker: "MSTR",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US5949724083"}),
            listingTicker: "MSTR",
            listingName: "MicroStrategy Incorporated",
            name: "MicroStrategy Incorporated ST0x",
            symbol: "tMSTR",
            region: Region.US,
            underlyingName: "Strategy Inc",
            isin: "US5949724083"
        });
        configs[1] = TokenConfig({
            underlying: "TSLA",
            ticker: "TSLA",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US88160R1014"}),
            listingTicker: "TSLA",
            listingName: "Tesla Inc",
            name: "Tesla Inc ST0x",
            symbol: "tTSLA",
            region: Region.US,
            underlyingName: "Tesla Inc",
            isin: "US88160R1014"
        });
        configs[2] = TokenConfig({
            underlying: "COIN",
            ticker: "COIN",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US19260Q1076"}),
            listingTicker: "COIN",
            listingName: "Coinbase Global Inc",
            name: "Coinbase Global Inc ST0x",
            symbol: "tCOIN",
            region: Region.US,
            underlyingName: "Coinbase Global Inc",
            isin: "US19260Q1076"
        });
        configs[3] = TokenConfig({
            underlying: "SPYM",
            ticker: "SPYM",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US78464A8541"}),
            listingTicker: "SPYM",
            listingName: "State Street SPDR Portfolio S&P 500 ETF",
            name: "State Street SPDR Portfolio S&P 500 ETF ST0x",
            symbol: "tSPYM",
            region: Region.US,
            underlyingName: "State Street SPDR Portfolio S&P 500 ETF",
            isin: "US78464A8541"
        });
        configs[4] = TokenConfig({
            underlying: "SIVR",
            ticker: "SIVR",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US0032641088"}),
            listingTicker: "SIVR",
            listingName: "abrdn Physical Silver Shares ETF",
            name: "abrdn Physical Silver Shares ETF ST0x",
            symbol: "tSIVR",
            region: Region.US,
            underlyingName: "abrdn Physical Silver Shares ETF",
            isin: "US0032641088"
        });
        configs[5] = TokenConfig({
            underlying: "CRCL",
            ticker: "CRCL",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US1725731079"}),
            listingTicker: "CRCL",
            listingName: "Circle Internet Group Inc",
            name: "Circle Internet Group Inc ST0x",
            symbol: "tCRCL",
            region: Region.US,
            underlyingName: "Circle Internet Group Inc",
            isin: "US1725731079"
        });
        configs[6] = TokenConfig({
            underlying: "NVDA",
            ticker: "NVDA",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US67066G1040"}),
            listingTicker: "NVDA",
            listingName: "NVIDIA Corporation",
            name: "NVIDIA Corporation ST0x",
            symbol: "tNVDA",
            region: Region.US,
            underlyingName: "NVIDIA Corporation",
            isin: "US67066G1040"
        });
        configs[7] = TokenConfig({
            underlying: "IAU",
            ticker: "IAU",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US4642852044"}),
            listingTicker: "IAU",
            listingName: "iShares Gold Trust",
            name: "iShares Gold Trust ST0x",
            symbol: "tIAU",
            region: Region.US,
            underlyingName: "iShares Gold Trust",
            isin: "US4642852044"
        });
        configs[8] = TokenConfig({
            underlying: "PPLT",
            ticker: "PPLT",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US0032601066"}),
            listingTicker: "PPLT",
            listingName: "abrdn Physical Platinum Shares ETF",
            name: "abrdn Physical Platinum Shares ETF ST0x",
            symbol: "tPPLT",
            region: Region.US,
            underlyingName: "abrdn Physical Platinum Shares ETF",
            isin: "US0032601066"
        });
        configs[9] = TokenConfig({
            underlying: "AMZN",
            ticker: "AMZN",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US0231351067"}),
            listingTicker: "AMZN",
            listingName: "Amazon.com Inc",
            name: "Amazon.com Inc ST0x",
            symbol: "tAMZN",
            region: Region.US,
            underlyingName: "Amazon.com Inc",
            isin: "US0231351067"
        });
        configs[10] = TokenConfig({
            underlying: "BMNR",
            ticker: "BMNR",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US09175A2069"}),
            listingTicker: "BMNR",
            listingName: "Bitmine Immersion Technologies, Inc",
            name: "Bitmine Immersion Technologies, Inc ST0x",
            symbol: "tBMNR",
            region: Region.US,
            underlyingName: "Bitmine Immersion Technologies, Inc",
            isin: "US09175A2069"
        });
        configs[11] = TokenConfig({
            underlying: "IBHG",
            ticker: "IBHG",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US46436E4787"}),
            listingTicker: "IBHG",
            listingName: "iShares iBonds 2027 Term High Yield and Income ETF",
            name: "iShares iBonds 2027 Term High Yield and Income ETF ST0x",
            symbol: "tIBHG",
            region: Region.US,
            underlyingName: "iShares iBonds 2027 Term High Yield and Income ETF",
            isin: "US46436E4787"
        });
        // NB: leading space is present on Base and is reproduced verbatim.
        configs[12] = TokenConfig({
            underlying: "SGOV",
            ticker: "SGOV",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US46436E7186"}),
            listingTicker: "SGOV",
            listingName: "iShares 0-3 Month Treasury Bond ETF",
            name: " iShares 0-3 Month Treasury Bond ETF ST0x",
            symbol: "tSGOV",
            region: Region.US,
            underlyingName: "iShares 0-3 Month Treasury Bond ETF",
            isin: "US46436E7186"
        });
        configs[13] = TokenConfig({
            underlying: "QQQM",
            ticker: "QQQM",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US46138G6492"}),
            listingTicker: "QQQM",
            listingName: "Invesco NASDAQ 100 ETF",
            name: "Invesco NASDAQ 100 ETF ST0x",
            symbol: "tQQQM",
            region: Region.US,
            underlyingName: "Invesco NASDAQ 100 ETF",
            isin: "US46138G6492"
        });
        configs[14] = TokenConfig({
            underlying: "VWO",
            ticker: "VWO",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US9220428588"}),
            listingTicker: "VWO",
            listingName: "Vanguard Emerging Markets Stock Index Fund",
            name: "Vanguard Emerging Markets Stock Index Fund ST0x",
            symbol: "tVWO",
            region: Region.US,
            underlyingName: "Vanguard Emerging Markets Stock Index Fund",
            isin: "US9220428588"
        });
        configs[15] = TokenConfig({
            underlying: "ARKK",
            ticker: "ARKK",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US00214Q1040"}),
            listingTicker: "ARKK",
            listingName: "ARK Innovation ETF",
            name: "ARK Innovation ETF ST0x",
            symbol: "tARKK",
            region: Region.US,
            underlyingName: "ARK Innovation ETF",
            isin: "US00214Q1040"
        });
        configs[16] = TokenConfig({
            underlying: "SPCX",
            ticker: "SPCX",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US84615Q1031"}),
            listingTicker: "SPCX",
            listingName: "Space Exploration Technologies Corp.",
            name: "Space Exploration Technologies Corp. ST0x",
            symbol: "tSPCX",
            region: Region.US,
            underlyingName: "Space Exploration Technologies Corp.",
            isin: "US84615Q1031"
        });
        configs[17] = TokenConfig({
            underlying: "CEG",
            ticker: "CEG",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US21037T1097"}),
            listingTicker: "CEG",
            listingName: "Constellation Energy Corporation",
            name: "Constellation Energy Corporation ST0x",
            symbol: "tCEG",
            region: Region.US,
            underlyingName: "Constellation Energy Corporation",
            isin: "US21037T1097"
        });
        configs[18] = TokenConfig({
            underlying: "DRAM",
            ticker: "DRAM",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US77926X3200"}),
            listingTicker: "DRAM",
            listingName: "Roundhill Memory ETF",
            name: "Roundhill Memory ETF ST0x",
            symbol: "tDRAM",
            region: Region.US,
            underlyingName: "Roundhill Memory ETF",
            isin: "US77926X3200"
        });
        configs[19] = TokenConfig({
            underlying: "TSM",
            ticker: "TSM",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US8740391003"}),
            listingTicker: "TSM",
            listingName: "Taiwan Semiconductor Manufacturing Company Limited ADR",
            name: "Taiwan Semiconductor Manufacturing Company Limited ADR ST0x",
            symbol: "tTSM",
            region: Region.US,
            underlyingName: "Taiwan Semiconductor Manufacturing Company Limited ADR",
            isin: "US8740391003"
        });
        configs[20] = TokenConfig({
            underlying: "SKHY",
            ticker: "SKHY",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US78392B2060"}),
            listingTicker: "SKHY",
            listingName: "SK hynix Inc. ADR",
            name: "SK hynix Inc. ADR ST0x",
            symbol: "tSKHY",
            region: Region.US,
            underlyingName: "SK hynix Inc. ADR",
            isin: "US78392B2060"
        });
        configs[21] = TokenConfig({
            underlying: "ASML",
            ticker: "ASML",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "USN070592100"}),
            listingTicker: "ASML",
            listingName: "ASML Holding N.V.",
            name: "ASML Holding N.V. ST0x",
            symbol: "tASML",
            region: Region.US,
            underlyingName: "ASML Holding N.V.",
            isin: "USN070592100"
        });
        configs[22] = TokenConfig({
            underlying: "MU",
            ticker: "MU",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US5951121038"}),
            listingTicker: "MU",
            listingName: "Micron Technology, Inc.",
            name: "Micron Technology, Inc. ST0x",
            symbol: "tMU",
            region: Region.US,
            underlyingName: "Micron Technology, Inc.",
            isin: "US5951121038"
        });
        configs[23] = TokenConfig({
            underlying: "AMD",
            ticker: "AMD",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US0079031078"}),
            listingTicker: "AMD",
            listingName: "Advanced Micro Devices, Inc.",
            name: "Advanced Micro Devices, Inc. ST0x",
            symbol: "tAMD",
            region: Region.US,
            underlyingName: "Advanced Micro Devices, Inc.",
            isin: "US0079031078"
        });
        configs[24] = TokenConfig({
            underlying: "AVGO",
            ticker: "AVGO",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US11135F1012"}),
            listingTicker: "AVGO",
            listingName: "Broadcom Inc.",
            name: "Broadcom Inc. ST0x",
            symbol: "tAVGO",
            region: Region.US,
            underlyingName: "Broadcom Inc.",
            isin: "US11135F1012"
        });
        configs[25] = TokenConfig({
            underlying: "AMAT",
            ticker: "AMAT",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US0382221051"}),
            listingTicker: "AMAT",
            listingName: "Applied Materials, Inc.",
            name: "Applied Materials, Inc. ST0x",
            symbol: "tAMAT",
            region: Region.US,
            underlyingName: "Applied Materials, Inc.",
            isin: "US0382221051"
        });
        configs[26] = TokenConfig({
            underlying: "LRCX",
            ticker: "LRCX",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US5128073062"}),
            listingTicker: "LRCX",
            listingName: "Lam Research Corporation",
            name: "Lam Research Corporation ST0x",
            symbol: "tLRCX",
            region: Region.US,
            underlyingName: "Lam Research Corporation",
            isin: "US5128073062"
        });
        configs[27] = TokenConfig({
            underlying: "TTWO",
            ticker: "TTWO",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US8740541094"}),
            listingTicker: "TTWO",
            listingName: "Take-Two Interactive Software, Inc.",
            name: "Take-Two Interactive Software, Inc. ST0x",
            symbol: "tTTWO",
            region: Region.US,
            underlyingName: "Take-Two Interactive Software, Inc.",
            isin: "US8740541094"
        });
        configs[28] = TokenConfig({
            underlying: "RKLB",
            ticker: "RKLB",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US7731211089"}),
            listingTicker: "RKLB",
            listingName: "Rocket Lab USA Inc",
            name: "Rocket Lab USA Inc ST0x",
            symbol: "tRKLB",
            region: Region.US,
            underlyingName: "Rocket Lab Corporation",
            isin: "US7731211089"
        });
        configs[29] = TokenConfig({
            underlying: "GOOGL",
            ticker: "GOOGL",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US02079K3059"}),
            listingTicker: "GOOGL",
            listingName: "Alphabet Inc. Class A",
            name: "Alphabet Inc. Class A ST0x",
            symbol: "tGOOGL",
            region: Region.US,
            underlyingName: "Alphabet Inc. Class A",
            isin: "US02079K3059"
        });
        configs[30] = TokenConfig({
            underlying: "AAPL",
            ticker: "AAPL",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US0378331005"}),
            listingTicker: "AAPL",
            listingName: "Apple Inc.",
            name: "Apple Inc. ST0x",
            symbol: "tAAPL",
            region: Region.US,
            underlyingName: "Apple Inc.",
            isin: "US0378331005"
        });
        configs[31] = TokenConfig({
            underlying: "MSFT",
            ticker: "MSFT",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US5949181045"}),
            listingTicker: "MSFT",
            listingName: "Microsoft Corporation",
            name: "Microsoft Corporation ST0x",
            symbol: "tMSFT",
            region: Region.US,
            underlyingName: "Microsoft Corporation",
            isin: "US5949181045"
        });
        configs[32] = TokenConfig({
            underlying: "LLY",
            ticker: "LLY",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US5324571083"}),
            listingTicker: "LLY",
            listingName: "Eli Lilly and Company",
            name: "Eli Lilly and Company ST0x",
            symbol: "tLLY",
            region: Region.US,
            underlyingName: "Eli Lilly and Company",
            isin: "US5324571083"
        });
        configs[33] = TokenConfig({
            underlying: "PTY",
            ticker: "PTY",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US72201B1017"}),
            listingTicker: "PTY",
            listingName: "PIMCO Corporate & Income Opportunity Fund",
            name: "PIMCO Corporate & Income Opportunity Fund ST0x",
            symbol: "tPTY",
            region: Region.US,
            underlyingName: "PIMCO Corporate & Income Opportunity Fund",
            isin: "US72201B1017"
        });
        configs[34] = TokenConfig({
            underlying: "INTC",
            ticker: "INTC",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US4581401001"}),
            listingTicker: "INTC",
            listingName: "Intel Corporation",
            name: "Intel Corporation ST0x",
            symbol: "tINTC",
            region: Region.US,
            underlyingName: "Intel Corporation",
            isin: "US4581401001"
        });
        configs[35] = TokenConfig({
            underlying: "HOOD",
            ticker: "HOOD",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US7707001027"}),
            listingTicker: "HOOD",
            listingName: "Robinhood Markets, Inc.",
            name: "Robinhood Markets, Inc. ST0x",
            symbol: "tHOOD",
            region: Region.US,
            underlyingName: "Robinhood Markets, Inc.",
            isin: "US7707001027"
        });
        configs[36] = TokenConfig({
            underlying: "ORCL",
            ticker: "ORCL",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US68389X1054"}),
            listingTicker: "ORCL",
            listingName: "Oracle Corporation",
            name: "Oracle Corporation ST0x",
            symbol: "tORCL",
            region: Region.US,
            underlyingName: "Oracle Corporation",
            isin: "US68389X1054"
        });
        configs[37] = TokenConfig({
            underlying: "SMCI",
            ticker: "SMCI",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US86800U3023"}),
            listingTicker: "SMCI",
            listingName: "Super Micro Computer, Inc.",
            name: "Super Micro Computer, Inc. ST0x",
            symbol: "tSMCI",
            region: Region.US,
            underlyingName: "Super Micro Computer, Inc.",
            isin: "US86800U3023"
        });
        configs[38] = TokenConfig({
            underlying: "BABA",
            ticker: "BABA",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US01609W1027"}),
            listingTicker: "BABA",
            listingName: "Alibaba Group Holding Limited ADR",
            name: "Alibaba Group Holding Limited ADR ST0x",
            symbol: "tBABA",
            region: Region.US,
            underlyingName: "Alibaba Group Holding Limited ADR",
            isin: "US01609W1027"
        });
        configs[39] = TokenConfig({
            underlying: "TQQQ",
            ticker: "TQQQ",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US74347X8314"}),
            listingTicker: "TQQQ",
            listingName: "ProShares UltraPro QQQ",
            name: "ProShares UltraPro QQQ ST0x",
            symbol: "tTQQQ",
            region: Region.US,
            underlyingName: "ProShares UltraPro QQQ",
            isin: "US74347X8314"
        });
        configs[40] = TokenConfig({
            underlying: "FTF",
            ticker: "FTF",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US35472T1016"}),
            listingTicker: "FTF",
            listingName: "Franklin Limited Duration Income Trust",
            name: "Franklin Limited Duration Income Trust ST0x",
            symbol: "tFTF",
            region: Region.US,
            underlyingName: "Franklin Limited Duration Income Trust",
            isin: "US35472T1016"
        });
        configs[41] = TokenConfig({
            underlying: "CBRS",
            ticker: "CBRS",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US15675D1037"}),
            listingTicker: "CBRS",
            listingName: "Cerebras Systems Inc.",
            name: "Cerebras Systems Inc. ST0x",
            symbol: "tCBRS",
            region: Region.US,
            underlyingName: "Cerebras Systems Inc.",
            isin: "US15675D1037"
        });
        configs[42] = TokenConfig({
            underlying: "MCD",
            ticker: "MCD",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US5801351017"}),
            listingTicker: "MCD",
            listingName: "McDonald's Corporation",
            name: "McDonald's Corporation ST0x",
            symbol: "tMCD",
            region: Region.US,
            underlyingName: "McDonald's Corporation",
            isin: "US5801351017"
        });
        configs[43] = TokenConfig({
            underlying: "NKE",
            ticker: "NKE",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US6541061031"}),
            listingTicker: "NKE",
            listingName: "NIKE, Inc.",
            name: "NIKE, Inc. ST0x",
            symbol: "tNKE",
            region: Region.US,
            underlyingName: "NIKE, Inc.",
            isin: "US6541061031"
        });
        configs[44] = TokenConfig({
            underlying: "GRND",
            ticker: "GRND",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US39854F1012"}),
            listingTicker: "GRND",
            listingName: "Grindr Inc.",
            name: "Grindr Inc. ST0x",
            symbol: "tGRND",
            region: Region.US,
            underlyingName: "Grindr Inc.",
            isin: "US39854F1012"
        });
        configs[45] = TokenConfig({
            underlying: "DNUT",
            ticker: "DNUT",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US50101L1061"}),
            listingTicker: "DNUT",
            listingName: "Krispy Kreme, Inc.",
            name: "Krispy Kreme, Inc. ST0x",
            symbol: "tDNUT",
            region: Region.US,
            underlyingName: "Krispy Kreme, Inc.",
            isin: "US50101L1061"
        });
        configs[46] = TokenConfig({
            underlying: "PLBY",
            ticker: "PLBY",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US72814P1093"}),
            listingTicker: "PLBY",
            listingName: "Playboy, Inc.",
            name: "Playboy, Inc. ST0x",
            symbol: "tPLBY",
            region: Region.US,
            underlyingName: "Playboy, Inc.",
            isin: "US72814P1093"
        });
        configs[47] = TokenConfig({
            underlying: "TR",
            ticker: "TR",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US8905161076"}),
            listingTicker: "TR",
            listingName: "Tootsie Roll Industries, Inc.",
            name: "Tootsie Roll Industries, Inc. ST0x",
            symbol: "tTR",
            region: Region.US,
            underlyingName: "Tootsie Roll Industries, Inc.",
            isin: "US8905161076"
        });
        configs[48] = TokenConfig({
            underlying: "WEN",
            ticker: "WEN",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US95058W1009"}),
            listingTicker: "WEN",
            listingName: "The Wendy's Company",
            name: "The Wendy's Company ST0x",
            symbol: "tWEN",
            region: Region.US,
            underlyingName: "The Wendy's Company",
            isin: "US95058W1009"
        });
        configs[49] = TokenConfig({
            underlying: "FGI",
            ticker: "FGI",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "KYG3302D2024"}),
            listingTicker: "FGI",
            listingName: "FGI Industries Ltd.",
            name: "FGI Industries Ltd. ST0x",
            symbol: "tFGI",
            region: Region.US,
            underlyingName: "FGI Industries Ltd.",
            isin: "KYG3302D2024"
        });
        // tBIRD — Smartbird, Inc. is the former Allbirds, Inc. (renamed 2026, same
        // Nasdaq listing); name derived the way sft-ops derives it
        // (`"<metadata.name> ST0x"`, `"t<code>"`) from sft-ops `metadata/bird.json`.
        configs[50] = TokenConfig({
            underlying: "BIRD",
            ticker: "BIRD",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US01675A2087"}),
            listingTicker: "BIRD",
            listingName: "Smartbird, Inc.",
            name: "Smartbird, Inc. ST0x",
            symbol: "tBIRD",
            region: Region.US,
            underlyingName: "Smartbird, Inc.",
            isin: "US01675A2087"
        });
        // tSPY — name derived from sft-ops `metadata/spy.json` the way CD derives it
        // (`"<metadata.name> ST0x"`, `"t<code>"`); verified against the live Base vault.
        configs[51] = TokenConfig({
            underlying: "SPY",
            ticker: "SPY",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US78462F1030"}),
            listingTicker: "SPY",
            listingName: "State Street SPDR S&P 500 ETF Trust",
            name: "State Street SPDR S&P 500 ETF Trust ST0x",
            symbol: "tSPY",
            region: Region.US,
            underlyingName: "State Street SPDR S&P 500 ETF Trust",
            isin: "US78462F1030"
        });
        // tSNES — name derived from sft-ops `metadata/snes.json` the way CD derives it;
        // verified against the live Base vault.
        configs[52] = TokenConfig({
            underlying: "SNES",
            ticker: "SNES",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US81720R6045"}),
            listingTicker: "SNES",
            listingName: "SenesTech, Inc.",
            name: "SenesTech, Inc. ST0x",
            symbol: "tSNES",
            region: Region.US,
            underlyingName: "SenesTech, Inc.",
            isin: "US81720R6045"
        });
        // tWMT — name derived from sft-ops `metadata/wmt.json` the way CD derives it;
        // verified against the live Base vault. Ahead of tMC because it reached
        // Base first (sft-ops CD run 37747102500); the tables pair by index.
        configs[53] = TokenConfig({
            underlying: "WMT",
            ticker: "WMT",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US9311421039"}),
            listingTicker: "WMT",
            listingName: "Walmart Inc.",
            name: "Walmart Inc. ST0x",
            symbol: "tWMT",
            region: Region.US,
            underlyingName: "Walmart Inc.",
            isin: "US9311421039"
        });
        configs[54] = TokenConfig({
            underlying: "MC",
            ticker: "MC",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "FR0000121014"}),
            listingTicker: "MC",
            listingName: unicode"LVMH Moët Hennessy Louis Vuitton SE",
            name: unicode"LVMH Moët Hennessy Louis Vuitton SE ST0x",
            symbol: "tMC",
            region: Region.EU,
            underlyingName: unicode"LVMH Moët Hennessy Louis Vuitton SE",
            isin: "FR0000121014"
        });
        configs[55] = TokenConfig({
            underlying: "DIS",
            ticker: "DIS",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US2546871060"}),
            listingTicker: "DIS",
            listingName: "The Walt Disney Company",
            name: "The Walt Disney Company ST0x",
            symbol: "tDIS",
            region: Region.US,
            underlyingName: "The Walt Disney Company",
            isin: "US2546871060"
        });
        configs[56] = TokenConfig({
            underlying: "IFX",
            ticker: "IFX",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "DE0006231004"}),
            listingTicker: "IFX",
            listingName: "Infineon Technologies AG",
            name: "Infineon Technologies AG ST0x",
            symbol: "tIFX",
            region: Region.EU,
            underlyingName: "Infineon Technologies AG",
            isin: "DE0006231004"
        });
        configs[57] = TokenConfig({
            underlying: "SOI",
            ticker: "SOI",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "FR0013227113"}),
            listingTicker: "SOI",
            listingName: "Soitec SA",
            name: "Soitec SA ST0x",
            symbol: "tSOI",
            region: Region.EU,
            underlyingName: "Soitec SA",
            isin: "FR0013227113"
        });
        configs[58] = TokenConfig({
            underlying: "TPRO",
            ticker: "TPRO",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "IT0005482333"}),
            listingTicker: "TPRO",
            listingName: "Technoprobe S.p.A.",
            name: "Technoprobe S.p.A. ST0x",
            symbol: "tTPRO",
            region: Region.EU,
            underlyingName: "Technoprobe S.p.A.",
            isin: "IT0005482333"
        });
    }

    /// @notice Tokens live on Ethereum, HyperEVM, Robinhood and BSC that no Base row carries, with Ethereum's verbatim
    /// names and symbols. Every chain issues them under US, so their region routes them to the US authoriser.
    /// @return configs The rows.
    function offBaseTokenConfigs() internal pure returns (TokenConfig[] memory configs) {
        configs = new TokenConfig[](6);
        configs[0] = TokenConfig({
            underlying: "AIR.PA",
            ticker: "AIR.PA",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "NL0000235190"}),
            listingTicker: "AIR",
            listingName: "Airbus SE",
            name: "Airbus SE ST0x",
            symbol: "tAIR.PA",
            region: Region.US,
            underlyingName: "Airbus SE",
            isin: "NL0000235190"
        });
        configs[1] = TokenConfig({
            underlying: "BMW.DE",
            ticker: "BMW.DE",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "DE0005190003"}),
            listingTicker: "BMW",
            listingName: "Bayerische Motoren Werke Aktiengesellschaft",
            name: "Bayerische Motoren Werke Aktiengesellschaft ST0x",
            symbol: "tBMW.DE",
            region: Region.US,
            underlyingName: "Bayerische Motoren Werke Aktiengesellschaft",
            isin: "DE0005190003"
        });
        configs[2] = TokenConfig({
            underlying: "MC.PA",
            ticker: "MC.PA",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "FR0000121014"}),
            listingTicker: "MC",
            listingName: unicode"LVMH Moët Hennessy Louis Vuitton SE",
            name: unicode"LVMH Moët Hennessy Louis Vuitton SE ST0x",
            symbol: "tMC.PA",
            region: Region.US,
            underlyingName: unicode"LVMH Moët Hennessy Louis Vuitton SE",
            isin: "FR0000121014"
        });
        configs[3] = TokenConfig({
            underlying: "SIE.DE",
            ticker: "SIE.DE",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "DE0007236101"}),
            listingTicker: "SIE",
            listingName: "Siemens Aktiengesellschaft",
            name: "Siemens Aktiengesellschaft ST0x",
            symbol: "tSIE.DE",
            region: Region.US,
            underlyingName: "Siemens Aktiengesellschaft",
            isin: "DE0007236101"
        });
        configs[4] = TokenConfig({
            underlying: "MBG.DE",
            ticker: "MBG.DE",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "DE0007100000"}),
            listingTicker: "MBG",
            listingName: "Mercedes-Benz Group AG",
            name: "Mercedes-Benz Group AG ST0x",
            symbol: "tMBG.DE",
            region: Region.US,
            underlyingName: "Mercedes-Benz Group AG",
            isin: "DE0007100000"
        });
        configs[5] = TokenConfig({
            underlying: "RHM.DE",
            ticker: "RHM.DE",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "DE0007030009"}),
            listingTicker: "RHM",
            listingName: "Rheinmetall AG",
            name: "Rheinmetall AG ST0x",
            symbol: "tRHM.DE",
            region: Region.US,
            underlyingName: "Rheinmetall AG",
            isin: "DE0007030009"
        });
    }

    /// @notice The canonical token order: the 0.1.1 beacon-set deployers' creation sequence that Ethereum and HyperEVM
    /// agree on, slots 0-64. A chain created in this order holds the same token at the same address.
    /// @return The underlyings.
    function canonicalTokenOrder() internal pure returns (string[65] memory) {
        return [
            "MSTR",
            "TSLA",
            "COIN",
            "SPYM",
            "SIVR",
            "CRCL",
            "NVDA",
            "IAU",
            "PPLT",
            "AMZN",
            "BMNR",
            "IBHG",
            "SGOV",
            "QQQM",
            "VWO",
            "ARKK",
            "SPCX",
            "CEG",
            "DRAM",
            "TSM",
            "SKHY",
            "ASML",
            "MU",
            "AMD",
            "AVGO",
            "AMAT",
            "LRCX",
            "TTWO",
            "RKLB",
            "HOOD",
            "ORCL",
            "SMCI",
            "BABA",
            "TQQQ",
            "AAPL",
            "GOOGL",
            "INTC",
            "LLY",
            "MSFT",
            "PTY",
            "FTF",
            "CBRS",
            "AIR.PA",
            "BMW.DE",
            "MC.PA",
            "SIE.DE",
            "MBG.DE",
            "RHM.DE",
            "MCD",
            "NKE",
            "GRND",
            "DNUT",
            "PLBY",
            "TR",
            "WEN",
            "FGI",
            "BIRD",
            "SPY",
            "SNES",
            "WMT",
            "MC",
            "DIS",
            "IFX",
            "SOI",
            "TPRO"
        ];
    }

    /// @notice The canonical token rows, in `canonicalTokenOrder`.
    /// @return configs The rows.
    function canonicalTokenConfigs() internal pure returns (TokenConfig[] memory configs) {
        string[65] memory order = canonicalTokenOrder();
        TokenConfig[] memory production = productionTokenConfigs();
        TokenConfig[] memory offBase = offBaseTokenConfigs();
        configs = new TokenConfig[](order.length);
        for (uint256 i = 0; i < order.length; i++) {
            configs[i] = rowIn(order[i], production, offBase);
        }
    }

    /// @notice The row for `underlying` in `first`, else in `second`.
    /// @param underlying The ticker join key.
    /// @param first The table searched first.
    /// @param second The table searched next.
    /// @return The row. Reverts `UnknownUnderlying` when neither has one.
    function rowIn(string memory underlying, TokenConfig[] memory first, TokenConfig[] memory second)
        internal
        pure
        returns (TokenConfig memory)
    {
        bytes32 key = keccak256(bytes(underlying));
        for (uint256 i = 0; i < first.length; i++) {
            if (keccak256(bytes(first[i].underlying)) == key) return first[i];
        }
        for (uint256 i = 0; i < second.length; i++) {
            if (keccak256(bytes(second[i].underlying)) == key) return second[i];
        }
        revert UnknownUnderlying(underlying);
    }

    function testTokenConfigs() internal pure returns (TokenConfig[] memory) {
        TokenConfig[] memory configs = new TokenConfig[](2);
        configs[0] = TokenConfig({
            underlying: "USTEST",
            ticker: "USTEST",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US78462F1030"}),
            listingTicker: "USTEST",
            listingName: "US Test",
            name: "US Test ST0x",
            symbol: "tUSTEST",
            region: Region.US,
            underlyingName: "",
            isin: "US78462F1030"
        });
        configs[1] = TokenConfig({
            underlying: "EUTEST",
            ticker: "EUTEST",
            assetId: AssetId({kind: AssetIdKind.ISIN, id: "US78462F1030"}),
            listingTicker: "EUTEST",
            listingName: "EU Test",
            name: "EU Test ST0x",
            symbol: "tEUTEST",
            region: Region.EU,
            underlyingName: "",
            isin: "US78462F1030"
        });
        return configs;
    }

    /// @notice The production or off-Base row for `underlying`.
    /// @param underlying The ticker join key.
    /// @return The row. Reverts `UnknownUnderlying` when there is none.
    function configOf(string memory underlying) internal pure returns (TokenConfig memory) {
        return rowIn(underlying, productionTokenConfigs(), offBaseTokenConfigs());
    }

    /// @notice The row of `table` for `underlying`.
    /// @param underlying The ticker join key.
    /// @param table The table searched, e.g. one `canonicalTokenConfigs()`
    /// build shared across many lookups.
    /// @return The row. Reverts `UnknownUnderlying` when there is none.
    function configOf(string memory underlying, TokenConfig[] memory table) internal pure returns (TokenConfig memory) {
        return rowIn(underlying, table, new TokenConfig[](0));
    }

    /// @notice The region of the production or off-Base row for
    /// `underlying`.
    /// @param underlying The ticker join key.
    /// @return The row's region. Reverts `UnknownUnderlying` when there is
    /// none.
    function regionOf(string memory underlying) internal pure returns (Region) {
        return configOf(underlying).region;
    }
}

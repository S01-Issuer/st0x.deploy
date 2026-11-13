// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @notice The deploy-time configuration for one production token — the
/// inputs `StoxUnifiedDeployer.newTokenAndWrapperVault` needs to reproduce
/// a Base token instance on another chain.
/// @dev Of the deploy inputs, only `name` + `symbol` are captured: the offchain-asset receipt
/// vault takes `asset = address(0)` (the asset is offchain) and
/// `receipt = address(0)` (the beacon-set deployer wires the receipt),
/// `initialAdmin` is the target chain's Safe (supplied by the deploy
/// script, not the table), `decimals` is fixed by the shared vault
/// implementation bytecode, and the wrapped token vault derives its own
/// name/symbol on-chain from the receipt vault. So the receipt vault's
/// `name` + `symbol` are the ONLY free initialization inputs, and this table
/// holds exactly those.
///
/// The underlying snapshot is built from `ticker`, `underlyingName` and
/// `isin`; the vault owner can override them with
/// `IStoxUnderlyingV2.setUnderlying`. Once resolved, the receipt vault reports
/// `"t" + ticker` / `underlyingName + " (ST0x)"` and the wrapped token vault
/// `ticker + "s"` / the receipt vault's name. A legacy token with no
/// snapshot row and no override reports the `name` + `symbol` it was
/// initialized with, and the wrapped token vault `"Wrapped " + name` /
/// `"w" + symbol`.
/// @param underlying The frozen chain-agnostic join key, matching
/// `LibTokenInvariants.TokenInstance.underlying`.
/// @param ticker The current underlying ticker: the `ticker` argument of
/// `setUnderlying`.
/// @param name The receipt vault's ERC-20 `name()`, verbatim from Base.
/// @param symbol The receipt vault's ERC-20 `symbol()`, verbatim from Base.
/// @param region Where the underlying is listed.
/// @param underlyingName The issuer's current legal name, without any ST0x
/// suffix: the `name` argument of `setUnderlying`. Usually the live `name`
/// without " ST0x"; it differs where the issuer has since been renamed
/// (MSTR, RKLB).
/// @param isin The underlying share line's current ISIN.
struct TokenConfig {
    string assetId;
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

enum Region {
    US,
    EU
}

/// @dev Unix seconds the underlying snapshot was cut from this table.
uint256 constant UNDERLYING_SNAPSHOT_AS_OF = 1794441600;

/// @notice The underlying has no row in the production token table.
error UnknownUnderlying(string underlying);

/// @title LibProdTokenConfig
/// @notice The canonical name/symbol table for the ST0x production
/// tokens, captured verbatim from the live Base receipt vaults so a new
/// chain's token set can be deployed byte-identical to Base. This is the
/// deploy-input companion to `LibTokenInvariants` (which holds the deployed
/// addresses): the deploy script reads this to author the
/// `newTokenAndWrapperVault` calls, and it is the CANONICAL BASELINE the
/// cross-chain parity pin asserts every chain's live `name`/`symbol` against
/// (Base included — `LibProdTokenConfigTest` pins this table to live Base, so
/// the baseline itself is validated, not just chain-vs-chain).
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
            assetId: "US5949724083",
            listingTicker: "MSTR",
            listingName: "MicroStrategy Incorporated",
            name: "MicroStrategy Incorporated ST0x",
            symbol: "tMSTR",
            region: Region.US,
            underlyingName: "Strategy Inc",
            isin: ""
        });
        configs[1] = TokenConfig({
            underlying: "TSLA",
            ticker: "TSLA",
            assetId: "US88160R1014",
            listingTicker: "TSLA",
            listingName: "Tesla Inc",
            name: "Tesla Inc ST0x",
            symbol: "tTSLA",
            region: Region.US,
            underlyingName: "Tesla Inc",
            isin: ""
        });
        configs[2] = TokenConfig({
            underlying: "COIN",
            ticker: "COIN",
            assetId: "US19260Q1076",
            listingTicker: "COIN",
            listingName: "Coinbase Global Inc",
            name: "Coinbase Global Inc ST0x",
            symbol: "tCOIN",
            region: Region.US,
            underlyingName: "Coinbase Global Inc",
            isin: ""
        });
        configs[3] = TokenConfig({
            underlying: "SPYM",
            ticker: "SPYM",
            assetId: "US78464A8541",
            listingTicker: "SPYM",
            listingName: "State Street SPDR Portfolio S&P 500 ETF",
            name: "State Street SPDR Portfolio S&P 500 ETF ST0x",
            symbol: "tSPYM",
            region: Region.US,
            underlyingName: "State Street SPDR Portfolio S&P 500 ETF",
            isin: ""
        });
        configs[4] = TokenConfig({
            underlying: "SIVR",
            ticker: "SIVR",
            assetId: "US0032641088",
            listingTicker: "SIVR",
            listingName: "abrdn Physical Silver Shares ETF",
            name: "abrdn Physical Silver Shares ETF ST0x",
            symbol: "tSIVR",
            region: Region.US,
            underlyingName: "abrdn Physical Silver Shares ETF",
            isin: ""
        });
        configs[5] = TokenConfig({
            underlying: "CRCL",
            ticker: "CRCL",
            assetId: "US1725731079",
            listingTicker: "CRCL",
            listingName: "Circle Internet Group Inc",
            name: "Circle Internet Group Inc ST0x",
            symbol: "tCRCL",
            region: Region.US,
            underlyingName: "Circle Internet Group Inc",
            isin: ""
        });
        configs[6] = TokenConfig({
            underlying: "NVDA",
            ticker: "NVDA",
            assetId: "US67066G1040",
            listingTicker: "NVDA",
            listingName: "NVIDIA Corporation",
            name: "NVIDIA Corporation ST0x",
            symbol: "tNVDA",
            region: Region.US,
            underlyingName: "NVIDIA Corporation",
            isin: ""
        });
        configs[7] = TokenConfig({
            underlying: "IAU",
            ticker: "IAU",
            assetId: "US4642852044",
            listingTicker: "IAU",
            listingName: "iShares Gold Trust",
            name: "iShares Gold Trust ST0x",
            symbol: "tIAU",
            region: Region.US,
            underlyingName: "iShares Gold Trust",
            isin: ""
        });
        configs[8] = TokenConfig({
            underlying: "PPLT",
            ticker: "PPLT",
            assetId: "US0032601066",
            listingTicker: "PPLT",
            listingName: "abrdn Physical Platinum Shares ETF",
            name: "abrdn Physical Platinum Shares ETF ST0x",
            symbol: "tPPLT",
            region: Region.US,
            underlyingName: "abrdn Physical Platinum Shares ETF",
            isin: ""
        });
        configs[9] = TokenConfig({
            underlying: "AMZN",
            ticker: "AMZN",
            assetId: "US0231351067",
            listingTicker: "AMZN",
            listingName: "Amazon.com Inc",
            name: "Amazon.com Inc ST0x",
            symbol: "tAMZN",
            region: Region.US,
            underlyingName: "Amazon.com Inc",
            isin: ""
        });
        configs[10] = TokenConfig({
            underlying: "BMNR",
            ticker: "BMNR",
            assetId: "US09175A2069",
            listingTicker: "BMNR",
            listingName: "Bitmine Immersion Technologies, Inc",
            name: "Bitmine Immersion Technologies, Inc ST0x",
            symbol: "tBMNR",
            region: Region.US,
            underlyingName: "Bitmine Immersion Technologies, Inc",
            isin: ""
        });
        configs[11] = TokenConfig({
            underlying: "IBHG",
            ticker: "IBHG",
            assetId: "US46436E4787",
            listingTicker: "IBHG",
            listingName: "iShares iBonds 2027 Term High Yield and Income ETF",
            name: "iShares iBonds 2027 Term High Yield and Income ETF ST0x",
            symbol: "tIBHG",
            region: Region.US,
            underlyingName: "iShares iBonds 2027 Term High Yield and Income ETF",
            isin: ""
        });
        // NB: leading space is present on Base and is reproduced verbatim.
        configs[12] = TokenConfig({
            underlying: "SGOV",
            ticker: "SGOV",
            assetId: "US46436E7186",
            listingTicker: "SGOV",
            listingName: " iShares 0-3 Month Treasury Bond ETF",
            name: " iShares 0-3 Month Treasury Bond ETF ST0x",
            symbol: "tSGOV",
            region: Region.US,
            underlyingName: "iShares 0-3 Month Treasury Bond ETF",
            isin: ""
        });
        configs[13] = TokenConfig({
            underlying: "QQQM",
            ticker: "QQQM",
            assetId: "US46138G6492",
            listingTicker: "QQQM",
            listingName: "Invesco NASDAQ 100 ETF",
            name: "Invesco NASDAQ 100 ETF ST0x",
            symbol: "tQQQM",
            region: Region.US,
            underlyingName: "Invesco NASDAQ 100 ETF",
            isin: ""
        });
        configs[14] = TokenConfig({
            underlying: "VWO",
            ticker: "VWO",
            assetId: "US9220428588",
            listingTicker: "VWO",
            listingName: "Vanguard Emerging Markets Stock Index Fund",
            name: "Vanguard Emerging Markets Stock Index Fund ST0x",
            symbol: "tVWO",
            region: Region.US,
            underlyingName: "Vanguard Emerging Markets Stock Index Fund",
            isin: ""
        });
        configs[15] = TokenConfig({
            underlying: "ARKK",
            ticker: "ARKK",
            assetId: "US00214Q1040",
            listingTicker: "ARKK",
            listingName: "ARK Innovation ETF",
            name: "ARK Innovation ETF ST0x",
            symbol: "tARKK",
            region: Region.US,
            underlyingName: "ARK Innovation ETF",
            isin: ""
        });
        configs[16] = TokenConfig({
            underlying: "SPCX",
            ticker: "SPCX",
            assetId: "US84615Q1031",
            listingTicker: "SPCX",
            listingName: "Space Exploration Technologies Corp.",
            name: "Space Exploration Technologies Corp. ST0x",
            symbol: "tSPCX",
            region: Region.US,
            underlyingName: "Space Exploration Technologies Corp.",
            isin: ""
        });
        configs[17] = TokenConfig({
            underlying: "CEG",
            ticker: "CEG",
            assetId: "US21037T1097",
            listingTicker: "CEG",
            listingName: "Constellation Energy Corporation",
            name: "Constellation Energy Corporation ST0x",
            symbol: "tCEG",
            region: Region.US,
            underlyingName: "Constellation Energy Corporation",
            isin: ""
        });
        configs[18] = TokenConfig({
            underlying: "DRAM",
            ticker: "DRAM",
            assetId: "US77926X3200",
            listingTicker: "DRAM",
            listingName: "Roundhill Memory ETF",
            name: "Roundhill Memory ETF ST0x",
            symbol: "tDRAM",
            region: Region.US,
            underlyingName: "Roundhill Memory ETF",
            isin: ""
        });
        configs[19] = TokenConfig({
            underlying: "TSM",
            ticker: "TSM",
            assetId: "US8740391003",
            listingTicker: "TSM",
            listingName: "Taiwan Semiconductor Manufacturing Company Limited ADR",
            name: "Taiwan Semiconductor Manufacturing Company Limited ADR ST0x",
            symbol: "tTSM",
            region: Region.US,
            underlyingName: "Taiwan Semiconductor Manufacturing Company Limited ADR",
            isin: ""
        });
        configs[20] = TokenConfig({
            underlying: "SKHY",
            ticker: "SKHY",
            assetId: "US78392B2060",
            listingTicker: "SKHY",
            listingName: "SK hynix Inc. ADR",
            name: "SK hynix Inc. ADR ST0x",
            symbol: "tSKHY",
            region: Region.US,
            underlyingName: "SK hynix Inc. ADR",
            isin: ""
        });
        configs[21] = TokenConfig({
            underlying: "ASML",
            ticker: "ASML",
            assetId: "USN070592100",
            listingTicker: "ASML",
            listingName: "ASML Holding N.V.",
            name: "ASML Holding N.V. ST0x",
            symbol: "tASML",
            region: Region.US,
            underlyingName: "ASML Holding N.V.",
            isin: ""
        });
        configs[22] = TokenConfig({
            underlying: "MU",
            ticker: "MU",
            assetId: "US5951121038",
            listingTicker: "MU",
            listingName: "Micron Technology, Inc.",
            name: "Micron Technology, Inc. ST0x",
            symbol: "tMU",
            region: Region.US,
            underlyingName: "Micron Technology, Inc.",
            isin: ""
        });
        configs[23] = TokenConfig({
            underlying: "AMD",
            ticker: "AMD",
            assetId: "US0079031078",
            listingTicker: "AMD",
            listingName: "Advanced Micro Devices, Inc.",
            name: "Advanced Micro Devices, Inc. ST0x",
            symbol: "tAMD",
            region: Region.US,
            underlyingName: "Advanced Micro Devices, Inc.",
            isin: ""
        });
        configs[24] = TokenConfig({
            underlying: "AVGO",
            ticker: "AVGO",
            assetId: "US11135F1012",
            listingTicker: "AVGO",
            listingName: "Broadcom Inc.",
            name: "Broadcom Inc. ST0x",
            symbol: "tAVGO",
            region: Region.US,
            underlyingName: "Broadcom Inc.",
            isin: ""
        });
        configs[25] = TokenConfig({
            underlying: "AMAT",
            ticker: "AMAT",
            assetId: "US0382221051",
            listingTicker: "AMAT",
            listingName: "Applied Materials, Inc.",
            name: "Applied Materials, Inc. ST0x",
            symbol: "tAMAT",
            region: Region.US,
            underlyingName: "Applied Materials, Inc.",
            isin: ""
        });
        configs[26] = TokenConfig({
            underlying: "LRCX",
            ticker: "LRCX",
            assetId: "US5128073062",
            listingTicker: "LRCX",
            listingName: "Lam Research Corporation",
            name: "Lam Research Corporation ST0x",
            symbol: "tLRCX",
            region: Region.US,
            underlyingName: "Lam Research Corporation",
            isin: ""
        });
        configs[27] = TokenConfig({
            underlying: "TTWO",
            ticker: "TTWO",
            assetId: "US8740541094",
            listingTicker: "TTWO",
            listingName: "Take-Two Interactive Software, Inc.",
            name: "Take-Two Interactive Software, Inc. ST0x",
            symbol: "tTTWO",
            region: Region.US,
            underlyingName: "Take-Two Interactive Software, Inc.",
            isin: ""
        });
        configs[28] = TokenConfig({
            underlying: "RKLB",
            ticker: "RKLB",
            assetId: "",
            listingTicker: "RKLB",
            listingName: "Rocket Lab USA Inc",
            name: "Rocket Lab USA Inc ST0x",
            symbol: "tRKLB",
            region: Region.US,
            underlyingName: "Rocket Lab Corporation",
            isin: ""
        });
        configs[29] = TokenConfig({
            underlying: "GOOGL",
            ticker: "GOOGL",
            assetId: "US02079K3059",
            listingTicker: "GOOGL",
            listingName: "Alphabet Inc. Class A",
            name: "Alphabet Inc. Class A ST0x",
            symbol: "tGOOGL",
            region: Region.US,
            underlyingName: "Alphabet Inc. Class A",
            isin: ""
        });
        configs[30] = TokenConfig({
            underlying: "AAPL",
            ticker: "AAPL",
            assetId: "US0378331005",
            listingTicker: "AAPL",
            listingName: "Apple Inc.",
            name: "Apple Inc. ST0x",
            symbol: "tAAPL",
            region: Region.US,
            underlyingName: "Apple Inc.",
            isin: ""
        });
        configs[31] = TokenConfig({
            underlying: "MSFT",
            ticker: "MSFT",
            assetId: "US5949181045",
            listingTicker: "MSFT",
            listingName: "Microsoft Corporation",
            name: "Microsoft Corporation ST0x",
            symbol: "tMSFT",
            region: Region.US,
            underlyingName: "Microsoft Corporation",
            isin: ""
        });
        configs[32] = TokenConfig({
            underlying: "LLY",
            ticker: "LLY",
            assetId: "US5324571083",
            listingTicker: "LLY",
            listingName: "Eli Lilly and Company",
            name: "Eli Lilly and Company ST0x",
            symbol: "tLLY",
            region: Region.US,
            underlyingName: "Eli Lilly and Company",
            isin: ""
        });
        configs[33] = TokenConfig({
            underlying: "PTY",
            ticker: "PTY",
            assetId: "US72201B1017",
            listingTicker: "PTY",
            listingName: "PIMCO Corporate & Income Opportunity Fund",
            name: "PIMCO Corporate & Income Opportunity Fund ST0x",
            symbol: "tPTY",
            region: Region.US,
            underlyingName: "PIMCO Corporate & Income Opportunity Fund",
            isin: ""
        });
        configs[34] = TokenConfig({
            underlying: "INTC",
            ticker: "INTC",
            assetId: "US4581401001",
            listingTicker: "INTC",
            listingName: "Intel Corporation",
            name: "Intel Corporation ST0x",
            symbol: "tINTC",
            region: Region.US,
            underlyingName: "Intel Corporation",
            isin: ""
        });
        configs[35] = TokenConfig({
            underlying: "HOOD",
            ticker: "HOOD",
            assetId: "US7707001027",
            listingTicker: "HOOD",
            listingName: "Robinhood Markets, Inc.",
            name: "Robinhood Markets, Inc. ST0x",
            symbol: "tHOOD",
            region: Region.US,
            underlyingName: "Robinhood Markets, Inc.",
            isin: ""
        });
        configs[36] = TokenConfig({
            underlying: "ORCL",
            ticker: "ORCL",
            assetId: "US68389X1054",
            listingTicker: "ORCL",
            listingName: "Oracle Corporation",
            name: "Oracle Corporation ST0x",
            symbol: "tORCL",
            region: Region.US,
            underlyingName: "Oracle Corporation",
            isin: ""
        });
        configs[37] = TokenConfig({
            underlying: "SMCI",
            ticker: "SMCI",
            assetId: "US86800U3023",
            listingTicker: "SMCI",
            listingName: "Super Micro Computer, Inc.",
            name: "Super Micro Computer, Inc. ST0x",
            symbol: "tSMCI",
            region: Region.US,
            underlyingName: "Super Micro Computer, Inc.",
            isin: ""
        });
        configs[38] = TokenConfig({
            underlying: "BABA",
            ticker: "BABA",
            assetId: "US01609W1027",
            listingTicker: "BABA",
            listingName: "Alibaba Group Holding Limited ADR",
            name: "Alibaba Group Holding Limited ADR ST0x",
            symbol: "tBABA",
            region: Region.US,
            underlyingName: "Alibaba Group Holding Limited ADR",
            isin: ""
        });
        configs[39] = TokenConfig({
            underlying: "TQQQ",
            ticker: "TQQQ",
            assetId: "US74347X8314",
            listingTicker: "TQQQ",
            listingName: "ProShares UltraPro QQQ",
            name: "ProShares UltraPro QQQ ST0x",
            symbol: "tTQQQ",
            region: Region.US,
            underlyingName: "ProShares UltraPro QQQ",
            isin: ""
        });
        configs[40] = TokenConfig({
            underlying: "FTF",
            ticker: "FTF",
            assetId: "US35472T1016",
            listingTicker: "FTF",
            listingName: "Franklin Limited Duration Income Trust",
            name: "Franklin Limited Duration Income Trust ST0x",
            symbol: "tFTF",
            region: Region.US,
            underlyingName: "Franklin Limited Duration Income Trust",
            isin: ""
        });
        configs[41] = TokenConfig({
            underlying: "CBRS",
            ticker: "CBRS",
            assetId: "US15675D1037",
            listingTicker: "CBRS",
            listingName: "Cerebras Systems Inc.",
            name: "Cerebras Systems Inc. ST0x",
            symbol: "tCBRS",
            region: Region.US,
            underlyingName: "Cerebras Systems Inc.",
            isin: ""
        });
        configs[42] = TokenConfig({
            underlying: "MCD",
            ticker: "MCD",
            assetId: "US5801351017",
            listingTicker: "MCD",
            listingName: "McDonald's Corporation",
            name: "McDonald's Corporation ST0x",
            symbol: "tMCD",
            region: Region.US,
            underlyingName: "McDonald's Corporation",
            isin: ""
        });
        configs[43] = TokenConfig({
            underlying: "NKE",
            ticker: "NKE",
            assetId: "US6541061031",
            listingTicker: "NKE",
            listingName: "NIKE, Inc.",
            name: "NIKE, Inc. ST0x",
            symbol: "tNKE",
            region: Region.US,
            underlyingName: "NIKE, Inc.",
            isin: ""
        });
        configs[44] = TokenConfig({
            underlying: "GRND",
            ticker: "GRND",
            assetId: "US39854F1012",
            listingTicker: "GRND",
            listingName: "Grindr Inc.",
            name: "Grindr Inc. ST0x",
            symbol: "tGRND",
            region: Region.US,
            underlyingName: "Grindr Inc.",
            isin: ""
        });
        configs[45] = TokenConfig({
            underlying: "DNUT",
            ticker: "DNUT",
            assetId: "US50101L1061",
            listingTicker: "DNUT",
            listingName: "Krispy Kreme, Inc.",
            name: "Krispy Kreme, Inc. ST0x",
            symbol: "tDNUT",
            region: Region.US,
            underlyingName: "Krispy Kreme, Inc.",
            isin: ""
        });
        configs[46] = TokenConfig({
            underlying: "PLBY",
            ticker: "PLBY",
            assetId: "US72814P1093",
            listingTicker: "PLBY",
            listingName: "Playboy, Inc.",
            name: "Playboy, Inc. ST0x",
            symbol: "tPLBY",
            region: Region.US,
            underlyingName: "Playboy, Inc.",
            isin: ""
        });
        configs[47] = TokenConfig({
            underlying: "TR",
            ticker: "TR",
            assetId: "US8905161076",
            listingTicker: "TR",
            listingName: "Tootsie Roll Industries, Inc.",
            name: "Tootsie Roll Industries, Inc. ST0x",
            symbol: "tTR",
            region: Region.US,
            underlyingName: "Tootsie Roll Industries, Inc.",
            isin: ""
        });
        configs[48] = TokenConfig({
            underlying: "WEN",
            ticker: "WEN",
            assetId: "US95058W1009",
            listingTicker: "WEN",
            listingName: "The Wendy's Company",
            name: "The Wendy's Company ST0x",
            symbol: "tWEN",
            region: Region.US,
            underlyingName: "The Wendy's Company",
            isin: ""
        });
        configs[49] = TokenConfig({
            underlying: "FGI",
            ticker: "FGI",
            assetId: "",
            listingTicker: "FGI",
            listingName: "FGI Industries Ltd.",
            name: "FGI Industries Ltd. ST0x",
            symbol: "tFGI",
            region: Region.US,
            underlyingName: "FGI Industries Ltd.",
            isin: ""
        });
        // tBIRD — Smartbird, Inc. is the former Allbirds, Inc. (renamed 2026, same
        // Nasdaq listing); name derived the way sft-ops derives it
        // (`"<metadata.name> ST0x"`, `"t<code>"`) from sft-ops `metadata/bird.json`.
        configs[50] = TokenConfig({
            underlying: "BIRD",
            ticker: "BIRD",
            assetId: "US01675A2087",
            listingTicker: "BIRD",
            listingName: "Smartbird, Inc.",
            name: "Smartbird, Inc. ST0x",
            symbol: "tBIRD",
            region: Region.US,
            underlyingName: "Smartbird, Inc.",
            isin: ""
        });
        // tSPY — name derived from sft-ops `metadata/spy.json` the way CD derives it
        // (`"<metadata.name> ST0x"`, `"t<code>"`); verified against the live Base vault.
        configs[51] = TokenConfig({
            underlying: "SPY",
            ticker: "SPY",
            assetId: "US78462F1030",
            listingTicker: "SPY",
            listingName: "State Street SPDR S&P 500 ETF Trust",
            name: "State Street SPDR S&P 500 ETF Trust ST0x",
            symbol: "tSPY",
            region: Region.US,
            underlyingName: "State Street SPDR S&P 500 ETF Trust",
            isin: ""
        });
        // tSNES — name derived from sft-ops `metadata/snes.json` the way CD derives it;
        // verified against the live Base vault.
        configs[52] = TokenConfig({
            underlying: "SNES",
            ticker: "SNES",
            assetId: "US81720R6045",
            listingTicker: "SNES",
            listingName: "SenesTech, Inc.",
            name: "SenesTech, Inc. ST0x",
            symbol: "tSNES",
            region: Region.US,
            underlyingName: "SenesTech, Inc.",
            isin: ""
        });
        // tWMT — name derived from sft-ops `metadata/wmt.json` the way CD derives it;
        // verified against the live Base vault. Ahead of tMC because it reached
        // Base first (sft-ops CD run 37747102500); the tables pair by index.
        configs[53] = TokenConfig({
            underlying: "WMT",
            ticker: "WMT",
            assetId: "US9311421039",
            listingTicker: "WMT",
            listingName: "Walmart Inc.",
            name: "Walmart Inc. ST0x",
            symbol: "tWMT",
            region: Region.US,
            underlyingName: "Walmart Inc.",
            isin: ""
        });
        configs[54] = TokenConfig({
            underlying: "MC",
            ticker: "MC",
            assetId: "FR0000121014",
            listingTicker: "MC",
            listingName: unicode"LVMH Moët Hennessy Louis Vuitton SE",
            name: unicode"LVMH Moët Hennessy Louis Vuitton SE ST0x",
            symbol: "tMC",
            region: Region.EU,
            underlyingName: unicode"LVMH Moët Hennessy Louis Vuitton SE",
            isin: ""
        });
        configs[55] = TokenConfig({
            underlying: "DIS",
            ticker: "DIS",
            assetId: "US2546871060",
            listingTicker: "DIS",
            listingName: "The Walt Disney Company",
            name: "The Walt Disney Company ST0x",
            symbol: "tDIS",
            region: Region.US,
            underlyingName: "The Walt Disney Company",
            isin: ""
        });
        configs[56] = TokenConfig({
            underlying: "IFX",
            ticker: "IFX",
            assetId: "DE0006231004",
            listingTicker: "IFX",
            listingName: "Infineon Technologies AG",
            name: "Infineon Technologies AG ST0x",
            symbol: "tIFX",
            region: Region.EU,
            underlyingName: "Infineon Technologies AG",
            isin: ""
        });
        configs[57] = TokenConfig({
            underlying: "SOI",
            ticker: "SOI",
            assetId: "FR0013227113",
            listingTicker: "SOI",
            listingName: "Soitec SA",
            name: "Soitec SA ST0x",
            symbol: "tSOI",
            region: Region.EU,
            underlyingName: "Soitec SA",
            isin: ""
        });
        configs[58] = TokenConfig({
            underlying: "TPRO",
            ticker: "TPRO",
            assetId: "IT0005482333",
            listingTicker: "TPRO",
            listingName: "Technoprobe S.p.A.",
            name: "Technoprobe S.p.A. ST0x",
            symbol: "tTPRO",
            region: Region.EU,
            underlyingName: "Technoprobe S.p.A.",
            isin: ""
        });
    }

    function testTokenConfigs() internal pure returns (TokenConfig[] memory) {
        TokenConfig[] memory configs = new TokenConfig[](2);
        configs[0] = TokenConfig({
            underlying: "USTEST",
            ticker: "USTEST",
            assetId: "US78462F1030",
            listingTicker: "USTEST",
            listingName: "US Test",
            name: "US Test ST0x",
            symbol: "tUSTEST",
            region: Region.US,
            underlyingName: "",
            isin: ""
        });
        configs[1] = TokenConfig({
            underlying: "EUTEST",
            ticker: "EUTEST",
            assetId: "US78462F1030",
            listingTicker: "EUTEST",
            listingName: "EU Test",
            name: "EU Test ST0x",
            symbol: "tEUTEST",
            region: Region.EU,
            underlyingName: "",
            isin: ""
        });
        return configs;
    }

    /// @notice The production row for `underlying`.
    /// @param underlying The ticker join key.
    /// @return The row. Reverts `UnknownUnderlying` when there is none.
    function configOf(string memory underlying) internal pure returns (TokenConfig memory) {
        TokenConfig[] memory configs = productionTokenConfigs();
        for (uint256 rowIndex = 0; rowIndex < configs.length; rowIndex++) {
            if (keccak256(bytes(configs[rowIndex].underlying)) == keccak256(bytes(underlying))) {
                return configs[rowIndex];
            }
        }
        revert UnknownUnderlying(underlying);
    }

    /// @notice The region of the production row for `underlying`.
    /// @param underlying The ticker join key.
    /// @return The row's region. Reverts `UnknownUnderlying` when there is
    /// none.
    function regionOf(string memory underlying) internal pure returns (Region) {
        return configOf(underlying).region;
    }
}

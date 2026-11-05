// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @notice The deploy-time configuration for one production token.
/// @dev `name` and `symbol` are the Base parity baseline: the receipt
/// vault's ERC-20 `name()` / `symbol()` captured verbatim from the live Base
/// token, which the cross-chain parity pin asserts every chain against, and
/// the input the rename table reads. They are NOT V6 deploy inputs. A V6
/// token (one deployed through `LibProdTokenTargets`) is initialized with an
/// empty name and symbol and with `assetId` in its init metadata, so its
/// address depends only on `assetId`, `region`, the authority and the beacon
/// names; the vault reverts on any other init. A V6 token reports an empty
/// `name()` / `symbol()` until its owner, the governance timelock, runs the
/// first `setUnderlying`.
///
/// The underlying ticker and name are not deploy inputs either: the vault
/// owner sets them after deployment with `IStoxUnderlyingV1.setUnderlying`.
/// The ticker is this table's `underlying` key (every row's `symbol` is
/// `"t" + underlying`) and the name is `underlyingName`. Once both are set,
/// the receipt vault reports `"t" + ticker` / `underlyingName + " (ST0x)"`
/// and the wrapped token vault `ticker + "s"` / the receipt vault's name.
/// Until then a live (pre-V6) receipt vault reports the `name` + `symbol` it
/// was initialized with, and the wrapped token vault `"Wrapped " + name` /
/// `"w" + symbol`.
///
/// A released row's `symbol` never changes in this table: renames happen
/// on-chain only. The V6 token suite key is derived from `symbol`, and a
/// released suite key is frozen (`LibProdTokenConfigAssetIdTest` pins the released
/// keys).
/// @param underlying The chain-agnostic ticker join key, matching
/// `LibTokenInvariants.TokenInstance.underlying`.
/// @param name The receipt vault's ERC-20 `name()`, verbatim from Base.
/// @param symbol The receipt vault's ERC-20 `symbol()`, verbatim from Base.
/// @param region Where the underlying is listed.
/// @param underlyingName The issuer's current legal name, without any ST0x
/// suffix: the `name` argument of `setUnderlying`. Usually the live `name`
/// without " ST0x"; it differs where the issuer has since been renamed
/// (MSTR, RKLB).
/// @param assetId The identifier of the asset, fixed at listing time: the
/// ISIN of the exact share line the token tracks and hedges where one exists.
/// It never follows later ISIN changes. It is unique per (`assetId`,
/// `region`). A row gets a V6 token suite if and only if its `assetId` is
/// non-empty (`LibProdTokenConfig.v6TokenConfigs`). After deploy, the token's
/// on-chain `IStoxAssetIdV1.assetId()` returns it.
struct TokenConfig {
    string underlying;
    string name;
    string symbol;
    Region region;
    string underlyingName;
    string assetId;
}

enum Region {
    US,
    EU
}

/// @notice The underlying has no row in the production token table.
error UnknownUnderlying(string underlying);

/// @title LibProdTokenConfig
/// @notice The canonical name/symbol table for the ST0x production
/// tokens, captured verbatim from the live Base receipt vaults. It is the
/// companion to `LibTokenInvariants` (which holds the deployed addresses) and
/// the CANONICAL BASELINE the cross-chain parity pin asserts every chain's
/// live `name`/`symbol` against (Base included — `LibProdTokenConfigTest` pins
/// this table to live Base, so the baseline itself is validated, not just
/// chain-vs-chain). V6 rows deploy nameless through `LibProdTokenTargets`; see
/// `TokenConfig`.
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
            name: "MicroStrategy Incorporated ST0x",
            symbol: "tMSTR",
            region: Region.US,
            underlyingName: "Strategy Inc",
            assetId: ""
        });
        configs[1] = TokenConfig({
            underlying: "TSLA",
            name: "Tesla Inc ST0x",
            symbol: "tTSLA",
            region: Region.US,
            underlyingName: "Tesla Inc",
            assetId: ""
        });
        configs[2] = TokenConfig({
            underlying: "COIN",
            name: "Coinbase Global Inc ST0x",
            symbol: "tCOIN",
            region: Region.US,
            underlyingName: "Coinbase Global Inc",
            assetId: ""
        });
        configs[3] = TokenConfig({
            underlying: "SPYM",
            name: "State Street SPDR Portfolio S&P 500 ETF ST0x",
            symbol: "tSPYM",
            region: Region.US,
            underlyingName: "State Street SPDR Portfolio S&P 500 ETF",
            assetId: ""
        });
        configs[4] = TokenConfig({
            underlying: "SIVR",
            name: "abrdn Physical Silver Shares ETF ST0x",
            symbol: "tSIVR",
            region: Region.US,
            underlyingName: "abrdn Physical Silver Shares ETF",
            assetId: ""
        });
        configs[5] = TokenConfig({
            underlying: "CRCL",
            name: "Circle Internet Group Inc ST0x",
            symbol: "tCRCL",
            region: Region.US,
            underlyingName: "Circle Internet Group Inc",
            assetId: ""
        });
        configs[6] = TokenConfig({
            underlying: "NVDA",
            name: "NVIDIA Corporation ST0x",
            symbol: "tNVDA",
            region: Region.US,
            underlyingName: "NVIDIA Corporation",
            assetId: ""
        });
        configs[7] = TokenConfig({
            underlying: "IAU",
            name: "iShares Gold Trust ST0x",
            symbol: "tIAU",
            region: Region.US,
            underlyingName: "iShares Gold Trust",
            assetId: ""
        });
        configs[8] = TokenConfig({
            underlying: "PPLT",
            name: "abrdn Physical Platinum Shares ETF ST0x",
            symbol: "tPPLT",
            region: Region.US,
            underlyingName: "abrdn Physical Platinum Shares ETF",
            assetId: ""
        });
        configs[9] = TokenConfig({
            underlying: "AMZN",
            name: "Amazon.com Inc ST0x",
            symbol: "tAMZN",
            region: Region.US,
            underlyingName: "Amazon.com Inc",
            assetId: ""
        });
        configs[10] = TokenConfig({
            underlying: "BMNR",
            name: "Bitmine Immersion Technologies, Inc ST0x",
            symbol: "tBMNR",
            region: Region.US,
            underlyingName: "Bitmine Immersion Technologies, Inc",
            assetId: ""
        });
        configs[11] = TokenConfig({
            underlying: "IBHG",
            name: "iShares iBonds 2027 Term High Yield and Income ETF ST0x",
            symbol: "tIBHG",
            region: Region.US,
            underlyingName: "iShares iBonds 2027 Term High Yield and Income ETF",
            assetId: ""
        });
        // NB: leading space is present on Base and is reproduced verbatim.
        configs[12] = TokenConfig({
            underlying: "SGOV",
            name: " iShares 0-3 Month Treasury Bond ETF ST0x",
            symbol: "tSGOV",
            region: Region.US,
            underlyingName: "iShares 0-3 Month Treasury Bond ETF",
            assetId: ""
        });
        configs[13] = TokenConfig({
            underlying: "QQQM",
            name: "Invesco NASDAQ 100 ETF ST0x",
            symbol: "tQQQM",
            region: Region.US,
            underlyingName: "Invesco NASDAQ 100 ETF",
            assetId: ""
        });
        configs[14] = TokenConfig({
            underlying: "VWO",
            name: "Vanguard Emerging Markets Stock Index Fund ST0x",
            symbol: "tVWO",
            region: Region.US,
            underlyingName: "Vanguard Emerging Markets Stock Index Fund",
            assetId: ""
        });
        configs[15] = TokenConfig({
            underlying: "ARKK",
            name: "ARK Innovation ETF ST0x",
            symbol: "tARKK",
            region: Region.US,
            underlyingName: "ARK Innovation ETF",
            assetId: ""
        });
        configs[16] = TokenConfig({
            underlying: "SPCX",
            name: "Space Exploration Technologies Corp. ST0x",
            symbol: "tSPCX",
            region: Region.US,
            underlyingName: "Space Exploration Technologies Corp.",
            assetId: ""
        });
        configs[17] = TokenConfig({
            underlying: "CEG",
            name: "Constellation Energy Corporation ST0x",
            symbol: "tCEG",
            region: Region.US,
            underlyingName: "Constellation Energy Corporation",
            assetId: ""
        });
        configs[18] = TokenConfig({
            underlying: "DRAM",
            name: "Roundhill Memory ETF ST0x",
            symbol: "tDRAM",
            region: Region.US,
            underlyingName: "Roundhill Memory ETF",
            assetId: ""
        });
        configs[19] = TokenConfig({
            underlying: "TSM",
            name: "Taiwan Semiconductor Manufacturing Company Limited ADR ST0x",
            symbol: "tTSM",
            region: Region.US,
            underlyingName: "Taiwan Semiconductor Manufacturing Company Limited ADR",
            assetId: ""
        });
        configs[20] = TokenConfig({
            underlying: "SKHY",
            name: "SK hynix Inc. ADR ST0x",
            symbol: "tSKHY",
            region: Region.US,
            underlyingName: "SK hynix Inc. ADR",
            assetId: ""
        });
        configs[21] = TokenConfig({
            underlying: "ASML",
            name: "ASML Holding N.V. ST0x",
            symbol: "tASML",
            region: Region.US,
            underlyingName: "ASML Holding N.V.",
            assetId: ""
        });
        configs[22] = TokenConfig({
            underlying: "MU",
            name: "Micron Technology, Inc. ST0x",
            symbol: "tMU",
            region: Region.US,
            underlyingName: "Micron Technology, Inc.",
            assetId: ""
        });
        configs[23] = TokenConfig({
            underlying: "AMD",
            name: "Advanced Micro Devices, Inc. ST0x",
            symbol: "tAMD",
            region: Region.US,
            underlyingName: "Advanced Micro Devices, Inc.",
            assetId: ""
        });
        configs[24] = TokenConfig({
            underlying: "AVGO",
            name: "Broadcom Inc. ST0x",
            symbol: "tAVGO",
            region: Region.US,
            underlyingName: "Broadcom Inc.",
            assetId: ""
        });
        configs[25] = TokenConfig({
            underlying: "AMAT",
            name: "Applied Materials, Inc. ST0x",
            symbol: "tAMAT",
            region: Region.US,
            underlyingName: "Applied Materials, Inc.",
            assetId: ""
        });
        configs[26] = TokenConfig({
            underlying: "LRCX",
            name: "Lam Research Corporation ST0x",
            symbol: "tLRCX",
            region: Region.US,
            underlyingName: "Lam Research Corporation",
            assetId: ""
        });
        configs[27] = TokenConfig({
            underlying: "TTWO",
            name: "Take-Two Interactive Software, Inc. ST0x",
            symbol: "tTTWO",
            region: Region.US,
            underlyingName: "Take-Two Interactive Software, Inc.",
            assetId: ""
        });
        configs[28] = TokenConfig({
            underlying: "RKLB",
            name: "Rocket Lab USA Inc ST0x",
            symbol: "tRKLB",
            region: Region.US,
            underlyingName: "Rocket Lab Corporation",
            assetId: ""
        });
        configs[29] = TokenConfig({
            underlying: "GOOGL",
            name: "Alphabet Inc. Class A ST0x",
            symbol: "tGOOGL",
            region: Region.US,
            underlyingName: "Alphabet Inc. Class A",
            assetId: ""
        });
        configs[30] = TokenConfig({
            underlying: "AAPL",
            name: "Apple Inc. ST0x",
            symbol: "tAAPL",
            region: Region.US,
            underlyingName: "Apple Inc.",
            assetId: ""
        });
        configs[31] = TokenConfig({
            underlying: "MSFT",
            name: "Microsoft Corporation ST0x",
            symbol: "tMSFT",
            region: Region.US,
            underlyingName: "Microsoft Corporation",
            assetId: ""
        });
        configs[32] = TokenConfig({
            underlying: "LLY",
            name: "Eli Lilly and Company ST0x",
            symbol: "tLLY",
            region: Region.US,
            underlyingName: "Eli Lilly and Company",
            assetId: ""
        });
        configs[33] = TokenConfig({
            underlying: "PTY",
            name: "PIMCO Corporate & Income Opportunity Fund ST0x",
            symbol: "tPTY",
            region: Region.US,
            underlyingName: "PIMCO Corporate & Income Opportunity Fund",
            assetId: ""
        });
        configs[34] = TokenConfig({
            underlying: "INTC",
            name: "Intel Corporation ST0x",
            symbol: "tINTC",
            region: Region.US,
            underlyingName: "Intel Corporation",
            assetId: ""
        });
        configs[35] = TokenConfig({
            underlying: "HOOD",
            name: "Robinhood Markets, Inc. ST0x",
            symbol: "tHOOD",
            region: Region.US,
            underlyingName: "Robinhood Markets, Inc.",
            assetId: ""
        });
        configs[36] = TokenConfig({
            underlying: "ORCL",
            name: "Oracle Corporation ST0x",
            symbol: "tORCL",
            region: Region.US,
            underlyingName: "Oracle Corporation",
            assetId: ""
        });
        configs[37] = TokenConfig({
            underlying: "SMCI",
            name: "Super Micro Computer, Inc. ST0x",
            symbol: "tSMCI",
            region: Region.US,
            underlyingName: "Super Micro Computer, Inc.",
            assetId: ""
        });
        configs[38] = TokenConfig({
            underlying: "BABA",
            name: "Alibaba Group Holding Limited ADR ST0x",
            symbol: "tBABA",
            region: Region.US,
            underlyingName: "Alibaba Group Holding Limited ADR",
            assetId: ""
        });
        configs[39] = TokenConfig({
            underlying: "TQQQ",
            name: "ProShares UltraPro QQQ ST0x",
            symbol: "tTQQQ",
            region: Region.US,
            underlyingName: "ProShares UltraPro QQQ",
            assetId: ""
        });
        configs[40] = TokenConfig({
            underlying: "FTF",
            name: "Franklin Limited Duration Income Trust ST0x",
            symbol: "tFTF",
            region: Region.US,
            underlyingName: "Franklin Limited Duration Income Trust",
            assetId: ""
        });
        configs[41] = TokenConfig({
            underlying: "CBRS",
            name: "Cerebras Systems Inc. ST0x",
            symbol: "tCBRS",
            region: Region.US,
            underlyingName: "Cerebras Systems Inc.",
            assetId: ""
        });
        configs[42] = TokenConfig({
            underlying: "MCD",
            name: "McDonald's Corporation ST0x",
            symbol: "tMCD",
            region: Region.US,
            underlyingName: "McDonald's Corporation",
            assetId: ""
        });
        configs[43] = TokenConfig({
            underlying: "NKE",
            name: "NIKE, Inc. ST0x",
            symbol: "tNKE",
            region: Region.US,
            underlyingName: "NIKE, Inc.",
            assetId: ""
        });
        configs[44] = TokenConfig({
            underlying: "GRND",
            name: "Grindr Inc. ST0x",
            symbol: "tGRND",
            region: Region.US,
            underlyingName: "Grindr Inc.",
            assetId: ""
        });
        configs[45] = TokenConfig({
            underlying: "DNUT",
            name: "Krispy Kreme, Inc. ST0x",
            symbol: "tDNUT",
            region: Region.US,
            underlyingName: "Krispy Kreme, Inc.",
            assetId: ""
        });
        configs[46] = TokenConfig({
            underlying: "PLBY",
            name: "Playboy, Inc. ST0x",
            symbol: "tPLBY",
            region: Region.US,
            underlyingName: "Playboy, Inc.",
            assetId: ""
        });
        configs[47] = TokenConfig({
            underlying: "TR",
            name: "Tootsie Roll Industries, Inc. ST0x",
            symbol: "tTR",
            region: Region.US,
            underlyingName: "Tootsie Roll Industries, Inc.",
            assetId: ""
        });
        configs[48] = TokenConfig({
            underlying: "WEN",
            name: "The Wendy's Company ST0x",
            symbol: "tWEN",
            region: Region.US,
            underlyingName: "The Wendy's Company",
            assetId: ""
        });
        configs[49] = TokenConfig({
            underlying: "FGI",
            name: "FGI Industries Ltd. ST0x",
            symbol: "tFGI",
            region: Region.US,
            underlyingName: "FGI Industries Ltd.",
            assetId: ""
        });
        // tBIRD — Smartbird, Inc. is the former Allbirds, Inc. (renamed 2026, same
        // Nasdaq listing); name derived the way sft-ops derives it
        // (`"<metadata.name> ST0x"`, `"t<code>"`) from sft-ops `metadata/bird.json`.
        configs[50] = TokenConfig({
            underlying: "BIRD",
            name: "Smartbird, Inc. ST0x",
            symbol: "tBIRD",
            region: Region.US,
            underlyingName: "Smartbird, Inc.",
            assetId: ""
        });
        // tSPY — name derived from sft-ops `metadata/spy.json` the way CD derives it
        // (`"<metadata.name> ST0x"`, `"t<code>"`); verified against the live Base vault.
        configs[51] = TokenConfig({
            underlying: "SPY",
            name: "State Street SPDR S&P 500 ETF Trust ST0x",
            symbol: "tSPY",
            region: Region.US,
            underlyingName: "State Street SPDR S&P 500 ETF Trust",
            assetId: ""
        });
        // tSNES — name derived from sft-ops `metadata/snes.json` the way CD derives it;
        // verified against the live Base vault.
        configs[52] = TokenConfig({
            underlying: "SNES",
            name: "SenesTech, Inc. ST0x",
            symbol: "tSNES",
            region: Region.US,
            underlyingName: "SenesTech, Inc.",
            assetId: ""
        });
        // tWMT — name derived from sft-ops `metadata/wmt.json` the way CD derives it;
        // verified against the live Base vault. Ahead of tMC because it reached
        // Base first (sft-ops CD run 37747102500); the tables pair by index.
        configs[53] = TokenConfig({
            underlying: "WMT",
            name: "Walmart Inc. ST0x",
            symbol: "tWMT",
            region: Region.US,
            underlyingName: "Walmart Inc.",
            assetId: ""
        });
        configs[54] = TokenConfig({
            underlying: "MC",
            name: unicode"LVMH Moët Hennessy Louis Vuitton SE ST0x",
            symbol: "tMC",
            region: Region.EU,
            underlyingName: unicode"LVMH Moët Hennessy Louis Vuitton SE",
            assetId: ""
        });
        configs[55] = TokenConfig({
            underlying: "DIS",
            name: "The Walt Disney Company ST0x",
            symbol: "tDIS",
            region: Region.US,
            underlyingName: "The Walt Disney Company",
            assetId: ""
        });
        configs[56] = TokenConfig({
            underlying: "IFX",
            name: "Infineon Technologies AG ST0x",
            symbol: "tIFX",
            region: Region.EU,
            underlyingName: "Infineon Technologies AG",
            assetId: ""
        });
        configs[57] = TokenConfig({
            underlying: "SOI",
            name: "Soitec SA ST0x",
            symbol: "tSOI",
            region: Region.EU,
            underlyingName: "Soitec SA",
            assetId: ""
        });
        configs[58] = TokenConfig({
            underlying: "TPRO",
            name: "Technoprobe S.p.A. ST0x",
            symbol: "tTPRO",
            region: Region.EU,
            underlyingName: "Technoprobe S.p.A.",
            assetId: ""
        });
    }

    /// @notice The rows of `configs` with a non-empty `assetId`, in order.
    /// This is the one rule for which rows get a V6 token suite.
    /// @param configs The rows.
    /// @return filtered The rows with a non-empty `assetId`.
    function withAssetId(TokenConfig[] memory configs) internal pure returns (TokenConfig[] memory filtered) {
        filtered = new TokenConfig[](configs.length);
        uint256 count = 0;
        for (uint256 i = 0; i < configs.length; i++) {
            if (bytes(configs[i].assetId).length != 0) {
                filtered[count++] = configs[i];
            }
        }
        assembly ("memory-safe") {
            mstore(filtered, count)
        }
    }

    /// @notice The production rows that get a V6 token suite: those with a
    /// non-empty `assetId`, in table order. Empty until production asset ids
    /// are chosen.
    /// @return The rows.
    function v6TokenConfigs() internal pure returns (TokenConfig[] memory) {
        return withAssetId(productionTokenConfigs());
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

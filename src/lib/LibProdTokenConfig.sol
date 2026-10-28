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
/// The underlying ticker and name are not deploy inputs: the vault owner sets
/// them after deployment with `IStoxUnderlyingV1.setUnderlying`. The ticker
/// is this table's `underlying` key (every row's `symbol` is
/// `"t" + underlying`) and the name is `underlyingName`. Once both are set,
/// the receipt vault reports `"t" + ticker` / `underlyingName + " (ST0x)"`
/// and the wrapped token vault `ticker + "s"` / the receipt vault's name.
/// Until then the receipt vault reports the `name` + `symbol` it was
/// initialized with, and the wrapped token vault `"Wrapped " + name` /
/// `"w" + symbol`.
/// @param underlying The chain-agnostic ticker join key, matching
/// `LibTokenInvariants.TokenInstance.underlying`.
/// @param name The receipt vault's ERC-20 `name()`, verbatim from Base.
/// @param symbol The receipt vault's ERC-20 `symbol()`, verbatim from Base.
/// @param region Where the underlying is listed.
/// @param underlyingName The issuer's current legal name, without any ST0x
/// suffix: the `name` argument of `setUnderlying`. Usually the live `name`
/// without " ST0x"; it differs where the issuer has since been renamed
/// (MSTR, RKLB).
struct TokenConfig {
    string underlying;
    string name;
    string symbol;
    Region region;
    string underlyingName;
}

enum Region {
    US,
    EU
}

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
        configs = new TokenConfig[](56);
        configs[0] = TokenConfig({
            underlying: "MSTR",
            name: "MicroStrategy Incorporated ST0x",
            symbol: "tMSTR",
            region: Region.US,
            underlyingName: "Strategy Inc"
        });
        configs[1] = TokenConfig({
            underlying: "TSLA", name: "Tesla Inc ST0x", symbol: "tTSLA", region: Region.US, underlyingName: "Tesla Inc"
        });
        configs[2] = TokenConfig({
            underlying: "COIN",
            name: "Coinbase Global Inc ST0x",
            symbol: "tCOIN",
            region: Region.US,
            underlyingName: "Coinbase Global Inc"
        });
        configs[3] = TokenConfig({
            underlying: "SPYM",
            name: "State Street SPDR Portfolio S&P 500 ETF ST0x",
            symbol: "tSPYM",
            region: Region.US,
            underlyingName: "State Street SPDR Portfolio S&P 500 ETF"
        });
        configs[4] = TokenConfig({
            underlying: "SIVR",
            name: "abrdn Physical Silver Shares ETF ST0x",
            symbol: "tSIVR",
            region: Region.US,
            underlyingName: "abrdn Physical Silver Shares ETF"
        });
        configs[5] = TokenConfig({
            underlying: "CRCL",
            name: "Circle Internet Group Inc ST0x",
            symbol: "tCRCL",
            region: Region.US,
            underlyingName: "Circle Internet Group Inc"
        });
        configs[6] = TokenConfig({
            underlying: "NVDA",
            name: "NVIDIA Corporation ST0x",
            symbol: "tNVDA",
            region: Region.US,
            underlyingName: "NVIDIA Corporation"
        });
        configs[7] = TokenConfig({
            underlying: "IAU",
            name: "iShares Gold Trust ST0x",
            symbol: "tIAU",
            region: Region.US,
            underlyingName: "iShares Gold Trust"
        });
        configs[8] = TokenConfig({
            underlying: "PPLT",
            name: "abrdn Physical Platinum Shares ETF ST0x",
            symbol: "tPPLT",
            region: Region.US,
            underlyingName: "abrdn Physical Platinum Shares ETF"
        });
        configs[9] = TokenConfig({
            underlying: "AMZN",
            name: "Amazon.com Inc ST0x",
            symbol: "tAMZN",
            region: Region.US,
            underlyingName: "Amazon.com Inc"
        });
        configs[10] = TokenConfig({
            underlying: "BMNR",
            name: "Bitmine Immersion Technologies, Inc ST0x",
            symbol: "tBMNR",
            region: Region.US,
            underlyingName: "Bitmine Immersion Technologies, Inc"
        });
        configs[11] = TokenConfig({
            underlying: "IBHG",
            name: "iShares iBonds 2027 Term High Yield and Income ETF ST0x",
            symbol: "tIBHG",
            region: Region.US,
            underlyingName: "iShares iBonds 2027 Term High Yield and Income ETF"
        });
        // NB: leading space is present on Base and is reproduced verbatim.
        configs[12] = TokenConfig({
            underlying: "SGOV",
            name: " iShares 0-3 Month Treasury Bond ETF ST0x",
            symbol: "tSGOV",
            region: Region.US,
            underlyingName: "iShares 0-3 Month Treasury Bond ETF"
        });
        configs[13] = TokenConfig({
            underlying: "QQQM",
            name: "Invesco NASDAQ 100 ETF ST0x",
            symbol: "tQQQM",
            region: Region.US,
            underlyingName: "Invesco NASDAQ 100 ETF"
        });
        configs[14] = TokenConfig({
            underlying: "VWO",
            name: "Vanguard Emerging Markets Stock Index Fund ST0x",
            symbol: "tVWO",
            region: Region.US,
            underlyingName: "Vanguard Emerging Markets Stock Index Fund"
        });
        configs[15] = TokenConfig({
            underlying: "ARKK",
            name: "ARK Innovation ETF ST0x",
            symbol: "tARKK",
            region: Region.US,
            underlyingName: "ARK Innovation ETF"
        });
        configs[16] = TokenConfig({
            underlying: "SPCX",
            name: "Space Exploration Technologies Corp. ST0x",
            symbol: "tSPCX",
            region: Region.US,
            underlyingName: "Space Exploration Technologies Corp."
        });
        configs[17] = TokenConfig({
            underlying: "CEG",
            name: "Constellation Energy Corporation ST0x",
            symbol: "tCEG",
            region: Region.US,
            underlyingName: "Constellation Energy Corporation"
        });
        configs[18] = TokenConfig({
            underlying: "DRAM",
            name: "Roundhill Memory ETF ST0x",
            symbol: "tDRAM",
            region: Region.US,
            underlyingName: "Roundhill Memory ETF"
        });
        configs[19] = TokenConfig({
            underlying: "TSM",
            name: "Taiwan Semiconductor Manufacturing Company Limited ADR ST0x",
            symbol: "tTSM",
            region: Region.US,
            underlyingName: "Taiwan Semiconductor Manufacturing Company Limited ADR"
        });
        configs[20] = TokenConfig({
            underlying: "SKHY",
            name: "SK hynix Inc. ADR ST0x",
            symbol: "tSKHY",
            region: Region.US,
            underlyingName: "SK hynix Inc. ADR"
        });
        configs[21] = TokenConfig({
            underlying: "ASML",
            name: "ASML Holding N.V. ST0x",
            symbol: "tASML",
            region: Region.US,
            underlyingName: "ASML Holding N.V."
        });
        configs[22] = TokenConfig({
            underlying: "MU",
            name: "Micron Technology, Inc. ST0x",
            symbol: "tMU",
            region: Region.US,
            underlyingName: "Micron Technology, Inc."
        });
        configs[23] = TokenConfig({
            underlying: "AMD",
            name: "Advanced Micro Devices, Inc. ST0x",
            symbol: "tAMD",
            region: Region.US,
            underlyingName: "Advanced Micro Devices, Inc."
        });
        configs[24] = TokenConfig({
            underlying: "AVGO",
            name: "Broadcom Inc. ST0x",
            symbol: "tAVGO",
            region: Region.US,
            underlyingName: "Broadcom Inc."
        });
        configs[25] = TokenConfig({
            underlying: "AMAT",
            name: "Applied Materials, Inc. ST0x",
            symbol: "tAMAT",
            region: Region.US,
            underlyingName: "Applied Materials, Inc."
        });
        configs[26] = TokenConfig({
            underlying: "LRCX",
            name: "Lam Research Corporation ST0x",
            symbol: "tLRCX",
            region: Region.US,
            underlyingName: "Lam Research Corporation"
        });
        configs[27] = TokenConfig({
            underlying: "TTWO",
            name: "Take-Two Interactive Software, Inc. ST0x",
            symbol: "tTTWO",
            region: Region.US,
            underlyingName: "Take-Two Interactive Software, Inc."
        });
        configs[28] = TokenConfig({
            underlying: "RKLB",
            name: "Rocket Lab USA Inc ST0x",
            symbol: "tRKLB",
            region: Region.US,
            underlyingName: "Rocket Lab Corporation"
        });
        configs[29] = TokenConfig({
            underlying: "GOOGL",
            name: "Alphabet Inc. Class A ST0x",
            symbol: "tGOOGL",
            region: Region.US,
            underlyingName: "Alphabet Inc. Class A"
        });
        configs[30] = TokenConfig({
            underlying: "AAPL",
            name: "Apple Inc. ST0x",
            symbol: "tAAPL",
            region: Region.US,
            underlyingName: "Apple Inc."
        });
        configs[31] = TokenConfig({
            underlying: "MSFT",
            name: "Microsoft Corporation ST0x",
            symbol: "tMSFT",
            region: Region.US,
            underlyingName: "Microsoft Corporation"
        });
        configs[32] = TokenConfig({
            underlying: "LLY",
            name: "Eli Lilly and Company ST0x",
            symbol: "tLLY",
            region: Region.US,
            underlyingName: "Eli Lilly and Company"
        });
        configs[33] = TokenConfig({
            underlying: "PTY",
            name: "PIMCO Corporate & Income Opportunity Fund ST0x",
            symbol: "tPTY",
            region: Region.US,
            underlyingName: "PIMCO Corporate & Income Opportunity Fund"
        });
        configs[34] = TokenConfig({
            underlying: "INTC",
            name: "Intel Corporation ST0x",
            symbol: "tINTC",
            region: Region.US,
            underlyingName: "Intel Corporation"
        });
        configs[35] = TokenConfig({
            underlying: "HOOD",
            name: "Robinhood Markets, Inc. ST0x",
            symbol: "tHOOD",
            region: Region.US,
            underlyingName: "Robinhood Markets, Inc."
        });
        configs[36] = TokenConfig({
            underlying: "ORCL",
            name: "Oracle Corporation ST0x",
            symbol: "tORCL",
            region: Region.US,
            underlyingName: "Oracle Corporation"
        });
        configs[37] = TokenConfig({
            underlying: "SMCI",
            name: "Super Micro Computer, Inc. ST0x",
            symbol: "tSMCI",
            region: Region.US,
            underlyingName: "Super Micro Computer, Inc."
        });
        configs[38] = TokenConfig({
            underlying: "BABA",
            name: "Alibaba Group Holding Limited ADR ST0x",
            symbol: "tBABA",
            region: Region.US,
            underlyingName: "Alibaba Group Holding Limited ADR"
        });
        configs[39] = TokenConfig({
            underlying: "TQQQ",
            name: "ProShares UltraPro QQQ ST0x",
            symbol: "tTQQQ",
            region: Region.US,
            underlyingName: "ProShares UltraPro QQQ"
        });
        configs[40] = TokenConfig({
            underlying: "FTF",
            name: "Franklin Limited Duration Income Trust ST0x",
            symbol: "tFTF",
            region: Region.US,
            underlyingName: "Franklin Limited Duration Income Trust"
        });
        configs[41] = TokenConfig({
            underlying: "CBRS",
            name: "Cerebras Systems Inc. ST0x",
            symbol: "tCBRS",
            region: Region.US,
            underlyingName: "Cerebras Systems Inc."
        });
        configs[42] = TokenConfig({
            underlying: "MCD",
            name: "McDonald's Corporation ST0x",
            symbol: "tMCD",
            region: Region.US,
            underlyingName: "McDonald's Corporation"
        });
        configs[43] = TokenConfig({
            underlying: "NKE", name: "NIKE, Inc. ST0x", symbol: "tNKE", region: Region.US, underlyingName: "NIKE, Inc."
        });
        configs[44] = TokenConfig({
            underlying: "GRND",
            name: "Grindr Inc. ST0x",
            symbol: "tGRND",
            region: Region.US,
            underlyingName: "Grindr Inc."
        });
        configs[45] = TokenConfig({
            underlying: "DNUT",
            name: "Krispy Kreme, Inc. ST0x",
            symbol: "tDNUT",
            region: Region.US,
            underlyingName: "Krispy Kreme, Inc."
        });
        configs[46] = TokenConfig({
            underlying: "PLBY",
            name: "Playboy, Inc. ST0x",
            symbol: "tPLBY",
            region: Region.US,
            underlyingName: "Playboy, Inc."
        });
        configs[47] = TokenConfig({
            underlying: "TR",
            name: "Tootsie Roll Industries, Inc. ST0x",
            symbol: "tTR",
            region: Region.US,
            underlyingName: "Tootsie Roll Industries, Inc."
        });
        configs[48] = TokenConfig({
            underlying: "WEN",
            name: "The Wendy's Company ST0x",
            symbol: "tWEN",
            region: Region.US,
            underlyingName: "The Wendy's Company"
        });
        configs[49] = TokenConfig({
            underlying: "FGI",
            name: "FGI Industries Ltd. ST0x",
            symbol: "tFGI",
            region: Region.US,
            underlyingName: "FGI Industries Ltd."
        });
        // tBIRD — Smartbird, Inc. is the former Allbirds, Inc. (renamed 2026, same
        // Nasdaq listing); name derived the way sft-ops derives it
        // (`"<metadata.name> ST0x"`, `"t<code>"`) from sft-ops `metadata/bird.json`.
        configs[50] = TokenConfig({
            underlying: "BIRD",
            name: "Smartbird, Inc. ST0x",
            symbol: "tBIRD",
            region: Region.US,
            underlyingName: "Smartbird, Inc."
        });
        // tSPY — name derived from sft-ops `metadata/spy.json` the way CD derives it
        // (`"<metadata.name> ST0x"`, `"t<code>"`); verified against the live Base vault.
        configs[51] = TokenConfig({
            underlying: "SPY",
            name: "State Street SPDR S&P 500 ETF Trust ST0x",
            symbol: "tSPY",
            region: Region.US,
            underlyingName: "State Street SPDR S&P 500 ETF Trust"
        });
        // tSNES — name derived from sft-ops `metadata/snes.json` the way CD derives it;
        // verified against the live Base vault.
        configs[52] = TokenConfig({
            underlying: "SNES",
            name: "SenesTech, Inc. ST0x",
            symbol: "tSNES",
            region: Region.US,
            underlyingName: "SenesTech, Inc."
        });
        // tWMT — name derived from sft-ops `metadata/wmt.json` the way CD derives it;
        // verified against the live Base vault. Ahead of tMC because it reached
        // Base first (sft-ops CD run 37747102500); the tables pair by index.
        configs[53] = TokenConfig({
            underlying: "WMT",
            name: "Walmart Inc. ST0x",
            symbol: "tWMT",
            region: Region.US,
            underlyingName: "Walmart Inc."
        });
        configs[54] = TokenConfig({
            underlying: "MC",
            name: unicode"LVMH Moët Hennessy Louis Vuitton SE ST0x",
            symbol: "tMC",
            region: Region.EU,
            underlyingName: unicode"LVMH Moët Hennessy Louis Vuitton SE"
        });
        configs[55] = TokenConfig({
            underlying: "DIS",
            name: "The Walt Disney Company ST0x",
            symbol: "tDIS",
            region: Region.US,
            underlyingName: "The Walt Disney Company"
        });
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

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @notice The deploy-time configuration for one production token — the
/// inputs `StoxUnifiedDeployer.newTokenAndWrapperVault` needs to reproduce
/// a Base token instance on another chain.
/// @dev Only `name` + `symbol` are captured: the offchain-asset receipt
/// vault takes `asset = address(0)` (the asset is offchain) and
/// `receipt = address(0)` (the beacon-set deployer wires the receipt),
/// `initialAdmin` is the target chain's Safe (supplied by the deploy
/// script, not the table), `decimals` is fixed by the shared vault
/// implementation bytecode, and the wrapped token vault derives its own
/// name/symbol on-chain (`"Wrapped " + name`, `"w" + symbol`). So the
/// receipt vault's `name` + `symbol` are the ONLY free deploy inputs.
/// @param underlying The chain-agnostic ticker join key, matching
/// `LibTokenInvariants.TokenInstance.underlying`.
/// @param name The receipt vault's ERC-20 `name()`, verbatim from Base.
/// @param symbol The receipt vault's ERC-20 `symbol()`, verbatim from Base.
struct TokenConfig {
    string underlying;
    string name;
    string symbol;
}

/// @title LibProdTokenConfig
/// @notice The canonical name/symbol table for the 28 ST0x production
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
/// alignment. Strings are reproduced EXACTLY, including quirks that exist on
/// Base — notably `SGOV`'s name has a leading space. Matching Base "exactly"
/// means carrying that space forward; the parity pin would flag it as a
/// divergence otherwise.
library LibProdTokenConfig {
    /// @notice The 28 production token deploy configs, Base table order.
    /// @return configs The name/symbol table.
    function productionTokenConfigs() internal pure returns (TokenConfig[] memory configs) {
        configs = new TokenConfig[](28);
        configs[0] = TokenConfig("MSTR", "MicroStrategy Incorporated ST0x", "tMSTR");
        configs[1] = TokenConfig("TSLA", "Tesla Inc ST0x", "tTSLA");
        configs[2] = TokenConfig("COIN", "Coinbase Global Inc ST0x", "tCOIN");
        configs[3] = TokenConfig("SPYM", "State Street SPDR Portfolio S&P 500 ETF ST0x", "tSPYM");
        configs[4] = TokenConfig("SIVR", "abrdn Physical Silver Shares ETF ST0x", "tSIVR");
        configs[5] = TokenConfig("CRCL", "Circle Internet Group Inc ST0x", "tCRCL");
        configs[6] = TokenConfig("NVDA", "NVIDIA Corporation ST0x", "tNVDA");
        configs[7] = TokenConfig("IAU", "iShares Gold Trust ST0x", "tIAU");
        configs[8] = TokenConfig("PPLT", "abrdn Physical Platinum Shares ETF ST0x", "tPPLT");
        configs[9] = TokenConfig("AMZN", "Amazon.com Inc ST0x", "tAMZN");
        configs[10] = TokenConfig("BMNR", "Bitmine Immersion Technologies, Inc ST0x", "tBMNR");
        configs[11] = TokenConfig("IBHG", "iShares iBonds 2027 Term High Yield and Income ETF ST0x", "tIBHG");
        // NB: leading space is present on Base and is reproduced verbatim.
        configs[12] = TokenConfig("SGOV", " iShares 0-3 Month Treasury Bond ETF ST0x", "tSGOV");
        configs[13] = TokenConfig("QQQM", "Invesco NASDAQ 100 ETF ST0x", "tQQQM");
        configs[14] = TokenConfig("VWO", "Vanguard Emerging Markets Stock Index Fund ST0x", "tVWO");
        configs[15] = TokenConfig("ARKK", "ARK Innovation ETF ST0x", "tARKK");
        configs[16] = TokenConfig("SPCX", "Space Exploration Technologies Corp. ST0x", "tSPCX");
        configs[17] = TokenConfig("CEG", "Constellation Energy Corporation ST0x", "tCEG");
        configs[18] = TokenConfig("DRAM", "Roundhill Memory ETF ST0x", "tDRAM");
        configs[19] = TokenConfig("TSM", "Taiwan Semiconductor Manufacturing Company Limited ADR ST0x", "tTSM");
        configs[20] = TokenConfig("SKHY", "SK hynix Inc. ADR ST0x", "tSKHY");
        configs[21] = TokenConfig("ASML", "ASML Holding N.V. ST0x", "tASML");
        configs[22] = TokenConfig("MU", "Micron Technology, Inc. ST0x", "tMU");
        configs[23] = TokenConfig("AMD", "Advanced Micro Devices, Inc. ST0x", "tAMD");
        configs[24] = TokenConfig("AVGO", "Broadcom Inc. ST0x", "tAVGO");
        configs[25] = TokenConfig("AMAT", "Applied Materials, Inc. ST0x", "tAMAT");
        configs[26] = TokenConfig("LRCX", "Lam Research Corporation ST0x", "tLRCX");
        configs[27] = TokenConfig("TTWO", "Take-Two Interactive Software, Inc. ST0x", "tTTWO");
    }
}

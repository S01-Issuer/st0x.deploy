// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {LibProdTokenConfig, TokenConfig} from "./LibProdTokenConfig.sol";
import {LibListingTree, ListingRow} from "./LibListingTree.sol";

/// @notice The rows of the V6 listing do not derive `ROOT`.
/// @param expected The frozen root.
/// @param actual The root the rows derive.
error V6ListingMoved(bytes32 expected, bytes32 actual);

/// @notice A listed row's token address or asset id no longer matches the table row in its place.
/// @param assetId The signed row's asset id.
/// @param signed The signed row's token.
/// @param derived The token the table row derives.
error V6ListingTokenMoved(string assetId, address signed, address derived);

/// @notice The table rows to check against the signed rows are not as many as the signed rows.
/// @param expected The number of signed rows.
/// @param actual The number of table rows.
error V6ListingRowCount(uint256 expected, uint256 actual);

/// @notice The table has fewer V6 rows than the listing names.
/// @param expected `ROW_COUNT`.
/// @param actual The number of V6 rows.
error V6ListingTableShort(uint256 expected, uint256 actual);

/// @title LibV6Listing
/// @notice The listing that first-names the leading `ROW_COUNT` production V6 tokens and the two test tokens on every
/// chain: the root the listing signer signs.
library LibV6Listing {
    /// @notice The listing root; frozen, since the listing signer signs it.
    bytes32 internal constant ROOT = 0x620bdcbe8ef7d32c36ec74daac5663c5cb5b4915f1882adb1a7f9bc85d2e0a6f;

    /// @notice How many leading production V6 rows the listing names; a row appended after them does not move it.
    uint256 internal constant ROW_COUNT = 59;

    /// @notice The leading `ROW_COUNT` production V6 rows, then the test tokens.
    /// @return The rows; reverts `V6ListingTableShort` when the table has fewer V6 rows.
    function configs() internal pure returns (TokenConfig[] memory) {
        return listedFrom(LibProdTokenConfig.v6TokenConfigs());
    }

    /// @notice The leading `ROW_COUNT` of `production`, then the test tokens.
    /// @param production The production V6 rows, in table order.
    /// @return The rows; reverts `V6ListingTableShort` when `production` has fewer than `ROW_COUNT`.
    function listedFrom(TokenConfig[] memory production) internal pure returns (TokenConfig[] memory) {
        if (production.length < ROW_COUNT) revert V6ListingTableShort(ROW_COUNT, production.length);
        TokenConfig[] memory test = LibProdTokenConfig.testTokenConfigs();
        TokenConfig[] memory listed = new TokenConfig[](ROW_COUNT + test.length);
        for (uint256 i = 0; i < ROW_COUNT; i++) {
            listed[i] = production[i];
        }
        for (uint256 i = 0; i < test.length; i++) {
            listed[ROW_COUNT + i] = test[i];
        }
        return listed;
    }

    /// @notice The signed rows, as signed: a later rename of a listed issuer in the table does not change them.
    /// @return The rows; reverts `V6ListingMoved` unless they derive `ROOT`.
    function rows() internal pure returns (ListingRow[] memory) {
        ListingRow[] memory signed = signedRows();
        bytes32 root = LibListingTree.root(signed);
        if (root != ROOT) revert V6ListingMoved(ROOT, root);
        return signed;
    }

    /// @notice The signed rows, after checking that each one's token and asset id are those of the row of `listed` in
    /// its place.
    /// @param listed The table rows, as `configs` returns them.
    /// @return The signed rows; reverts `V6ListingTokenMoved` on a row whose token or asset id moved.
    function rowsFor(TokenConfig[] memory listed) internal pure returns (ListingRow[] memory) {
        ListingRow[] memory signed = rows();
        ListingRow[] memory derived = LibListingTree.rows(listed);
        if (derived.length != signed.length) revert V6ListingRowCount(signed.length, derived.length);
        for (uint256 i = 0; i < signed.length; i++) {
            if (
                derived[i].token != signed[i].token
                    || keccak256(bytes(derived[i].assetId)) != keccak256(bytes(signed[i].assetId))
            ) {
                revert V6ListingTokenMoved(signed[i].assetId, signed[i].token, derived[i].token);
            }
        }
        return signed;
    }

    /// @notice The rows the listing signer signed under `ROOT`: token, asset id, ticker and underlying name.
    /// @return The rows.
    function signedRows() internal pure returns (ListingRow[] memory) {
        ListingRow[] memory signed = new ListingRow[](ROW_COUNT + 2);
        signed[0] = ListingRow({
            token: 0xbC326eC6179Ee9ae04E264C7EB18044A7fd0E017,
            assetId: "US5949724083",
            ticker: "MSTR",
            name: "Strategy Inc"
        });
        signed[1] = ListingRow({
            token: 0x04d9A4Aca7DD55F59dced9F845c7e2DaF9104291,
            assetId: "US88160R1014",
            ticker: "TSLA",
            name: "Tesla Inc"
        });
        signed[2] = ListingRow({
            token: 0x22D30D699f07AAbB822efea0e45C9C8497C28eca,
            assetId: "US19260Q1076",
            ticker: "COIN",
            name: "Coinbase Global Inc"
        });
        signed[3] = ListingRow({
            token: 0x8f0106aAe3BC5c2a1517e43072B9a5F9D046DEE7,
            assetId: "US78464A8541",
            ticker: "SPYM",
            name: "State Street SPDR Portfolio S&P 500 ETF"
        });
        signed[4] = ListingRow({
            token: 0x29C07Fc81e61BB47eEB0760bFb5d488D388Ad60D,
            assetId: "US0032641088",
            ticker: "SIVR",
            name: "abrdn Physical Silver Shares ETF"
        });
        signed[5] = ListingRow({
            token: 0x1fEDcBFf9e122277BC132de32FE8d3014AcaF35A,
            assetId: "US1725731079",
            ticker: "CRCL",
            name: "Circle Internet Group Inc"
        });
        signed[6] = ListingRow({
            token: 0x24cAac3BDDf50E009D037C796C7Aed04C0ABC6c3,
            assetId: "US67066G1040",
            ticker: "NVDA",
            name: "NVIDIA Corporation"
        });
        signed[7] = ListingRow({
            token: 0xBcdA1BA7BF0A811FaF8B2636Ad0aC20fcebC7fBb,
            assetId: "US4642852044",
            ticker: "IAU",
            name: "iShares Gold Trust"
        });
        signed[8] = ListingRow({
            token: 0x9b647B15F093FFab6c4E4e50E7126809B93B6B08,
            assetId: "US0032601066",
            ticker: "PPLT",
            name: "abrdn Physical Platinum Shares ETF"
        });
        signed[9] = ListingRow({
            token: 0x9e882E0737d79D44D8AA22C9073975AF81360CeC,
            assetId: "US0231351067",
            ticker: "AMZN",
            name: "Amazon.com Inc"
        });
        signed[10] = ListingRow({
            token: 0x122A0A1dC0a6db4523161310a0482D6aD5C6a82e,
            assetId: "US09175A2069",
            ticker: "BMNR",
            name: "Bitmine Immersion Technologies, Inc"
        });
        signed[11] = ListingRow({
            token: 0x528e2F8264d29D887c9675439AeBdAb415ae4BD9,
            assetId: "US46436E4787",
            ticker: "IBHG",
            name: "iShares iBonds 2027 Term High Yield and Income ETF"
        });
        signed[12] = ListingRow({
            token: 0x1DD78073823C72E6CACB2A5165742a909C5C2c54,
            assetId: "US46436E7186",
            ticker: "SGOV",
            name: "iShares 0-3 Month Treasury Bond ETF"
        });
        signed[13] = ListingRow({
            token: 0x76A5E285976F63F6322E8CC0c600b265d01dbA24,
            assetId: "US46138G6492",
            ticker: "QQQM",
            name: "Invesco NASDAQ 100 ETF"
        });
        signed[14] = ListingRow({
            token: 0x6eED79EB9D09c3B7a35A0Fd2e7Ead89B1A478d4a,
            assetId: "US9220428588",
            ticker: "VWO",
            name: "Vanguard Emerging Markets Stock Index Fund"
        });
        signed[15] = ListingRow({
            token: 0x8764A2334F6dCA1C9b0f5C3Bf15BbC87B8c3d34b,
            assetId: "US00214Q1040",
            ticker: "ARKK",
            name: "ARK Innovation ETF"
        });
        signed[16] = ListingRow({
            token: 0xc52DD06195B1A71C758122Bc24F8D5A695d0e312,
            assetId: "US84615Q1031",
            ticker: "SPCX",
            name: "Space Exploration Technologies Corp."
        });
        signed[17] = ListingRow({
            token: 0x1830a8a511Eb2719fd8a7b7c776C88068F4d6920,
            assetId: "US21037T1097",
            ticker: "CEG",
            name: "Constellation Energy Corporation"
        });
        signed[18] = ListingRow({
            token: 0x3d25cEFC5FD90249E4DAeCb626D05cF9af3EA6eF,
            assetId: "US77926X3200",
            ticker: "DRAM",
            name: "Roundhill Memory ETF"
        });
        signed[19] = ListingRow({
            token: 0x11C3886989F75Dea1f45Ed5F7e150eC21b4933a4,
            assetId: "US8740391003",
            ticker: "TSM",
            name: "Taiwan Semiconductor Manufacturing Company Limited ADR"
        });
        signed[20] = ListingRow({
            token: 0x9a63c5BA935C13CeDC11F1fB8eD1e72221Cb119b,
            assetId: "US78392B2060",
            ticker: "SKHY",
            name: "SK hynix Inc. ADR"
        });
        signed[21] = ListingRow({
            token: 0x540F5438DEe3821D8f84a94326685C918b45291a,
            assetId: "USN070592100",
            ticker: "ASML",
            name: "ASML Holding N.V."
        });
        signed[22] = ListingRow({
            token: 0xe0E6342E683B75a79eF9572f208c8F92241040B5,
            assetId: "US5951121038",
            ticker: "MU",
            name: "Micron Technology, Inc."
        });
        signed[23] = ListingRow({
            token: 0x459d82598075b25c4BEABaebB1B23BB717156b3C,
            assetId: "US0079031078",
            ticker: "AMD",
            name: "Advanced Micro Devices, Inc."
        });
        signed[24] = ListingRow({
            token: 0x442b6A5A9B14D5a949bD6CBa2b019538E94eC6DD,
            assetId: "US11135F1012",
            ticker: "AVGO",
            name: "Broadcom Inc."
        });
        signed[25] = ListingRow({
            token: 0xCF1F2B7F6a8B12E91cB3cE33252D5C1921b9e66E,
            assetId: "US0382221051",
            ticker: "AMAT",
            name: "Applied Materials, Inc."
        });
        signed[26] = ListingRow({
            token: 0x2524756BeD5777dE5DB5C286AF823653E4A5B470,
            assetId: "US5128073062",
            ticker: "LRCX",
            name: "Lam Research Corporation"
        });
        signed[27] = ListingRow({
            token: 0xffbF50E9a44E38267fd0afedE66d5173d6A18fCE,
            assetId: "US8740541094",
            ticker: "TTWO",
            name: "Take-Two Interactive Software, Inc."
        });
        signed[28] = ListingRow({
            token: 0xF057b31923C84cE721b01b59F5cB28b78C39CaA8,
            assetId: "US7731211089",
            ticker: "RKLB",
            name: "Rocket Lab Corporation"
        });
        signed[29] = ListingRow({
            token: 0xeE2339599EcbC2AE1854e4e28b3e95e1784521fB,
            assetId: "US02079K3059",
            ticker: "GOOGL",
            name: "Alphabet Inc. Class A"
        });
        signed[30] = ListingRow({
            token: 0x09cde3825DfCB7ee3F6A226eb8a1999372246a10,
            assetId: "US0378331005",
            ticker: "AAPL",
            name: "Apple Inc."
        });
        signed[31] = ListingRow({
            token: 0x3200A6267109C85873aac4A5Be4A457f34Ff8eC2,
            assetId: "US5949181045",
            ticker: "MSFT",
            name: "Microsoft Corporation"
        });
        signed[32] = ListingRow({
            token: 0x51507fDB4fAfB972a14775A2B9BE7AD3Fd75300d,
            assetId: "US5324571083",
            ticker: "LLY",
            name: "Eli Lilly and Company"
        });
        signed[33] = ListingRow({
            token: 0x26E25438DbAF3d2facCd4284dd672B02D15FCFF1,
            assetId: "US72201B1017",
            ticker: "PTY",
            name: "PIMCO Corporate & Income Opportunity Fund"
        });
        signed[34] = ListingRow({
            token: 0xC092D39E56F15E5e7c970217a2c5C84A735e2c9C,
            assetId: "US4581401001",
            ticker: "INTC",
            name: "Intel Corporation"
        });
        signed[35] = ListingRow({
            token: 0x5637506917673D780117096aC27bE091f84a27D4,
            assetId: "US7707001027",
            ticker: "HOOD",
            name: "Robinhood Markets, Inc."
        });
        signed[36] = ListingRow({
            token: 0x9dcaE50e711e8d0442e78C9b11DF77E695Fd9006,
            assetId: "US68389X1054",
            ticker: "ORCL",
            name: "Oracle Corporation"
        });
        signed[37] = ListingRow({
            token: 0x7b7f5Fc75a6177dF8612A2D6cf185cAF572C9E23,
            assetId: "US86800U3023",
            ticker: "SMCI",
            name: "Super Micro Computer, Inc."
        });
        signed[38] = ListingRow({
            token: 0x93C53C4eEb45E5F52478431E2f2602D83C2359f7,
            assetId: "US01609W1027",
            ticker: "BABA",
            name: "Alibaba Group Holding Limited ADR"
        });
        signed[39] = ListingRow({
            token: 0xdb0D24f33b4e97A6143896d2F8DB17a0fA8C5617,
            assetId: "US74347X8314",
            ticker: "TQQQ",
            name: "ProShares UltraPro QQQ"
        });
        signed[40] = ListingRow({
            token: 0x2037aB87DFCe1283ba2eCF15bdC9b026eA3e06ff,
            assetId: "US35472T1016",
            ticker: "FTF",
            name: "Franklin Limited Duration Income Trust"
        });
        signed[41] = ListingRow({
            token: 0x630031a0809eD49CeaEDE0a023aC190d1a92b406,
            assetId: "US15675D1037",
            ticker: "CBRS",
            name: "Cerebras Systems Inc."
        });
        signed[42] = ListingRow({
            token: 0x81f7b51747A988376959C4cd52516245Cd1c89b8,
            assetId: "US5801351017",
            ticker: "MCD",
            name: "McDonald's Corporation"
        });
        signed[43] = ListingRow({
            token: 0x6E6994C5D98463f66f7Ba35814cE8196239d1F76,
            assetId: "US6541061031",
            ticker: "NKE",
            name: "NIKE, Inc."
        });
        signed[44] = ListingRow({
            token: 0xFb29DF7E3B554B1724b16e9D9171d11661a07493,
            assetId: "US39854F1012",
            ticker: "GRND",
            name: "Grindr Inc."
        });
        signed[45] = ListingRow({
            token: 0x2635cAC1E438C87F79C251b3C4EB0Fef3C3596c1,
            assetId: "US50101L1061",
            ticker: "DNUT",
            name: "Krispy Kreme, Inc."
        });
        signed[46] = ListingRow({
            token: 0x77FE3DD3D481CeFc681128e57CE7C17cea61C87d,
            assetId: "US72814P1093",
            ticker: "PLBY",
            name: "Playboy, Inc."
        });
        signed[47] = ListingRow({
            token: 0xE5CF2E3298352a56421Be866c0764fd9C1Cc0fF9,
            assetId: "US8905161076",
            ticker: "TR",
            name: "Tootsie Roll Industries, Inc."
        });
        signed[48] = ListingRow({
            token: 0x6eA93EdD59117b329D1Fd0aac10FD62cC99DDF59,
            assetId: "US95058W1009",
            ticker: "WEN",
            name: "The Wendy's Company"
        });
        signed[49] = ListingRow({
            token: 0xff53c72fB9A359DF9dA0d066615221D4b527c5c4,
            assetId: "KYG3302D2024",
            ticker: "FGI",
            name: "FGI Industries Ltd."
        });
        signed[50] = ListingRow({
            token: 0xB90aeFE338B75433f876161BDC967F5C424008bC,
            assetId: "US01675A2087",
            ticker: "BIRD",
            name: "Smartbird, Inc."
        });
        signed[51] = ListingRow({
            token: 0xA7b4B8739E1152D9B01107f5fc7D1a277c6B190D,
            assetId: "US78462F1030",
            ticker: "SPY",
            name: "State Street SPDR S&P 500 ETF Trust"
        });
        signed[52] = ListingRow({
            token: 0xE26B4315353379fD4d61AC0D7441A0e4E2a4De27,
            assetId: "US81720R6045",
            ticker: "SNES",
            name: "SenesTech, Inc."
        });
        signed[53] = ListingRow({
            token: 0xA45a92Aa5cA20CB89cB075868f5051e4D5470564,
            assetId: "US9311421039",
            ticker: "WMT",
            name: "Walmart Inc."
        });
        signed[54] = ListingRow({
            token: 0xf30c12D819CD2ef07A906aBd24037f58658d01c6,
            assetId: "FR0000121014",
            ticker: "MC",
            name: unicode"LVMH Moët Hennessy Louis Vuitton SE"
        });
        signed[55] = ListingRow({
            token: 0x9a5C86b0563762Abb8073e6a3a0B091e4A89F51E,
            assetId: "US2546871060",
            ticker: "DIS",
            name: "The Walt Disney Company"
        });
        signed[56] = ListingRow({
            token: 0x7d1Bc64545fD011Ac0B8b47f9e67945bbEc7c9c6,
            assetId: "DE0006231004",
            ticker: "IFX",
            name: "Infineon Technologies AG"
        });
        signed[57] = ListingRow({
            token: 0xB38886cE20f7Ad88d0C58Ab8FA758783fa7F318b, assetId: "FR0013227113", ticker: "SOI", name: "Soitec SA"
        });
        signed[58] = ListingRow({
            token: 0xAb9528135aDD6D59D45706c698d2B2DF6dC41920,
            assetId: "IT0005482333",
            ticker: "TPRO",
            name: "Technoprobe S.p.A."
        });
        signed[59] = ListingRow({
            token: 0xac3877cC44E59d02a79C08470fE166B3412BCf63, assetId: "ST0XTESTUS", ticker: "USTEST", name: "US Test"
        });
        signed[60] = ListingRow({
            token: 0x267d73588AA23Bc728cc107eBe921145f63B5A36, assetId: "ST0XTESTEU", ticker: "EUTEST", name: "EU Test"
        });
        return signed;
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    LibRainDeployRegistryBeaconProxy,
    RegistryBeaconProxyParams
} from "rain-factory-0.2.18/src/lib/LibRainDeployRegistryBeaconProxy.sol";

import {TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibProdTokenParams} from "../../../src/lib/LibProdTokenParams.sol";
import {LibTestTokenRows} from "../../lib/LibTestTokenRows.sol";

struct TokenAddressPin {
    string symbol;
    address token;
    address wrapper;
}

/// @notice A change that moves any row's token or wrapper address fails here instead of silently re-deriving.
contract StoxDeploySuitesTokenAddressesTest is Test {
    function pins() internal pure returns (TokenAddressPin[] memory) {
        TokenAddressPin[] memory pinned = new TokenAddressPin[](61);
        pinned[0] = TokenAddressPin(
            "tMSTR", 0x75793927E8406f7F56E4BE9e52a968fa883469bF, 0x3334634B162724d47999e053e1a2c797d42FEd7a
        );
        pinned[1] = TokenAddressPin(
            "tTSLA", 0x5fAc579be2579Fe24Df28a9d8e0c55a745F7B94E, 0xd360b4fE2DA90A5F5f0eB97fcAc31DDE8aD7C609
        );
        pinned[2] = TokenAddressPin(
            "tCOIN", 0x094c04FbED0137741478F00bA3AFDF283CF4935F, 0xd43107Cb1119c771120D1Df99ec5fd93Ed225Ce5
        );
        pinned[3] = TokenAddressPin(
            "tSPYM", 0xB23c66440405B48b7E50a9177D7D83B5e7d4e2a7, 0xbffE5F7d24cEA214876B0b7452984866DaEA6F2d
        );
        pinned[4] = TokenAddressPin(
            "tSIVR", 0xE2cbD384A4568AB5Feb1D807c5a5f7AC3771b1d7, 0x36f3ee9c9c6454130D307feD17c1c8A108c6aC1c
        );
        pinned[5] = TokenAddressPin(
            "tCRCL", 0xDC5c57969A53be5a90E07a8290722F35bd9DF6fe, 0x0e54e50516914f12E6F0a493eFA2aD433BBbcCC8
        );
        pinned[6] = TokenAddressPin(
            "tNVDA", 0x3c65fa591aa6f962Be011217292dFA07d8e1E878, 0x7aef7fd1325EA1666C8F488B9459e5F35772100c
        );
        pinned[7] = TokenAddressPin(
            "tIAU", 0xE602A39E5b7BDa691b4D6087FBFcA6698a0E9d02, 0x0B8E2Aa0119aD07F209FDEAE68256C66142b78b1
        );
        pinned[8] = TokenAddressPin(
            "tPPLT", 0x342f9DE5bc9275F082e692f4656B98b0A57e0Bf5, 0x2E8A1514C5b97d09DD1C2AB8aC5320AFE0797e59
        );
        pinned[9] = TokenAddressPin(
            "tAMZN", 0x0741331DB63E67e95979F18E0e5B21AC7f479B90, 0x911b4DBD7B8ef9899f75fb388d174dafdD67553b
        );
        pinned[10] = TokenAddressPin(
            "tBMNR", 0xFb91C10E4D59a7a9d7358bcBa1952bdc9C92Cebe, 0x6Dd08Df19438046DF6fEca1432D0E7e0c997BD92
        );
        pinned[11] = TokenAddressPin(
            "tIBHG", 0x892606F048F00a34fa64f2a7E72d5df204089215, 0xbd185C6A16f2448751509e54849C506266DF9576
        );
        pinned[12] = TokenAddressPin(
            "tSGOV", 0xB1513b3a800cAf934e10654aa6827f3f8c9B90bF, 0xEE3489ca5957bB93068Ee0DbfBF4e22D256a02c6
        );
        pinned[13] = TokenAddressPin(
            "tQQQM", 0x642068e8F27a67BDdb4260Fe5401479e2480e40f, 0xb08E6632b93c0c74dFA3B5BFc83Df63B8c0576C6
        );
        pinned[14] = TokenAddressPin(
            "tVWO", 0xe90aEEe1E15EB6e9Ac466c5444Fde87324313194, 0xE341ed5f2EDe55CF1128919521dfF8a6C17c2dF6
        );
        pinned[15] = TokenAddressPin(
            "tARKK", 0x54fd6804169B9941f985300346092F996132fBC7, 0xEeA0f74EafF05A93bbb61c5696A787DB848E682d
        );
        pinned[16] = TokenAddressPin(
            "tSPCX", 0x3ffd1a2A6c6d2A644843Edc691c5a3cEE155Da9F, 0x5b9CBC51428F9DBf2B2cBF5Ce69090fA96BcefC5
        );
        pinned[17] = TokenAddressPin(
            "tCEG", 0xCF0271D996ED0B7Bb0431b09B473b4f8CE4A79BD, 0xcDbFC11A6C6F1c1A366F9A569bE794eaA8677864
        );
        pinned[18] = TokenAddressPin(
            "tDRAM", 0x4fdEa05248eF475350F357C5B61176cBEc0cC631, 0x1DE44A7a65480EA34A0E7b76a05046A866bC8d12
        );
        pinned[19] = TokenAddressPin(
            "tTSM", 0xb27a477Fb7BeaCCEadfc358F2651D4524f362eb2, 0x1966421367E01d3d398b8850FF782Cc13a299dFe
        );
        pinned[20] = TokenAddressPin(
            "tSKHY", 0x10379537E19Ea46a8f5148f7BDD055124B584C0F, 0x89cf32499b26D78aA920AB52be317D8e00D1f473
        );
        pinned[21] = TokenAddressPin(
            "tASML", 0x80fCF2152AEC5fcAB15D38677F724d3A67A28829, 0x776eF1852BBbEb73cAA463403c7a8899d072Ba02
        );
        pinned[22] = TokenAddressPin(
            "tMU", 0xbadad753196544536eFa2061e9B74f3c6F627bBF, 0x762c7048A6e89dc484352b8bc6ee4bef305FD2C4
        );
        pinned[23] = TokenAddressPin(
            "tAMD", 0xcd6465b459C7eE5a42B59929a4DAe2A188326DE9, 0x35aF734496C340A65215Bf90a2fD52E05033067B
        );
        pinned[24] = TokenAddressPin(
            "tAVGO", 0x4754320b463743493691C44B2375008DA6271923, 0x27B3d02A817B771f3618A41e96Ca213d5B58cBe0
        );
        pinned[25] = TokenAddressPin(
            "tAMAT", 0xCEA275fEb4C618C50DE1fD6Affaf13EbCdC4F104, 0x4a6Ec128BCC67C3f9148ea56E537354a09c19Dfd
        );
        pinned[26] = TokenAddressPin(
            "tLRCX", 0x52DA9e91888cD4cEDE3a2dbA8c30d29eFDf5F0D0, 0xD18C72bFAb1b97b72f29CbE2e8F7778d0Ab253f8
        );
        pinned[27] = TokenAddressPin(
            "tTTWO", 0xcD1e8d585B3f599dfa2b7311125DA19b8f75D798, 0xcD81138154d5f20761a4a4D65Bca56a85df7fcF5
        );
        pinned[28] = TokenAddressPin(
            "tRKLB", 0x568Ddf6EAb16C0b9229ea53F4D2670785acea916, 0xe398515480b07eD44B7f6815A5f6333416Ab70c6
        );
        pinned[29] = TokenAddressPin(
            "tGOOGL", 0x46F5A7595778280FA2C3fF3164610D9827ECbf7f, 0x61583a27Bf235dA385b138e06eE60a3238cA1d77
        );
        pinned[30] = TokenAddressPin(
            "tAAPL", 0x7DeB596c41386E97Ba6bF62cDC9E97126b0f6434, 0x330A14a9Ab1011564371B425b6cd79E02846Ec88
        );
        pinned[31] = TokenAddressPin(
            "tMSFT", 0x8a253ea8144aE3670EfEe9F6405bE96C7e231B9F, 0xb7d0d94106B1449e6e3115b22B26ee990cd5aab4
        );
        pinned[32] = TokenAddressPin(
            "tLLY", 0x5235774C2539775FA603Bf98484a95bA91aD9bAf, 0x79427D918436b5B2c857775c8632e8789c1cD4f6
        );
        pinned[33] = TokenAddressPin(
            "tPTY", 0xA051A9399371910f56d487a5A407a7D8b2D5F307, 0x4a23893cE582a1efBA1502f7d103a71A49f927Bf
        );
        pinned[34] = TokenAddressPin(
            "tINTC", 0x99c17CD397DF041d311C76326ba116AF73E23368, 0x9aee065e0eA8D4Dfd00a06BCc878C20eaD48489A
        );
        pinned[35] = TokenAddressPin(
            "tHOOD", 0x54DBB98D7044Be2D636D27825636778cd3A7eD03, 0x237E578d9755A365609AeC1c25C593dE8917313F
        );
        pinned[36] = TokenAddressPin(
            "tORCL", 0x120216C6923aC8Dc9A20339FDe664AcFc9B6E397, 0xf7eC4334bCc98824B2500a946958453702c32d95
        );
        pinned[37] = TokenAddressPin(
            "tSMCI", 0x134dc0Fe098ce62D1197EFb02bb390CB19790535, 0x3FA1c659A555cA09160B4924c22667ef166F0D0C
        );
        pinned[38] = TokenAddressPin(
            "tBABA", 0x93Fc3ADA4a10572deF6Fb68AA3ceA424cC13d7Ed, 0xC4dCc3BCb1e95222F3EAf2E576492a7868506BF2
        );
        pinned[39] = TokenAddressPin(
            "tTQQQ", 0x311EbB0cBF3B8af9d7955a12E40A05aF639C74C1, 0x9583272dAcf6353e6BC399f6968183d89b256EDB
        );
        pinned[40] = TokenAddressPin(
            "tFTF", 0x9fB29abdC1616372368F924B1e0c8052Df0BcB48, 0xe756Ff91F7ebc5eEF82D09E7F39cD9FB97A6ce4B
        );
        pinned[41] = TokenAddressPin(
            "tCBRS", 0xD872dE98e5C9859750d33ae0d42114Dd6a16590F, 0x3309AF243AF3103AB9DC396c8Fe4258fC311efE3
        );
        pinned[42] = TokenAddressPin(
            "tMCD", 0xF8dF643ef316c5C7f8C9CFF05ca68b0345e82568, 0xED815d63E1F4C37F64Be268dd8B96AF98D7Cb44a
        );
        pinned[43] = TokenAddressPin(
            "tNKE", 0xDa330c3ff51c114f29e02DC933cD53F5f8588D5f, 0xF6EB169F4EE4c37118512B97E56fDAcb864fde02
        );
        pinned[44] = TokenAddressPin(
            "tGRND", 0xFE294685775e6B57bBfBC286A083c49e6Aca81e6, 0xa8A6D477D72EA649CC0D9EC00146D16f70498EdB
        );
        pinned[45] = TokenAddressPin(
            "tDNUT", 0xBB688108c779b2570BeC62a7D25D220020e963f5, 0x33061f7B8C0e8f29F36289eF8dD8ECFa6b4670b2
        );
        pinned[46] = TokenAddressPin(
            "tPLBY", 0x4FE3E9b730fFB25CBA8739AF0c9aBF44aF6Cd253, 0xc139D5843692268D9f0BEa4AB0C4cd9376269BaB
        );
        pinned[47] = TokenAddressPin(
            "tTR", 0x21373FCB28327b7bC6DD1677205B3443e3E82e94, 0x5c4167A37ea1Fd0B878da96f60665BF423c0Df0e
        );
        pinned[48] = TokenAddressPin(
            "tWEN", 0x915E160a89a92a1E65179D044314E2B0b5Eb354B, 0x4e58ABa2104f192F747bC18a2A7da05bE029c0fa
        );
        pinned[49] = TokenAddressPin(
            "tFGI", 0x7588F1576c3F71680E0E56567C4869328BAeE5B4, 0x86A8491000bFc9B21c8Db1a777919cf0D4c326dd
        );
        pinned[50] = TokenAddressPin(
            "tBIRD", 0x25e8a4D15E8fECB2F4351c0ddD659Bb5D37637C9, 0x70803Ef49DD0E8809F0d6771d7d6bBdff7302f6c
        );
        pinned[51] = TokenAddressPin(
            "tSPY", 0x186831d6b7244441F87E1808Ab9c566CeE872E6F, 0x8569F23b6E13da58291E06f633B635173E0D189a
        );
        pinned[52] = TokenAddressPin(
            "tSNES", 0xA89E562A9659c3a95188c0A6Af122F514cEE0d07, 0xb795F742c9DeEfbA43981097aa84e350A6979140
        );
        pinned[53] = TokenAddressPin(
            "tWMT", 0xF4CEB9E7bAcC70c0691852f9ac21AF0964660851, 0x9B9aF8f7e06ce5da2bB49903006A0c32A3474111
        );
        pinned[54] = TokenAddressPin(
            "tMC", 0x7d8e3CDd7d2947cabFb2130333B38Fa062aAE51E, 0x78e4cc24c2453772b00F37262c672EdC14c39DEc
        );
        pinned[55] = TokenAddressPin(
            "tDIS", 0xb19e8F875192903CcF36cd990C25c2E389397F36, 0x346f59a8F7b623497adce30bc8adE7515a7adC44
        );
        pinned[56] = TokenAddressPin(
            "tIFX", 0xb74A0445f896885191a0F3a6cF75Ed4FC368bEf5, 0xF576d22355DdD6aC33E723d6c4E95cb47b4fbDc5
        );
        pinned[57] = TokenAddressPin(
            "tSOI", 0xeAdbE2A2e8eB60ACa03bf83edD6b11849194b189, 0x9B4DA3e8c4EC7c4349Df16d4DC36d12ca0433A93
        );
        pinned[58] = TokenAddressPin(
            "tTPRO", 0x27e4dD505BC378dBdED9b1aa56Ff62Dbb40C97F1, 0xb0C2516d13F2E4F33CD722042dF1D45fCF18C8c9
        );
        pinned[59] = TokenAddressPin(
            "tUSTEST", 0xad1045B48361790dbcDc758e678705142B3c4B9E, 0x872bb64EAC21498866961840A94C45Ce856451a3
        );
        pinned[60] = TokenAddressPin(
            "tEUTEST", 0x232744918DB33a692673d108FbcEf274cF621244, 0x422cC24570da44d0696F7953c287A90eF2495241
        );
        return pinned;
    }

    function testEveryTokenRowsTokenAndWrapperLandAtTheirPinnedAddresses() external pure {
        TokenConfig[] memory rows = LibTestTokenRows.allRows();
        RegistryBeaconProxyParams[] memory tokens = LibProdTokenParams.tokenParams(rows);
        RegistryBeaconProxyParams[] memory wrappers = LibProdTokenParams.wrapperParams(rows);
        TokenAddressPin[] memory pinned = pins();
        assertEq(pinned.length, rows.length, "one pin per row");
        for (uint256 i = 0; i < rows.length; i++) {
            assertEq(pinned[i].symbol, rows[i].symbol, "row");
            assertEq(
                LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(tokens[i]),
                pinned[i].token,
                rows[i].symbol
            );
            assertEq(
                LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(wrappers[i]),
                pinned[i].wrapper,
                string.concat(rows[i].symbol, " wrapper")
            );
        }
    }
}

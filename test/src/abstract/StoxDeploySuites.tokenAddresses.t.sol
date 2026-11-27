// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    LibRainDeployRegistryBeaconProxy,
    RegistryBeaconProxyParams
} from "rain-factory-0.2.21/src/lib/LibRainDeployRegistryBeaconProxy.sol";

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
            "tMSTR", 0x82583cAD4442CA1dcAB5A15EA61Db4970c71E638, 0x33C59f43062c19449D1085688A07628C82df93dB
        );
        pinned[1] = TokenAddressPin(
            "tTSLA", 0xaf51460BE36965050553C374ddb6Abb85d61d494, 0x1a311fcACb41DBa3eC74a455B563aB2D98C7672b
        );
        pinned[2] = TokenAddressPin(
            "tCOIN", 0xA0ce7dabDdD1D949af1a8EcBC8bad4663Fb4B158, 0x0f03d67837ddb09c858d62153205C01f0B9535E1
        );
        pinned[3] = TokenAddressPin(
            "tSPYM", 0x711891FEB244D83F555D710c819D5230fB960628, 0xe8c9D500e6EB3a14Ee965A62EB0546bc2468e86e
        );
        pinned[4] = TokenAddressPin(
            "tSIVR", 0xf04d763879f6fF861c502E9DFDF9956DFE72A20d, 0xEbd6e6D571321b4c6c4449433F729045A91B18FD
        );
        pinned[5] = TokenAddressPin(
            "tCRCL", 0x37F400d638f8f1701D32E528b7e6048255a27255, 0x30167C064c65f57EF09381dC3B030B9e32AE3F0a
        );
        pinned[6] = TokenAddressPin(
            "tNVDA", 0x17bE576A1b7a957081e44138f2a5640C55012915, 0xf178B3Eef6A62D17CB459317A5BD4a18f0ca8921
        );
        pinned[7] = TokenAddressPin(
            "tIAU", 0x9CB87e76BC2246F4f6B4592e16F2B506AB515bDF, 0x46cfa6708698cc7489Fde54aed46E50c0132d733
        );
        pinned[8] = TokenAddressPin(
            "tPPLT", 0x0192AD80AC76C1906F9dF1DF4b19ABEF5aA629cE, 0x8F7daee37768218f7E39cfBaC00bE06707014Fb5
        );
        pinned[9] = TokenAddressPin(
            "tAMZN", 0x1060A3F95DaB7E0fe0622BC58d9944138B09F32e, 0x30c770Ed9B28523b064ED77885cd55CdD732e898
        );
        pinned[10] = TokenAddressPin(
            "tBMNR", 0xE300De515E61Cb42Ca0Fec89941437310368Dd9a, 0xeee0F24425fEfBb93167e731bDF9b3Cfb20c8711
        );
        pinned[11] = TokenAddressPin(
            "tIBHG", 0xe5FC07e507B8cFf18A5b1EE21d3040a932eA69e5, 0x8a9da42782c93c9FF7C17720e3321d4208a78388
        );
        pinned[12] = TokenAddressPin(
            "tSGOV", 0xbA0218236E4F3dd58b43f6B03d55234e9C008a2b, 0xb94AF9dd78483301C6E6dFcC775D0e1C88b146fF
        );
        pinned[13] = TokenAddressPin(
            "tQQQM", 0xD2e40490D210d62229d8b264A8c7aa0c8b311B61, 0x055DD0b89Ac76958eCcaCC8D860913a1F564842b
        );
        pinned[14] = TokenAddressPin(
            "tVWO", 0x2252c1e1B48927BbA639fA8D4Cf07B385F1674cC, 0xa305d7076d2325c70998270864D990326D2188d2
        );
        pinned[15] = TokenAddressPin(
            "tARKK", 0x00eE6b77599bAF6663F968C6e46893F9d3148729, 0xc645ad715b287CBbeDC3a35C498bdeDCcF6D47cf
        );
        pinned[16] = TokenAddressPin(
            "tSPCX", 0xF45a4E22Aa6FE92a3D8f2f2A35Fb084d950f3373, 0xc51448b3D6467D5735533f6399C35a35a34FB37E
        );
        pinned[17] = TokenAddressPin(
            "tCEG", 0xAaBEa4861Fd290F69Dd4E211d6A2Dfb84eAF48D5, 0x05eD1dA27CB34C44fc2C4C74952D41b0a61169e7
        );
        pinned[18] = TokenAddressPin(
            "tDRAM", 0xb6a615F3996B7DC527C5C14409949Ba949e22830, 0xF53d674dc0bD4F5DD592bFCE5198525d924A6538
        );
        pinned[19] = TokenAddressPin(
            "tTSM", 0xD832113472d0Db7Bc368c4d30Ed5dadfe1ba0578, 0x277F58B594b00E640D3dDee6c555be3ae4142784
        );
        pinned[20] = TokenAddressPin(
            "tSKHY", 0x741dceA6e7BD458887a454505888a3eaBe16d0D4, 0x5b70276cCdd3009e23f16ac8f75D9aEf5e39BBC7
        );
        pinned[21] = TokenAddressPin(
            "tASML", 0x6b3e1Ef523Baab01689C35eBDE4f48ad01950004, 0xcA6e47D812154D6E7AA47939db9005202093a3a3
        );
        pinned[22] = TokenAddressPin(
            "tMU", 0x0fCF2fF13b13f573aFa1Da1bFba35456e420F0Cc, 0x90e423ddaB315C456C03A50F25590Ed4013c7AB7
        );
        pinned[23] = TokenAddressPin(
            "tAMD", 0xBCd8638E54a72f0010943D563Fa3db1E817F23A3, 0x54Ef9336b1Cd68f8F9FD15d2E19E7351D267b6e1
        );
        pinned[24] = TokenAddressPin(
            "tAVGO", 0x2d37302b79fEcc2A3697e0cF91deF7B7062c2B31, 0x7aF87344153776F5e3da9b1Ea337C8E1aa5c9a7B
        );
        pinned[25] = TokenAddressPin(
            "tAMAT", 0x5b31E66C91862fc0cB7b18cD6a42a92e56Df2333, 0xE4b7670AC3F35e090cdE8D2eE4B9Dc32a05D5720
        );
        pinned[26] = TokenAddressPin(
            "tLRCX", 0x973B202104001272fAe6919181A646d0dab0E3dD, 0xb9A139b201587c8a52c40321a276E039d575c9bB
        );
        pinned[27] = TokenAddressPin(
            "tTTWO", 0x0C5e95B4Ce767B33bc015700Eaa8355b08e3Dba9, 0x110d28f855e833333A62dBD59F1877f8FB5aE9Be
        );
        pinned[28] = TokenAddressPin(
            "tRKLB", 0x2d512059D0b83A13eA43F9C15b20a940eB122A4d, 0xE5802d3B40576c411fC461FCF2761d0E837A8B06
        );
        pinned[29] = TokenAddressPin(
            "tGOOGL", 0x40F80CdF53B024F24FaC3FD5c39d49f4667f9DB2, 0xa54291026d9BF40318B6B1A8AFF62d7969574EAe
        );
        pinned[30] = TokenAddressPin(
            "tAAPL", 0x7f44c5d3676896306d82744486A980ede58f55d8, 0x8d0b5e4fa494457A2e985B736a650E60d801EA54
        );
        pinned[31] = TokenAddressPin(
            "tMSFT", 0x869aCEF74A4117c4608D6Bd47217D3025A11d679, 0x6C72E7e37abE21bF066A4093c4b1325de1ba1BC2
        );
        pinned[32] = TokenAddressPin(
            "tLLY", 0x350D4f8E7fB63f14C5ffC64f6Cd390B36D22CF13, 0xE5Bfb1878d16c58DBE7838c8F451b3Aa4e8e1Ba4
        );
        pinned[33] = TokenAddressPin(
            "tPTY", 0x140FB4142c1a90aA673d021EF277DA8B06f03157, 0xBEbE577F6bc761B5F18ba5e692F80FB77980B4FD
        );
        pinned[34] = TokenAddressPin(
            "tINTC", 0x83c611384Dbfad69c8043D05496eE56fe5607CaB, 0x0809a7814D7450C8e294945ca8aDC0148487bAA9
        );
        pinned[35] = TokenAddressPin(
            "tHOOD", 0x5864F064EfE6D8977FF18E7aD9480173Da765854, 0x0c16653F892c9d809231263FC4D110b01c0d2ba4
        );
        pinned[36] = TokenAddressPin(
            "tORCL", 0x89CAF3EFF07bace7a531A7950014c91077668B42, 0x69D05f45f98E53DbFEe9E303D70d962c97CF97Dc
        );
        pinned[37] = TokenAddressPin(
            "tSMCI", 0x4C312dA57B8B4c66Bd2d0b4624D20869c6c5ae6f, 0xDDEe94cacc2ACdFca6cE816a27E36aD8f9900A54
        );
        pinned[38] = TokenAddressPin(
            "tBABA", 0x930d85B95b9C59442264180083E512945a2d32F4, 0xC4313D624Ef9458cFe3facFD7C0D17062e85e160
        );
        pinned[39] = TokenAddressPin(
            "tTQQQ", 0x0C8B8a7B168D8e5652F72d37184B60e39B3Cc702, 0x85489c5576769F7F626bdf836EC712b1A59F7B23
        );
        pinned[40] = TokenAddressPin(
            "tFTF", 0x494d1Ac347Cb371a80a5e7FEcC0D03309cdca428, 0x08f17C26e7118Fd27EEF488947711Ef47f632EBE
        );
        pinned[41] = TokenAddressPin(
            "tCBRS", 0x7f4b52DC6bE0AE6829d76b9305f9b4192e205A87, 0x711Fa23a45816C51Bf67d28Dd234Eb2A28e78fE6
        );
        pinned[42] = TokenAddressPin(
            "tMCD", 0x4038386Cca59dA5Ce06455a66FA55C83D7944bAe, 0xf9a8BCf80196Db2677720DF4EA831Da91125c40c
        );
        pinned[43] = TokenAddressPin(
            "tNKE", 0x3245d16Dd8cBb9B61be9F8CD904B44F6127a66e7, 0x5E15964797c1E1d1BA44345200A111476c506329
        );
        pinned[44] = TokenAddressPin(
            "tGRND", 0x06906404C7F4A97b4D99d26709016a5ad5861E42, 0xdC67abF4e09679E83C85F7936967bbe65Ef2A8a5
        );
        pinned[45] = TokenAddressPin(
            "tDNUT", 0xa5C49A65A5AAb54d9cdA1668d5BF4E0DF4279B96, 0xD103Ae0fFf46E706b0F9e15af2580e4F28a35dE6
        );
        pinned[46] = TokenAddressPin(
            "tPLBY", 0xb34D680B9Fd27CA3b76bf1c519a31CDf613B9744, 0x66D1bdC8079DC8100414795d0A29d75a3dBf4527
        );
        pinned[47] = TokenAddressPin(
            "tTR", 0x453867037b702bFbb9Bc1BA39584fD2106e1cCa8, 0xb70F9Eed956D602BC9d3E8Bc5abb45e1C64C572d
        );
        pinned[48] = TokenAddressPin(
            "tWEN", 0x75a03cBc839c9B133A868a6FBF995CacAF16dc4f, 0x003885909786A5d04F4B24987C780ce70Bc9cFA1
        );
        pinned[49] = TokenAddressPin(
            "tFGI", 0x50DF14AC73CEF02F9C26aEd9530f4A8c07DD09ab, 0x5350B6EAf6067090B7a7972Cf837DAb41761af55
        );
        pinned[50] = TokenAddressPin(
            "tBIRD", 0x7a35f53E13908afb203B21076a54fbafcdbC6DA9, 0x4ffC4d8EdF4e05E5ec40774CA798a471598a2658
        );
        pinned[51] = TokenAddressPin(
            "tSPY", 0x2c8E517313e57273D6B915a449AAd5ca73536b0D, 0xe971173caE47DfeF05b241715473D5fD14EAe1C9
        );
        pinned[52] = TokenAddressPin(
            "tSNES", 0x8474Bc9516b4A390A8484508d21aa35ee6DD7724, 0xDf15334371206a44aB6612AD129F69b9632C76Ff
        );
        pinned[53] = TokenAddressPin(
            "tWMT", 0x93Bb9C01610e5A85Aee53f9E01AC086D1D05fc72, 0x670E2cE44D974C8eCdCfa064E4fd68da22B159FB
        );
        pinned[54] = TokenAddressPin(
            "tMC", 0x0472F40bDa5F18A7a83C870f196843641dEb0Dd6, 0x10e65873301a969770822bb399F05B65140C50DF
        );
        pinned[55] = TokenAddressPin(
            "tDIS", 0x5Da35C1E80f09933Fdd7ac70880f1408Fe3DeEb3, 0x45B4251A01Bb6AE0a20824b5C2f6e604fb2A86c9
        );
        pinned[56] = TokenAddressPin(
            "tIFX", 0x4A4a69348C2e68051aB69CA4cbC4C09776Cc97aD, 0x3C6bAea38F7e59058275F3A83751661A3993e5Aa
        );
        pinned[57] = TokenAddressPin(
            "tSOI", 0x820bDa5b751CDb0B239EF5ce2Fe5F07ef54e0f6f, 0x12e658902E38FefB6e5C9c3558Dc5a0040E344f0
        );
        pinned[58] = TokenAddressPin(
            "tTPRO", 0x22c8715D479756D41F1A14647d420Ec02E8ed7c9, 0xf70acb00989525916192f872785aCD1E6f9f261a
        );
        pinned[59] = TokenAddressPin(
            "tUSTEST", 0x9c0da6860b020162FFbA845F0BE691f067d9a3Aa, 0x2c9CCA452C46afC5Abd6F93365F1a15B127affcc
        );
        pinned[60] = TokenAddressPin(
            "tEUTEST", 0x03b485fb0CA2018Fa58EB9D5fD873ad09440A996, 0x5449aE1B95023502b5Cbf811b3202755116540C8
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

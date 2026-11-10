// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    LibRainDeployRegistryBeaconProxy,
    RegistryBeaconProxyParams
} from "rain-factory-0.2.11/src/lib/LibRainDeployRegistryBeaconProxy.sol";

import {LibProdTokenConfig, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibProdTokenParams} from "../../../src/lib/LibProdTokenParams.sol";

/// The wrapper address a V6 row deploys at, pinned by its asset id; the wrapper address commits to the token address.
struct PinnedWrapperAddress {
    string assetId;
    address wrapper;
}

/// @title LibProdTokenParamsAddressesTest
/// @notice Every V6 row still derives the wrapper address pinned for its asset id. The wrapper address commits to the
/// token address, so a dependency bump or a change to the token params cannot move a V6 token or wrapper unseen.
/// @dev A new V6 row adds its pin here, checked with the clone factory's on-chain `predictRegistryBeaconProxyAddress`
/// (`WRAPPER_BEACON_NAME`, `abi.encode(token)` of its `listing.json` token, salt `keccak256(bytes(assetId))`).
/// An existing pin is never edited to match a new derivation.
contract LibProdTokenParamsAddressesTest is Test {
    /// The pinned addresses of the production V6 rows, in table order.
    function productionAddresses() internal pure returns (PinnedWrapperAddress[] memory) {
        PinnedWrapperAddress[] memory pins = new PinnedWrapperAddress[](59);
        pins[0] = PinnedWrapperAddress({assetId: "US5949724083", wrapper: 0x3c56454bdC40E77194aD7c7e11fc69C0759ad751});
        pins[1] = PinnedWrapperAddress({assetId: "US88160R1014", wrapper: 0x2CBe3C1F4002850E70B8B185FB1fBe100061F3D4});
        pins[2] = PinnedWrapperAddress({assetId: "US19260Q1076", wrapper: 0xFCd19DCac83baE7414adf86C2ED60cB6cacD56d2});
        pins[3] = PinnedWrapperAddress({assetId: "US78464A8541", wrapper: 0x4B11EF2420b18D493441e1339bF0be60e3B0CDA3});
        pins[4] = PinnedWrapperAddress({assetId: "US0032641088", wrapper: 0x86A846CA9715f667112522e81dd457c253eBBAD5});
        pins[5] = PinnedWrapperAddress({assetId: "US1725731079", wrapper: 0x97CA86AE710f3c3b286b5CD878212539E9fb0Cc6});
        pins[6] = PinnedWrapperAddress({assetId: "US67066G1040", wrapper: 0x8171e4a267F56F8C98859997836FA2218f0d0A42});
        pins[7] = PinnedWrapperAddress({assetId: "US4642852044", wrapper: 0x1d89762E11f8Efb0632f5857C3A560D7523858e4});
        pins[8] = PinnedWrapperAddress({assetId: "US0032601066", wrapper: 0x682BF8911f873b228C428037f94B1d74E9258BC7});
        pins[9] = PinnedWrapperAddress({assetId: "US0231351067", wrapper: 0x3FD03812302C91F1601E6BaD3aC179f114765401});
        pins[10] = PinnedWrapperAddress({assetId: "US09175A2069", wrapper: 0xdEFB5B5BD5bD4B5077d1E99C848844C8D010BFe1});
        pins[11] = PinnedWrapperAddress({assetId: "US46436E4787", wrapper: 0xc0765320A62E0fE62B68d13D35843De019b327Ab});
        pins[12] = PinnedWrapperAddress({assetId: "US46436E7186", wrapper: 0x6322CBa47711C37C37875DAD04892d89890A49a9});
        pins[13] = PinnedWrapperAddress({assetId: "US46138G6492", wrapper: 0x6E39285B91A5b6aE08389a156916443C7132ffAa});
        pins[14] = PinnedWrapperAddress({assetId: "US9220428588", wrapper: 0x3a0Bedb350c4A240632D4B1cD21D61A8dD38F8d8});
        pins[15] = PinnedWrapperAddress({assetId: "US00214Q1040", wrapper: 0x3399D533cedAc5a0f0d2BEb8E5652b77D48cD0d4});
        pins[16] = PinnedWrapperAddress({assetId: "US84615Q1031", wrapper: 0xBE587AAA41f41d539e7E51c5f996d8f4DAEA07B4});
        pins[17] = PinnedWrapperAddress({assetId: "US21037T1097", wrapper: 0x062Cb4Aaf689eC9D6e74992bf6809b30e16345C8});
        pins[18] = PinnedWrapperAddress({assetId: "US77926X3200", wrapper: 0x7c04C06B27877a371f1d0544434C81463B7E57EC});
        pins[19] = PinnedWrapperAddress({assetId: "US8740391003", wrapper: 0xC96d864A054827AFF177ECf157318027E601242a});
        pins[20] = PinnedWrapperAddress({assetId: "US78392B2060", wrapper: 0xcEd678a2b342b6604F1Fa5f803c9e5a5bb752A7b});
        pins[21] = PinnedWrapperAddress({assetId: "USN070592100", wrapper: 0xFa6E88c5deFf457675712831DF9eadfbe7015a2f});
        pins[22] = PinnedWrapperAddress({assetId: "US5951121038", wrapper: 0x8002b810ddad6576c123bFD334AcfF8bE935Bc98});
        pins[23] = PinnedWrapperAddress({assetId: "US0079031078", wrapper: 0x7B20f437835990822AD4fC1Fd9bfFe2425549C03});
        pins[24] = PinnedWrapperAddress({assetId: "US11135F1012", wrapper: 0xB844F9b629b59eF8E09d6a202196e74F9A6D26b0});
        pins[25] = PinnedWrapperAddress({assetId: "US0382221051", wrapper: 0x78cB459fCbfE57eC88079F846eB5f88619c26e39});
        pins[26] = PinnedWrapperAddress({assetId: "US5128073062", wrapper: 0xA1157E04a05E3707481d4D1216dFB3f5294F92A4});
        pins[27] = PinnedWrapperAddress({assetId: "US8740541094", wrapper: 0x84D08497612D770F4A964C99a5f40ab8256D640c});
        pins[28] = PinnedWrapperAddress({assetId: "US7731211089", wrapper: 0xc7874FFC73b1321f771bEB2e2cacEFd5a69a189e});
        pins[29] = PinnedWrapperAddress({assetId: "US02079K3059", wrapper: 0x6050EDe83576f1e97494Ce75346609123D44765d});
        pins[30] = PinnedWrapperAddress({assetId: "US0378331005", wrapper: 0xAEA02CDD65B3EcCB1A04aA6E752521B5c30Ea76F});
        pins[31] = PinnedWrapperAddress({assetId: "US5949181045", wrapper: 0x6b5C2475B5529149A9e02e4D46EF4429d6fbC90F});
        pins[32] = PinnedWrapperAddress({assetId: "US5324571083", wrapper: 0x6b5b7C5D597C0878998d2e40c5b33BcBA021E26C});
        pins[33] = PinnedWrapperAddress({assetId: "US72201B1017", wrapper: 0x7cDf0518ACe487d36DB579Bbb2908e5D079D04d5});
        pins[34] = PinnedWrapperAddress({assetId: "US4581401001", wrapper: 0xB7a0871BDA8Cf822005b2e948b53DeE72794E297});
        pins[35] = PinnedWrapperAddress({assetId: "US7707001027", wrapper: 0xf2defF2012471867bEbAb026eF5F824e132AeE14});
        pins[36] = PinnedWrapperAddress({assetId: "US68389X1054", wrapper: 0xc6abeE839759Af823c1a2Fb4Dd056B6a871a8B66});
        pins[37] = PinnedWrapperAddress({assetId: "US86800U3023", wrapper: 0x71fecD4EeC9b1077FD7437E7eD74F536b93C26F5});
        pins[38] = PinnedWrapperAddress({assetId: "US01609W1027", wrapper: 0x41ed3287E177C77e5F02893234E4114b4d236548});
        pins[39] = PinnedWrapperAddress({assetId: "US74347X8314", wrapper: 0xbD53e1D2df09b3208d51de0d55d1786dD0daB719});
        pins[40] = PinnedWrapperAddress({assetId: "US35472T1016", wrapper: 0x3A188E340bAFdc2AFdbF0f24cE91f630987Cc07f});
        pins[41] = PinnedWrapperAddress({assetId: "US15675D1037", wrapper: 0xa462559640dd4C794C858CD6bf0e7f1Be7f9c040});
        pins[42] = PinnedWrapperAddress({assetId: "US5801351017", wrapper: 0xC84FF7C2710C8693F3a34Ec729245dBb90Fc7a23});
        pins[43] = PinnedWrapperAddress({assetId: "US6541061031", wrapper: 0x4d54e131472C22E3a50102DCa51d42CEA9155E71});
        pins[44] = PinnedWrapperAddress({assetId: "US39854F1012", wrapper: 0x18fD5F41F0f41C81c3780668A34095cBb97B493c});
        pins[45] = PinnedWrapperAddress({assetId: "US50101L1061", wrapper: 0x4cB9D2cDA57c7DC4cd4141aeC7Da3F57B6c69A17});
        pins[46] = PinnedWrapperAddress({assetId: "US72814P1093", wrapper: 0x23b5F6b9F1318E2A53AC06d0c118a179b3c3aac9});
        pins[47] = PinnedWrapperAddress({assetId: "US8905161076", wrapper: 0xD334D52D24A7ADfA7e4AB8829EBCFe1534D20334});
        pins[48] = PinnedWrapperAddress({assetId: "US95058W1009", wrapper: 0x976e02343f331883E2eD98906A792cA633EA1cBd});
        pins[49] = PinnedWrapperAddress({assetId: "KYG3302D2024", wrapper: 0xa4B5Cb63B7A995aF638E96C12D99F2B651A730c1});
        pins[50] = PinnedWrapperAddress({assetId: "US01675A2087", wrapper: 0x82e2bF3912c8fd27E10fC3344F154d2325E69436});
        pins[51] = PinnedWrapperAddress({assetId: "US78462F1030", wrapper: 0xA35929dBd585626b5528480FfeeBE075e2F3Ace5});
        pins[52] = PinnedWrapperAddress({assetId: "US81720R6045", wrapper: 0x298233482cf1c390D0A73BB0951fb2a6fb915e99});
        pins[53] = PinnedWrapperAddress({assetId: "US9311421039", wrapper: 0xE00e8092d9D6095341FC0924D32B38340405E0ba});
        pins[54] = PinnedWrapperAddress({assetId: "FR0000121014", wrapper: 0xeD671Fc549d7E16e69e8122a6Ea5A01B99eB75bf});
        pins[55] = PinnedWrapperAddress({assetId: "US2546871060", wrapper: 0x587352883fb1Adf7dDE0aAcB58e76924fD320903});
        pins[56] = PinnedWrapperAddress({assetId: "DE0006231004", wrapper: 0xaE891d09dA16B6225B441333Cd2Aaf54e2437D41});
        pins[57] = PinnedWrapperAddress({assetId: "FR0013227113", wrapper: 0x458361eDDc4e684410Bef136Bf4707C25c897f8E});
        pins[58] = PinnedWrapperAddress({assetId: "IT0005482333", wrapper: 0x7514457F689296F9e91e026a5ba2b09Ce167da6e});
        return pins;
    }

    /// The pinned addresses of the two test-token rows.
    function testTokenAddresses() internal pure returns (PinnedWrapperAddress[] memory) {
        PinnedWrapperAddress[] memory pins = new PinnedWrapperAddress[](2);
        pins[0] = PinnedWrapperAddress({assetId: "ST0XTESTUS", wrapper: 0x082C143DfFcAd39677d92365becAe4032478659E});
        pins[1] = PinnedWrapperAddress({assetId: "ST0XTESTEU", wrapper: 0x43A05429539D1F0a399Efb1Cc0A2361F6fF1c268});
        return pins;
    }

    /// Each row of `configs` derives the pinned wrapper of the same asset id, in the same order.
    function checkAddresses(TokenConfig[] memory configs, PinnedWrapperAddress[] memory pinned) internal pure {
        assertEq(configs.length, pinned.length, "pin every V6 row in productionAddresses or testTokenAddresses");
        RegistryBeaconProxyParams[] memory wrappers = LibProdTokenParams.wrapperParams(configs);
        for (uint256 i = 0; i < configs.length; i++) {
            assertEq(configs[i].assetId, pinned[i].assetId, "asset id");
            assertEq(
                LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(wrappers[i]),
                pinned[i].wrapper,
                string.concat(configs[i].assetId, " wrapper")
            );
        }
    }

    function testProductionV6AddressesArePinned() external pure {
        checkAddresses(LibProdTokenConfig.v6TokenConfigs(), productionAddresses());
    }

    function testTestTokenAddressesArePinned() external pure {
        checkAddresses(LibProdTokenConfig.testTokenConfigs(), testTokenAddresses());
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IOwnable} from "../interface/IOwnable.sol";
import {IAuthorisable} from "../interface/IAuthorisable.sol";
import {LibMigrationInvariant} from "./LibMigrationInvariant.sol";

/// @notice One production token's contract triple on a single chain, keyed
/// by the underlying ticker. The underlying symbol (e.g. "MSTR", not
/// "tMSTR" / "wtMSTR") is the chain-agnostic join key: it matches the
/// issuer-side asset identity, so cross-chain checks pair instances by
/// `underlying` and then compare the on-chain `name()` / `symbol()` /
/// `decimals()` read from each chain's contracts.
/// @param underlying The underlying ticker the token set wraps.
/// @param receipt The ERC-1155 receipt contract.
/// @param receiptVault The ERC-20 receipt vault (tStock).
/// @param wrappedTokenVault The ERC-4626 wrapped token vault (wtStock).
struct TokenInstance {
    string underlying;
    address receipt;
    address receiptVault;
    address wrappedTokenVault;
}

/// @notice A production receipt vault's `owner()` does not match the owner
/// the uniform-ownership invariant expected every vault to share. Surfaces
/// the exact vault address that breaks the invariant rather than a generic
/// mismatch.
/// @param vault The receipt vault whose owner was read.
/// @param expected The address every vault is expected to report as
/// `owner()`.
/// @param actual The owner address returned by `vault.owner()`.
error ReceiptVaultOwnerMismatch(address vault, address expected, address actual);

/// @notice A production receipt vault's `authorizer()` does not match the
/// authoriser every vault is expected to share. Surfaces the exact vault
/// that breaks the uniform-authoriser invariant.
/// @param vault The receipt vault whose authoriser was read.
/// @param expected The authoriser address every vault is expected to share.
/// @param actual The authoriser address returned by `vault.authorizer()`.
error ReceiptVaultAuthoriserMismatch(address vault, address expected, address actual);

/// @title LibTokenInvariants
/// @notice Reusable token-side uniformity invariants for the ST0x
/// production receipt vaults on Base. Each assertion iterates the vault
/// list emitted by `productionReceiptVaults` and either
/// returns silently when the invariant holds against the live chain state
/// or reverts with a typed error that pinpoints the offending vault.
/// @dev These are token-side prod invariants: a receipt vault's owner and
/// authoriser uniformity is a property of the token deployment, not of the
/// Safe multisig. `LibInvariants.assertAll` composes this lib's `assertAll`
/// alongside `LibSafeInvariants.assertAll` so consumers asserting the full
/// production state get both. Individual asserts are also callable
/// standalone for focused drift detection.
library LibTokenInvariants {
    // =========================================================================
    // Production token instance addresses on Base. Each token set is a
    // beacon proxy triple deployed via V1 OffchainAssetReceiptVaultBeaconSetDeployer
    // + V1 StoxWrappedTokenVaultBeaconSetDeployer: a receipt (ERC-1155), a
    // receipt vault (ERC-20), and a wrapped token vault (ERC-4626).
    // =========================================================================

    // ---- tMSTR / wtMSTR — MicroStrategy Incorporated ST0x ----
    /// https://basescan.org/address/0x1c1fEF6f7b8e576219554b1d11c8aF29D00C0cEC
    address internal constant MSTR_RECEIPT = address(0x1c1fEF6f7b8e576219554b1d11c8aF29D00C0cEC);
    /// https://basescan.org/address/0x013b782F402d61aa1004CCA95b9f5Bb402c9d5FE
    address internal constant MSTR_RECEIPT_VAULT = address(0x013b782F402d61aa1004CCA95b9f5Bb402c9d5FE);
    /// https://basescan.org/address/0xFF05E1bD696900dc6A52CA35Ca61Bb1024eDa8e2
    address internal constant MSTR_WRAPPED_TOKEN_VAULT = address(0xFF05E1bD696900dc6A52CA35Ca61Bb1024eDa8e2);

    // ---- tTSLA / wtTSLA — Tesla Inc ST0x ----
    /// https://basescan.org/address/0x660923230fAA859622711a5fC80f532dd588b125
    address internal constant TSLA_RECEIPT = address(0x660923230fAA859622711a5fC80f532dd588b125);
    /// https://basescan.org/address/0x4E169cD2Ab4f82640a8c65C68feD55863866fDB0
    address internal constant TSLA_RECEIPT_VAULT = address(0x4E169cD2Ab4f82640a8c65C68feD55863866fDB0);
    /// https://basescan.org/address/0x219A8d384a10BF19b9f24cB5cC53F79Dd0e5A03D
    address internal constant TSLA_WRAPPED_TOKEN_VAULT = address(0x219A8d384a10BF19b9f24cB5cC53F79Dd0e5A03D);

    // ---- tCOIN / wtCOIN — Coinbase Global Inc ST0x ----
    /// https://basescan.org/address/0xBA1B8836A5510815e96103F067715b7CCC7c2E0E
    address internal constant COIN_RECEIPT = address(0xBA1B8836A5510815e96103F067715b7CCC7c2E0E);
    /// https://basescan.org/address/0x626757e6F50675D17fcAd312E82f989aE7A23d38
    address internal constant COIN_RECEIPT_VAULT = address(0x626757e6F50675D17fcAd312E82f989aE7A23d38);
    /// https://basescan.org/address/0x5cDa0E1CA4ce2af96315f7F8963C85399c172204
    address internal constant COIN_WRAPPED_TOKEN_VAULT = address(0x5cDa0E1CA4ce2af96315f7F8963C85399c172204);

    // ---- tSPYM / wtSPYM — State Street SPDR Portfolio S&P 500 ETF ST0x ----
    /// https://basescan.org/address/0x957056dD6e2E594742E36675e8AA5A567163E5bd
    address internal constant SPYM_RECEIPT = address(0x957056dD6e2E594742E36675e8AA5A567163E5bd);
    /// https://basescan.org/address/0x8Fdf41116F755771Bfe0747D5F8C3711D5DEbfBb
    address internal constant SPYM_RECEIPT_VAULT = address(0x8Fdf41116F755771Bfe0747D5F8C3711D5DEbfBb);
    /// https://basescan.org/address/0x31C2C14134e6E3B7ef9478297F199331133Fc2d8
    address internal constant SPYM_WRAPPED_TOKEN_VAULT = address(0x31C2C14134e6E3B7ef9478297F199331133Fc2d8);

    // ---- tSIVR / wtSIVR — abrdn Physical Silver Shares ETF ST0x ----
    /// https://basescan.org/address/0x053F52109a3439b4F292056D2DceC0486B544e82
    address internal constant SIVR_RECEIPT = address(0x053F52109a3439b4F292056D2DceC0486B544e82);
    /// https://basescan.org/address/0x58cE5024B89B4f73C27814C0f0aBbEa331C99Be8
    address internal constant SIVR_RECEIPT_VAULT = address(0x58cE5024B89B4f73C27814C0f0aBbEa331C99Be8);
    /// https://basescan.org/address/0xEB7F3E4093C9d68253b6104FbbfF561F3eC0442F
    address internal constant SIVR_WRAPPED_TOKEN_VAULT = address(0xEB7F3E4093C9d68253b6104FbbfF561F3eC0442F);

    // ---- tCRCL / wtCRCL — Circle Internet Group Inc ST0x ----
    /// https://basescan.org/address/0xd508B97975fBE04E62bFf18959549b046bD8FA78
    address internal constant CRCL_RECEIPT = address(0xd508B97975fBE04E62bFf18959549b046bD8FA78);
    /// https://basescan.org/address/0x38Eb797892ED71Da69bDc27A456A7c83Ff813b52
    address internal constant CRCL_RECEIPT_VAULT = address(0x38Eb797892ED71Da69bDc27A456A7c83Ff813b52);
    /// https://basescan.org/address/0x8AFba81DEc38DE0A18E2Df5E1967a7493651eebf
    address internal constant CRCL_WRAPPED_TOKEN_VAULT = address(0x8AFba81DEc38DE0A18E2Df5E1967a7493651eebf);

    // ---- tNVDA / wtNVDA — NVIDIA Corporation ST0x ----
    /// https://basescan.org/address/0x8Dd4c6f08E446075879310AFae8167CC4DE2f805
    address internal constant NVDA_RECEIPT = address(0x8Dd4c6f08E446075879310AFae8167CC4DE2f805);
    /// https://basescan.org/address/0x7271A3C91Bb6070eD09333B84a815949D4f16d14
    address internal constant NVDA_RECEIPT_VAULT = address(0x7271A3C91Bb6070eD09333B84a815949D4f16d14);
    /// https://basescan.org/address/0xFb5B41acdbA20a3230F84BE995173CFb98b8D6E7
    address internal constant NVDA_WRAPPED_TOKEN_VAULT = address(0xFb5B41acdbA20a3230F84BE995173CFb98b8D6E7);

    // ---- tIAU / wtIAU — iShares Gold Trust ST0x ----
    /// https://basescan.org/address/0x9E128159ff53Ce113df52D760C032DD65DDb0E64
    address internal constant IAU_RECEIPT = address(0x9E128159ff53Ce113df52D760C032DD65DDb0E64);
    /// https://basescan.org/address/0x9A507314EA2a6C5686C0D07BfecB764dCF324dFF
    address internal constant IAU_RECEIPT_VAULT = address(0x9A507314EA2a6C5686C0D07BfecB764dCF324dFF);
    /// https://basescan.org/address/0x1E46d7eFef64A833AFB1CD49299a7AD5B439f4d8
    address internal constant IAU_WRAPPED_TOKEN_VAULT = address(0x1E46d7eFef64A833AFB1CD49299a7AD5B439f4d8);

    // ---- tPPLT / wtPPLT — abrdn Physical Platinum Shares ETF ST0x ----
    /// https://basescan.org/address/0x61b5a0424cD3adcd3b312619fC58B6fCeFA1ECb6
    address internal constant PPLT_RECEIPT = address(0x61b5a0424cD3adcd3b312619fC58B6fCeFA1ECb6);
    /// https://basescan.org/address/0x1f17523b147CcC2A2328c0F014f6d49c479ea063
    address internal constant PPLT_RECEIPT_VAULT = address(0x1f17523b147CcC2A2328c0F014f6d49c479ea063);
    /// https://basescan.org/address/0x82f5BAEE1076334357a34A19E04f7c282D51cE47
    address internal constant PPLT_WRAPPED_TOKEN_VAULT = address(0x82f5BAEE1076334357a34A19E04f7c282D51cE47);

    // ---- tAMZN / wtAMZN — Amazon.com Inc ST0x ----
    /// https://basescan.org/address/0x3C4895df971e5c1fDCa81bF74aDb8eeE94F24721
    address internal constant AMZN_RECEIPT = address(0x3C4895df971e5c1fDCa81bF74aDb8eeE94F24721);
    /// https://basescan.org/address/0x466CB2e46Fa1AfC0AB5e22274B34d0391db18eFd
    address internal constant AMZN_RECEIPT_VAULT = address(0x466CB2e46Fa1AfC0AB5e22274B34d0391db18eFd);
    /// https://basescan.org/address/0x997baE3EC193a249596d3708C3fAB7C501Bb8a53
    address internal constant AMZN_WRAPPED_TOKEN_VAULT = address(0x997baE3EC193a249596d3708C3fAB7C501Bb8a53);

    // ---- tBMNR / wtBMNR — Bitmine Immersion Technologies, Inc ST0x ----
    /// https://basescan.org/address/0x67aeAFD8c274F62933fEc34E8c0724189AaD01fc
    address internal constant BMNR_RECEIPT = address(0x67aeAFD8c274F62933fEc34E8c0724189AaD01fc);
    /// https://basescan.org/address/0xfBde45dF60249203b12148452fC77C3B5F811eB2
    address internal constant BMNR_RECEIPT_VAULT = address(0xfBde45dF60249203b12148452fC77C3B5F811eB2);
    /// https://basescan.org/address/0x2512EC661f0bA089c275EA105E31bAD6FcFcf319
    address internal constant BMNR_WRAPPED_TOKEN_VAULT = address(0x2512EC661f0bA089c275EA105E31bAD6FcFcf319);

    // ---- tIBHG / wtIBHG — iShares iBonds 2027 Term High Yield and Income ETF ST0x ----
    /// https://basescan.org/address/0xE603De6450555cEf32be7e666eEd70fddDa13e1e
    address internal constant IBHG_RECEIPT = address(0xE603De6450555cEf32be7e666eEd70fddDa13e1e);
    /// https://basescan.org/address/0x3c0F093aa1eD511910279b2C8d56eF5c96f1a6cF
    address internal constant IBHG_RECEIPT_VAULT = address(0x3c0F093aa1eD511910279b2C8d56eF5c96f1a6cF);
    /// https://basescan.org/address/0xf73894603e92d6f91b1f156e98cca38fd1f78dbf
    address internal constant IBHG_WRAPPED_TOKEN_VAULT = address(0xF73894603e92D6f91B1f156e98Cca38Fd1F78dBf);

    // ---- tSGOV / wtSGOV — iShares 0-3 Month Treasury Bond ETF ST0x ----
    /// https://basescan.org/address/0x5c28F1Dd98dC2D61F289545c3be85cafdb4cB111
    address internal constant SGOV_RECEIPT = address(0x5c28F1Dd98dC2D61F289545c3be85cafdb4cB111);
    /// https://basescan.org/address/0xc941C1506B7555Ba8C506Fb6c9b9CC259902d612
    address internal constant SGOV_RECEIPT_VAULT = address(0xc941C1506B7555Ba8C506Fb6c9b9CC259902d612);
    /// https://basescan.org/address/0x78c31580c97101694c70022c83d570150c11e935
    address internal constant SGOV_WRAPPED_TOKEN_VAULT = address(0x78c31580c97101694C70022c83D570150c11e935);

    // ---- tQQQM / wtQQQM — Invesco NASDAQ 100 ETF ST0x ----
    /// https://basescan.org/address/0x6Dcca0af274EB97f15ECc22d01a4F980f23F5E56
    address internal constant QQQM_RECEIPT = address(0x6Dcca0af274EB97f15ECc22d01a4F980f23F5E56);
    /// https://basescan.org/address/0x09ee803ba675052e10a54bfc8e18c0f67793056b
    address internal constant QQQM_RECEIPT_VAULT = address(0x09eE803bA675052e10A54BFc8E18c0f67793056b);
    /// https://basescan.org/address/0x823FF7Bbde2869aAe73A6CD53e7f614442836757
    address internal constant QQQM_WRAPPED_TOKEN_VAULT = address(0x823FF7Bbde2869aAe73A6CD53e7f614442836757);

    // ---- tVWO / wtVWO — Vanguard Emerging Markets Stock Index Fund ST0x ----
    /// https://basescan.org/address/0x3EC7C053Fd515353Df294B43F4c4d81F76eF0924
    address internal constant VWO_RECEIPT = address(0x3EC7C053Fd515353Df294B43F4c4d81F76eF0924);
    /// https://basescan.org/address/0x0acfea6833c4a3f41bf2fbd736aa9eea547d90ee
    address internal constant VWO_RECEIPT_VAULT = address(0x0acFea6833c4a3f41BF2FBD736aa9eEa547D90Ee);
    /// https://basescan.org/address/0x23ec6886b49D7ab123E9ee8e474D2fa7AB6Cbc2d
    address internal constant VWO_WRAPPED_TOKEN_VAULT = address(0x23ec6886b49D7ab123E9ee8e474D2fa7AB6Cbc2d);

    // ---- tARKK / wtARKK — ARK Innovation ETF ST0x ----
    /// https://basescan.org/address/0x5C497a52857b71538a7b57E6f57322877eD792B2
    address internal constant ARKK_RECEIPT = address(0x5C497a52857b71538a7b57E6f57322877eD792B2);
    /// https://basescan.org/address/0x323804af6f3bb463d688b854667c6870a0fc06ad
    address internal constant ARKK_RECEIPT_VAULT = address(0x323804af6f3Bb463d688B854667C6870A0Fc06aD);
    /// https://basescan.org/address/0x9FfF48B4535AF3765Ac9E1b164720EDc01DF8EE7
    address internal constant ARKK_WRAPPED_TOKEN_VAULT = address(0x9FfF48B4535AF3765Ac9E1b164720EDc01DF8EE7);

    // ---- tSPCX / wtSPCX — Space Exploration Technologies Corp. ST0x ----
    /// https://basescan.org/address/0xba81B21F8a22bD99900E00Ed1373EC77C0772F55
    address internal constant SPCX_RECEIPT = address(0xba81B21F8a22bD99900E00Ed1373EC77C0772F55);
    /// https://basescan.org/address/0xc585AeB8B76c5F5e4215470A7625258e86ED7746
    address internal constant SPCX_RECEIPT_VAULT = address(0xc585AeB8B76c5F5e4215470A7625258e86ED7746);
    /// https://basescan.org/address/0x19F89aaEf8a93f38A974beca9776f09aB844887F
    address internal constant SPCX_WRAPPED_TOKEN_VAULT = address(0x19F89aaEf8a93f38A974beca9776f09aB844887F);

    // ---- tCEG / wtCEG — Constellation Energy Corporation ST0x ----
    /// https://basescan.org/address/0xc6bc19DF197cCd0DB4c02cCd6AAFf7B2Ce698e08
    address internal constant CEG_RECEIPT = address(0xc6bc19DF197cCd0DB4c02cCd6AAFf7B2Ce698e08);
    /// https://basescan.org/address/0x9a5D3cAeC90b0332b18C0B93fEF42F3F8C918289
    address internal constant CEG_RECEIPT_VAULT = address(0x9a5D3cAeC90b0332b18C0B93fEF42F3F8C918289);
    /// https://basescan.org/address/0x3aF952888Cd89DAD3e8AF67cf4b7E740B36829C3
    address internal constant CEG_WRAPPED_TOKEN_VAULT = address(0x3aF952888Cd89DAD3e8AF67cf4b7E740B36829C3);

    // ---- tDRAM / wtDRAM — Roundhill Memory ETF ST0x ----
    /// https://basescan.org/address/0x728734768a772c137A5364b10e61943De13921C4
    address internal constant DRAM_RECEIPT = address(0x728734768a772c137A5364b10e61943De13921C4);
    /// https://basescan.org/address/0x96DE077262609298CD891E4Ab21bd34837dE33aB
    address internal constant DRAM_RECEIPT_VAULT = address(0x96DE077262609298CD891E4Ab21bd34837dE33aB);
    /// https://basescan.org/address/0x1A91Df4a970EBaB1bB4AF32Eb6d10509028eE4b8
    address internal constant DRAM_WRAPPED_TOKEN_VAULT = address(0x1A91Df4a970EBaB1bB4AF32Eb6d10509028eE4b8);

    // ---- tTSM / wtTSM — Taiwan Semiconductor Manufacturing Company ST0x ----
    /// https://basescan.org/address/0x6553f9A5352ec3ca808138eaB56FE4cC496eA5A9
    address internal constant TSM_RECEIPT = address(0x6553f9A5352ec3ca808138eaB56FE4cC496eA5A9);
    /// https://basescan.org/address/0x7001e2974F775f0Fd73a3D2e5914e591f3EC3fBB
    address internal constant TSM_RECEIPT_VAULT = address(0x7001e2974F775f0Fd73a3D2e5914e591f3EC3fBB);
    /// https://basescan.org/address/0x71C66449d2528E23514A9c197BFD55Ae9DB3B714
    address internal constant TSM_WRAPPED_TOKEN_VAULT = address(0x71C66449d2528E23514A9c197BFD55Ae9DB3B714);

    // ---- tSKHY / wtSKHY — SK hynix Inc. ADR ST0x ----
    /// https://basescan.org/address/0xE26105d49e57cEd5Ce83d20Ca5f04C3B0dCC876C
    address internal constant SKHY_RECEIPT = address(0xE26105d49e57cEd5Ce83d20Ca5f04C3B0dCC876C);
    /// https://basescan.org/address/0x4DBA41f0feb390F208a85e96168fF5d8aC2b6F5c
    address internal constant SKHY_RECEIPT_VAULT = address(0x4DBA41f0feb390F208a85e96168fF5d8aC2b6F5c);
    /// https://basescan.org/address/0xFcD17aC4c4BF6a72c93018096F3fC09e66573Ff9
    address internal constant SKHY_WRAPPED_TOKEN_VAULT = address(0xFcD17aC4c4BF6a72c93018096F3fC09e66573Ff9);

    // ---- tASML / wtASML — ASML Holding N.V. New York Registry Shares ST0x ----
    /// https://basescan.org/address/0x17021e305D28c4CfA8ec02817ad22B2ef432dC85
    address internal constant ASML_RECEIPT = address(0x17021e305D28c4CfA8ec02817ad22B2ef432dC85);
    /// https://basescan.org/address/0x722Cb373f1871A176fb5DC3953046f2EAE22F619
    address internal constant ASML_RECEIPT_VAULT = address(0x722Cb373f1871A176fb5DC3953046f2EAE22F619);
    /// https://basescan.org/address/0x8200c6d9AB9E02A25D7F2099244C476d99a085ef
    address internal constant ASML_WRAPPED_TOKEN_VAULT = address(0x8200c6d9AB9E02A25D7F2099244C476d99a085ef);

    // ---- tMU / wtMU — Micron Technology, Inc. ST0x ----
    /// https://basescan.org/address/0x0CC8b07E5bb99Ef8C227a6C995c907b8448ED9A8
    address internal constant MU_RECEIPT = address(0x0CC8b07E5bb99Ef8C227a6C995c907b8448ED9A8);
    /// https://basescan.org/address/0x7d89a2DFfDaF9f48A64337C725D925381b431aE2
    address internal constant MU_RECEIPT_VAULT = address(0x7d89a2DFfDaF9f48A64337C725D925381b431aE2);
    /// https://basescan.org/address/0x89EcfE9E0728D6b3c5eb0EE7236f8C6F806C7B56
    address internal constant MU_WRAPPED_TOKEN_VAULT = address(0x89EcfE9E0728D6b3c5eb0EE7236f8C6F806C7B56);

    // ---- tAMD / wtAMD — Advanced Micro Devices, Inc. ST0x ----
    /// https://basescan.org/address/0x9A06e971B71334f1003bF7E601E3e1E398fa82A6
    address internal constant AMD_RECEIPT = address(0x9A06e971B71334f1003bF7E601E3e1E398fa82A6);
    /// https://basescan.org/address/0x50b5225409A55B873fD6C2Fd5880AF5a11acE9b1
    address internal constant AMD_RECEIPT_VAULT = address(0x50b5225409A55B873fD6C2Fd5880AF5a11acE9b1);
    /// https://basescan.org/address/0x648042Acd8638E12fEfd51C2b25A9f993f21a612
    address internal constant AMD_WRAPPED_TOKEN_VAULT = address(0x648042Acd8638E12fEfd51C2b25A9f993f21a612);

    // ---- tAVGO / wtAVGO — Broadcom Inc. ST0x ----
    /// https://basescan.org/address/0x36e3612554857751c78FC70A31a9a40B130168c4
    address internal constant AVGO_RECEIPT = address(0x36e3612554857751c78FC70A31a9a40B130168c4);
    /// https://basescan.org/address/0x6088F8ef741AE1f5A61882866f130631b41617E2
    address internal constant AVGO_RECEIPT_VAULT = address(0x6088F8ef741AE1f5A61882866f130631b41617E2);
    /// https://basescan.org/address/0x70A182f481AEF05836666B6CfDbe84dCBCE8AC19
    address internal constant AVGO_WRAPPED_TOKEN_VAULT = address(0x70A182f481AEF05836666B6CfDbe84dCBCE8AC19);

    // ---- tAMAT / wtAMAT — Applied Materials, Inc. ST0x ----
    /// https://basescan.org/address/0xB50Cf64462C87545e89Eeb6Da020ebf5dC971612
    address internal constant AMAT_RECEIPT = address(0xB50Cf64462C87545e89Eeb6Da020ebf5dC971612);
    /// https://basescan.org/address/0x98C02B58b7E65EF5a4262d9536162949e3B2E141
    address internal constant AMAT_RECEIPT_VAULT = address(0x98C02B58b7E65EF5a4262d9536162949e3B2E141);
    /// https://basescan.org/address/0x522DC65c89C9Af4f410BAe01bbf53aF75854a9f9
    address internal constant AMAT_WRAPPED_TOKEN_VAULT = address(0x522DC65c89C9Af4f410BAe01bbf53aF75854a9f9);

    // ---- tLRCX / wtLRCX — Lam Research Corporation ST0x ----
    /// https://basescan.org/address/0xDa588aceE0E45F29dfF1E48988D5108122491388
    address internal constant LRCX_RECEIPT = address(0xDa588aceE0E45F29dfF1E48988D5108122491388);
    /// https://basescan.org/address/0xDdE9346107609A05439A0B59Ab6eD4f7F81a1FBF
    address internal constant LRCX_RECEIPT_VAULT = address(0xDdE9346107609A05439A0B59Ab6eD4f7F81a1FBF);
    /// https://basescan.org/address/0x328B9aFFa511fE26673edBb4fEa37eDaF908A3bc
    address internal constant LRCX_WRAPPED_TOKEN_VAULT = address(0x328B9aFFa511fE26673edBb4fEa37eDaF908A3bc);

    // ---- tTTWO / wtTTWO — Take-Two Interactive Software, Inc. ST0x ----
    /// https://basescan.org/address/0x0162Bd328D45fae647FdA01C33Be54709b314c48
    address internal constant TTWO_RECEIPT = address(0x0162Bd328D45fae647FdA01C33Be54709b314c48);
    /// https://basescan.org/address/0x1a29eD11DF8295D5F3B5F59849FD94caD615E024
    address internal constant TTWO_RECEIPT_VAULT = address(0x1a29eD11DF8295D5F3B5F59849FD94caD615E024);
    /// https://basescan.org/address/0x045Fb493D970f94a54FeaF931033622fC82192e6
    address internal constant TTWO_WRAPPED_TOKEN_VAULT = address(0x045Fb493D970f94a54FeaF931033622fC82192e6);

    /// @notice Returns the 28 production token instance triples on Base, in
    /// the order they were deployed. This is the structured source of truth
    /// the flat `productionReceiptVaults()` accessor derives from; consumers
    /// that need the receipt / wrapped-vault legs or the underlying join key
    /// (cross-chain parity, per-token config checks) iterate this instead.
    /// @return tokens The 28 production token instances on Base.
    function productionTokensBase() internal pure returns (TokenInstance[] memory tokens) {
        tokens = new TokenInstance[](28);
        tokens[0] = TokenInstance("MSTR", MSTR_RECEIPT, MSTR_RECEIPT_VAULT, MSTR_WRAPPED_TOKEN_VAULT);
        tokens[1] = TokenInstance("TSLA", TSLA_RECEIPT, TSLA_RECEIPT_VAULT, TSLA_WRAPPED_TOKEN_VAULT);
        tokens[2] = TokenInstance("COIN", COIN_RECEIPT, COIN_RECEIPT_VAULT, COIN_WRAPPED_TOKEN_VAULT);
        tokens[3] = TokenInstance("SPYM", SPYM_RECEIPT, SPYM_RECEIPT_VAULT, SPYM_WRAPPED_TOKEN_VAULT);
        tokens[4] = TokenInstance("SIVR", SIVR_RECEIPT, SIVR_RECEIPT_VAULT, SIVR_WRAPPED_TOKEN_VAULT);
        tokens[5] = TokenInstance("CRCL", CRCL_RECEIPT, CRCL_RECEIPT_VAULT, CRCL_WRAPPED_TOKEN_VAULT);
        tokens[6] = TokenInstance("NVDA", NVDA_RECEIPT, NVDA_RECEIPT_VAULT, NVDA_WRAPPED_TOKEN_VAULT);
        tokens[7] = TokenInstance("IAU", IAU_RECEIPT, IAU_RECEIPT_VAULT, IAU_WRAPPED_TOKEN_VAULT);
        tokens[8] = TokenInstance("PPLT", PPLT_RECEIPT, PPLT_RECEIPT_VAULT, PPLT_WRAPPED_TOKEN_VAULT);
        tokens[9] = TokenInstance("AMZN", AMZN_RECEIPT, AMZN_RECEIPT_VAULT, AMZN_WRAPPED_TOKEN_VAULT);
        tokens[10] = TokenInstance("BMNR", BMNR_RECEIPT, BMNR_RECEIPT_VAULT, BMNR_WRAPPED_TOKEN_VAULT);
        tokens[11] = TokenInstance("IBHG", IBHG_RECEIPT, IBHG_RECEIPT_VAULT, IBHG_WRAPPED_TOKEN_VAULT);
        tokens[12] = TokenInstance("SGOV", SGOV_RECEIPT, SGOV_RECEIPT_VAULT, SGOV_WRAPPED_TOKEN_VAULT);
        tokens[13] = TokenInstance("QQQM", QQQM_RECEIPT, QQQM_RECEIPT_VAULT, QQQM_WRAPPED_TOKEN_VAULT);
        tokens[14] = TokenInstance("VWO", VWO_RECEIPT, VWO_RECEIPT_VAULT, VWO_WRAPPED_TOKEN_VAULT);
        tokens[15] = TokenInstance("ARKK", ARKK_RECEIPT, ARKK_RECEIPT_VAULT, ARKK_WRAPPED_TOKEN_VAULT);
        tokens[16] = TokenInstance("SPCX", SPCX_RECEIPT, SPCX_RECEIPT_VAULT, SPCX_WRAPPED_TOKEN_VAULT);
        tokens[17] = TokenInstance("CEG", CEG_RECEIPT, CEG_RECEIPT_VAULT, CEG_WRAPPED_TOKEN_VAULT);
        tokens[18] = TokenInstance("DRAM", DRAM_RECEIPT, DRAM_RECEIPT_VAULT, DRAM_WRAPPED_TOKEN_VAULT);
        tokens[19] = TokenInstance("TSM", TSM_RECEIPT, TSM_RECEIPT_VAULT, TSM_WRAPPED_TOKEN_VAULT);
        tokens[20] = TokenInstance("SKHY", SKHY_RECEIPT, SKHY_RECEIPT_VAULT, SKHY_WRAPPED_TOKEN_VAULT);
        tokens[21] = TokenInstance("ASML", ASML_RECEIPT, ASML_RECEIPT_VAULT, ASML_WRAPPED_TOKEN_VAULT);
        tokens[22] = TokenInstance("MU", MU_RECEIPT, MU_RECEIPT_VAULT, MU_WRAPPED_TOKEN_VAULT);
        tokens[23] = TokenInstance("AMD", AMD_RECEIPT, AMD_RECEIPT_VAULT, AMD_WRAPPED_TOKEN_VAULT);
        tokens[24] = TokenInstance("AVGO", AVGO_RECEIPT, AVGO_RECEIPT_VAULT, AVGO_WRAPPED_TOKEN_VAULT);
        tokens[25] = TokenInstance("AMAT", AMAT_RECEIPT, AMAT_RECEIPT_VAULT, AMAT_WRAPPED_TOKEN_VAULT);
        tokens[26] = TokenInstance("LRCX", LRCX_RECEIPT, LRCX_RECEIPT_VAULT, LRCX_WRAPPED_TOKEN_VAULT);
        tokens[27] = TokenInstance("TTWO", TTWO_RECEIPT, TTWO_RECEIPT_VAULT, TTWO_WRAPPED_TOKEN_VAULT);
    }

    /// @notice Returns the production token instance triples on Ethereum
    /// mainnet — the same 28 underlyings as Base, in the same order, so the
    /// two tables pair by index as well as by key.
    ///
    /// **ALL PLACEHOLDERS** (`address(0)`) until the Ethereum token
    /// deployments execute and the post-execution pin PR hydrates every entry
    /// in one reviewed change. Hydration is all-or-nothing across the table:
    /// the multichain issuance cutover is lockstep over the full token set, so
    /// a partially hydrated table is an error state, which the cross-chain
    /// parity suite rejects rather than half-checks.
    /// @return tokens The 28 production token instances on Ethereum.
    function productionTokensEthereum() internal pure returns (TokenInstance[] memory tokens) {
        // PLACEHOLDER TABLE. Every address is `address(0)` until the 28 tokens
        // are deployed on Ethereum and their addresses pinned here (the token
        // pin PR — a per-row literal swap). Laid out as explicit rows mirroring
        // `productionTokensBase()` so the two tables are formatted consistently
        // across chains and the pin diff is a clean per-token change. Order and
        // underlyings MUST match Base row-for-row (the cross-chain parity pin
        // asserts this).
        tokens = new TokenInstance[](28);
        tokens[0] = TokenInstance("MSTR", address(1), address(1), address(1));
        tokens[1] = TokenInstance("TSLA", address(1), address(1), address(1));
        tokens[2] = TokenInstance("COIN", address(1), address(1), address(1));
        tokens[3] = TokenInstance("SPYM", address(1), address(1), address(1));
        tokens[4] = TokenInstance("SIVR", address(1), address(1), address(1));
        tokens[5] = TokenInstance("CRCL", address(1), address(1), address(1));
        tokens[6] = TokenInstance("NVDA", address(1), address(1), address(1));
        tokens[7] = TokenInstance("IAU", address(1), address(1), address(1));
        tokens[8] = TokenInstance("PPLT", address(1), address(1), address(1));
        tokens[9] = TokenInstance("AMZN", address(1), address(1), address(1));
        tokens[10] = TokenInstance("BMNR", address(1), address(1), address(1));
        tokens[11] = TokenInstance("IBHG", address(1), address(1), address(1));
        tokens[12] = TokenInstance("SGOV", address(1), address(1), address(1));
        tokens[13] = TokenInstance("QQQM", address(1), address(1), address(1));
        tokens[14] = TokenInstance("VWO", address(1), address(1), address(1));
        tokens[15] = TokenInstance("ARKK", address(1), address(1), address(1));
        tokens[16] = TokenInstance("SPCX", address(1), address(1), address(1));
        tokens[17] = TokenInstance("CEG", address(1), address(1), address(1));
        tokens[18] = TokenInstance("DRAM", address(1), address(1), address(1));
        tokens[19] = TokenInstance("TSM", address(1), address(1), address(1));
        tokens[20] = TokenInstance("SKHY", address(1), address(1), address(1));
        tokens[21] = TokenInstance("ASML", address(1), address(1), address(1));
        tokens[22] = TokenInstance("MU", address(1), address(1), address(1));
        tokens[23] = TokenInstance("AMD", address(1), address(1), address(1));
        tokens[24] = TokenInstance("AVGO", address(1), address(1), address(1));
        tokens[25] = TokenInstance("AMAT", address(1), address(1), address(1));
        tokens[26] = TokenInstance("LRCX", address(1), address(1), address(1));
        tokens[27] = TokenInstance("TTWO", address(1), address(1), address(1));
    }

    /// @notice Returns the 28 production receipt vault addresses on Base, in
    /// the order they were deployed. Provided so consumers (e.g. invariant
    /// assertions, migration scripts) can iterate without hardcoding the
    /// list inline.
    /// @dev Derived from `productionTokensBase()` so the token table is the
    /// single source of truth and the two accessors cannot drift.
    /// @return vaults The 28 production receipt vault addresses on Base.
    function productionReceiptVaults() internal pure returns (address[] memory vaults) {
        TokenInstance[] memory tokens = productionTokensBase();
        vaults = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            vaults[i] = tokens[i].receiptVault;
        }
    }

    /// @notice Assert that every production receipt vault reports the same
    /// `owner()`. Iterates `productionReceiptVaults` and
    /// reverts with `ReceiptVaultOwnerMismatch` on the first vault whose
    /// `owner()` diverges from `expectedOwner`, surfacing the offending
    /// vault.
    /// @dev A divergent owner means a token is controlled by a different
    /// account than the rest of the system — the class of inconsistency
    /// this invariant exists to prevent. Composed into `assertAll` (with
    /// the Safe as the expected owner) and through there into
    /// `LibInvariants.assertAll`; also callable standalone.
    /// @param expectedOwner The address every production receipt vault is
    /// expected to report as `owner()`.
    function assertUniformOwnership(address expectedOwner) internal view {
        assertUniformOwnership(productionTokensBase(), expectedOwner);
    }

    /// @notice Chain-parametric `assertUniformOwnership`: assert every
    /// receipt vault in the supplied token table reports `expectedOwner`.
    /// The Base no-arg-table overload delegates here with
    /// `productionTokensBase()`; a multichain caller passes another chain's
    /// table so the same uniform-ownership invariant runs against every
    /// chain with that chain's vaults and Safe.
    /// @param tokens The token table whose receipt vaults are checked.
    /// @param expectedOwner The address every receipt vault must report as
    /// `owner()`.
    function assertUniformOwnership(TokenInstance[] memory tokens, address expectedOwner) internal view {
        for (uint256 i = 0; i < tokens.length; i++) {
            address actualOwner = IOwnable(tokens[i].receiptVault).owner();
            if (actualOwner != expectedOwner) {
                revert ReceiptVaultOwnerMismatch(tokens[i].receiptVault, expectedOwner, actualOwner);
            }
        }
    }

    /// @notice Assert that every production receipt vault reports the same
    /// authoriser. Iterates `productionReceiptVaults` and
    /// reverts with `ReceiptVaultAuthoriserMismatch` on the first vault whose
    /// `authorizer()` diverges from `expected`, surfacing the offending vault.
    /// @dev A divergent authoriser means a token is gated by a different RBAC
    /// contract than the rest of the system — the class of inconsistency this
    /// invariant exists to prevent. Composed into `assertAll` and through
    /// there into `LibInvariants.assertAll`; also callable standalone.
    /// @param expected The authoriser address every production receipt vault
    /// is expected to share.
    function assertUniformAuthoriser(address expected) internal view {
        assertUniformAuthoriser(productionTokensBase(), expected);
    }

    /// @notice Chain-parametric `assertUniformAuthoriser`: assert every
    /// receipt vault in the supplied token table reports `expected` as its
    /// authoriser. The Base overload delegates here with
    /// `productionTokensBase()`; a multichain caller passes another chain's
    /// table + that chain's authoriser clone.
    /// @param tokens The token table whose receipt vaults are checked.
    /// @param expected The authoriser every receipt vault must share.
    function assertUniformAuthoriser(TokenInstance[] memory tokens, address expected) internal view {
        for (uint256 i = 0; i < tokens.length; i++) {
            address actual = IAuthorisable(tokens[i].receiptVault).authorizer();
            if (actual != expected) {
                revert ReceiptVaultAuthoriserMismatch(tokens[i].receiptVault, expected, actual);
            }
        }
    }

    /// @notice Migration-window variant of `assertUniformAuthoriser`:
    /// every production receipt vault's `authorizer()` must be `pre` OR
    /// `post` before `deadline`, and exactly `post` at/after it. Lets the
    /// authoriser-swap invariant merge alongside the swap script instead
    /// of waiting for on-chain execution — both sides of the transition
    /// are cron-covered, and a swap left un-run past the deadline
    /// red-lines via `MigrationDeadlinePassed`.
    /// @dev Each vault is asserted independently, so a half-landed swap
    /// (some vaults on `pre`, some on `post`) passes before the deadline
    /// — the bundle is atomic per Safe execution, but this leg does not
    /// assume that. Any third value trips `MigrationStateDrift`
    /// immediately regardless of the deadline.
    /// @param pre The accepted authoriser before the swap runs.
    /// @param post The accepted authoriser after the swap runs.
    /// @param deadline Unix timestamp past which only `post` is accepted.
    function assertUniformAuthoriserMigration(address pre, address post, uint256 deadline) internal view {
        address[] memory vaults = productionReceiptVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            LibMigrationInvariant.assertMigration(
                "receiptVault.authorizer()", IAuthorisable(vaults[i]).authorizer(), pre, post, deadline
            );
        }
    }

    /// @notice Full token-side invariant bundle: every production receipt
    /// vault reports the supplied Safe as its `owner()` AND the supplied
    /// authoriser as its `authorizer()`. Pre-flight / post-state hook for
    /// any script touching the production receipt vault set; consumers
    /// asserting the full production state (Safe + token + authoriser)
    /// compose this alongside `LibSafeInvariants.assertAll` and
    /// `LibAuthoriserInvariants.assertAll` via `LibInvariants.assertAll`.
    /// @dev Both legs run last in the composed bundle because each performs
    /// one external call per production token instance and is only
    /// meaningful once the Safe itself has been validated. The authoriser is parameterised rather than
    /// hardcoded so this lib stays free of cross-facet dependencies; the
    /// orchestrator supplies the pinned address.
    /// @param safe The Safe address every production receipt vault is
    /// expected to report as `owner()`.
    /// @param expectedAuthoriser The authoriser address every production
    /// receipt vault is expected to report as `authorizer()`.
    function assertAll(address safe, address expectedAuthoriser) internal view {
        assertAll(productionTokensBase(), safe, expectedAuthoriser);
    }

    /// @notice Chain-parametric token-side bundle: every receipt vault in
    /// the supplied table reports `safe` as `owner()` and
    /// `expectedAuthoriser` as `authorizer()`. The Base overload delegates
    /// here with `productionTokensBase()`; `LibInvariants.assertProductionState`
    /// calls this with each chain's own table so the full-production-state
    /// pre-flight works on every chain.
    /// @param tokens The chain's token table.
    /// @param safe The Safe every receipt vault must report as `owner()`.
    /// @param expectedAuthoriser The authoriser every receipt vault must
    /// report as `authorizer()`.
    function assertAll(TokenInstance[] memory tokens, address safe, address expectedAuthoriser) internal view {
        assertUniformOwnership(tokens, safe);
        assertUniformAuthoriser(tokens, expectedAuthoriser);
    }
}

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

    // ---- tRKLB / wtRKLB — Rocket Lab USA Inc ST0x ----
    /// https://basescan.org/address/0x34Bf3d8DFaa92e554FBCf48135E5d814210DA1dd
    address internal constant RKLB_RECEIPT = address(0x34Bf3d8DFaa92e554FBCf48135E5d814210DA1dd);
    /// https://basescan.org/address/0xf6744Fd94e27c2f58F6110aa9fDC77A87e41766B
    address internal constant RKLB_RECEIPT_VAULT = address(0xf6744Fd94e27c2f58F6110aa9fDC77A87e41766B);
    /// https://basescan.org/address/0xF4f8c66085910d583c01f3b4e44Bf731D4e2c565
    address internal constant RKLB_WRAPPED_TOKEN_VAULT = address(0xF4f8c66085910d583c01f3b4e44Bf731D4e2c565);

    // ---- tGOOGL / wtGOOGL — Alphabet Inc. Class A ST0x ----
    /// https://basescan.org/address/0x85ac79F639C692B2f1290d0994c79eEffF350D00
    address internal constant GOOGL_RECEIPT = address(0x85ac79F639C692B2f1290d0994c79eEffF350D00);
    /// https://basescan.org/address/0x15De944Cd020A18C8E5626fB0F81b36e73956199
    address internal constant GOOGL_RECEIPT_VAULT = address(0x15De944Cd020A18C8E5626fB0F81b36e73956199);
    /// https://basescan.org/address/0x6a2357Df4975C667B171bE53dA6FFe6deBf7030c
    address internal constant GOOGL_WRAPPED_TOKEN_VAULT = address(0x6a2357Df4975C667B171bE53dA6FFe6deBf7030c);

    // ---- tMETA / wtMETA — Meta Platforms, Inc. ST0x ----
    // Deployed 2026-07-27, never launched — absent from registry, logos and Turnkey set; recorded, not pinned.
    // /// https://basescan.org/address/0xffcBEA042a0d55293f9ad0f050CE11f6331C9313
    // address internal constant META_RECEIPT = address(0xffcBEA042a0d55293f9ad0f050CE11f6331C9313);
    // /// https://basescan.org/address/0xAF07a843A6221d3E6540122Fa712DF8541B05E26
    // address internal constant META_RECEIPT_VAULT = address(0xAF07a843A6221d3E6540122Fa712DF8541B05E26);
    // /// https://basescan.org/address/0xd1ddE998d1Cd19B502242FBE14F6CC97bE601E30
    // address internal constant META_WRAPPED_TOKEN_VAULT = address(0xd1ddE998d1Cd19B502242FBE14F6CC97bE601E30);

    // ---- tAAPL / wtAAPL — Apple Inc. ST0x ----
    /// https://basescan.org/address/0x3156EB08c9dd870979f1475C5CFe681b8f6A3b53
    address internal constant AAPL_RECEIPT = address(0x3156EB08c9dd870979f1475C5CFe681b8f6A3b53);
    /// https://basescan.org/address/0xD36056a4a03707D3743fCE4e9C08852820ADcfdC
    address internal constant AAPL_RECEIPT_VAULT = address(0xD36056a4a03707D3743fCE4e9C08852820ADcfdC);
    /// https://basescan.org/address/0x1020EC8Aa3f709a1f3D8705cdBa89b950451bd88
    address internal constant AAPL_WRAPPED_TOKEN_VAULT = address(0x1020EC8Aa3f709a1f3D8705cdBa89b950451bd88);

    // ---- tMSFT / wtMSFT — Microsoft Corporation ST0x ----
    /// https://basescan.org/address/0x6862e34dE9AFE099ca19934fC768A8eB9a906b90
    address internal constant MSFT_RECEIPT = address(0x6862e34dE9AFE099ca19934fC768A8eB9a906b90);
    /// https://basescan.org/address/0x6a071E25fa25653cF15d1ee320eA3df771926Aa0
    address internal constant MSFT_RECEIPT_VAULT = address(0x6a071E25fa25653cF15d1ee320eA3df771926Aa0);
    /// https://basescan.org/address/0x515A3Ac2a6aB590bDFa970caFFFd7fAdC680886E
    address internal constant MSFT_WRAPPED_TOKEN_VAULT = address(0x515A3Ac2a6aB590bDFa970caFFFd7fAdC680886E);

    // ---- tPLTR / wtPLTR — Palantir Technologies Inc. ST0x ----
    // Deployed 2026-07-27, never launched — `owner()` is still the deployer EOA, not the Safe; recorded, not pinned.
    // /// https://basescan.org/address/0x0fa01D10006486f042E55728f14A1A8f70ACa6a3
    // address internal constant PLTR_RECEIPT = address(0x0fa01D10006486f042E55728f14A1A8f70ACa6a3);
    // /// https://basescan.org/address/0xEAcB0EF8b160D0340578d8BA24311A5F7AD717F2
    // address internal constant PLTR_RECEIPT_VAULT = address(0xEAcB0EF8b160D0340578d8BA24311A5F7AD717F2);
    // /// https://basescan.org/address/0x842C2A838Bd005840Dea1EF62e82FC89533FF8f9
    // address internal constant PLTR_WRAPPED_TOKEN_VAULT = address(0x842C2A838Bd005840Dea1EF62e82FC89533FF8f9);

    // ---- tLLY / wtLLY — Eli Lilly and Company ST0x ----
    /// https://basescan.org/address/0x7b345A02d56f989420EbEd4df647D1C673608F3C
    address internal constant LLY_RECEIPT = address(0x7b345A02d56f989420EbEd4df647D1C673608F3C);
    /// https://basescan.org/address/0xA41Ce7B8255A01062ED1AF23ea5E8137B9300554
    address internal constant LLY_RECEIPT_VAULT = address(0xA41Ce7B8255A01062ED1AF23ea5E8137B9300554);
    /// https://basescan.org/address/0x892CcF5E75f4a7Ee6402971a1587F65BEE4d52bd
    address internal constant LLY_WRAPPED_TOKEN_VAULT = address(0x892CcF5E75f4a7Ee6402971a1587F65BEE4d52bd);

    // ---- tPTY / wtPTY — PIMCO Corporate & Income Opportunity Fund ST0x ----
    /// https://basescan.org/address/0x019Ea210a98f5E74F03376712BDAab3801079b7F
    address internal constant PTY_RECEIPT = address(0x019Ea210a98f5E74F03376712BDAab3801079b7F);
    /// https://basescan.org/address/0xb6021810971714cD48572af527307Acc324ecF61
    address internal constant PTY_RECEIPT_VAULT = address(0xb6021810971714cD48572af527307Acc324ecF61);
    /// https://basescan.org/address/0xb6D779A79E7493ed821a65D52bA419F0F6D5dD0a
    address internal constant PTY_WRAPPED_TOKEN_VAULT = address(0xb6D779A79E7493ed821a65D52bA419F0F6D5dD0a);

    // ---- tINTC / wtINTC — Intel Corporation ST0x ----
    /// https://basescan.org/address/0xAFEd850e458d331EF2A13569547258A84e2e42D2
    address internal constant INTC_RECEIPT = address(0xAFEd850e458d331EF2A13569547258A84e2e42D2);
    /// https://basescan.org/address/0xBDC237Aa3B67cC3088adAf117913F30Bf08157a3
    address internal constant INTC_RECEIPT_VAULT = address(0xBDC237Aa3B67cC3088adAf117913F30Bf08157a3);
    /// https://basescan.org/address/0xf567652fC2d7Db8D5469fD06AEbe8C9c4372d722
    address internal constant INTC_WRAPPED_TOKEN_VAULT = address(0xf567652fC2d7Db8D5469fD06AEbe8C9c4372d722);

    // ---- tHOOD / wtHOOD — Robinhood Markets, Inc. ST0x ----
    /// https://basescan.org/address/0x942639370E1c095ECCe2BdffebFB295d0B3e384e
    address internal constant HOOD_RECEIPT = address(0x942639370E1c095ECCe2BdffebFB295d0B3e384e);
    /// https://basescan.org/address/0x5cEfd886dD05001c2Fc32c313E05360D07f37d8f
    address internal constant HOOD_RECEIPT_VAULT = address(0x5cEfd886dD05001c2Fc32c313E05360D07f37d8f);
    /// https://basescan.org/address/0xd50f561322fe3235DBc9Ec8b3aB7693383d8A425
    address internal constant HOOD_WRAPPED_TOKEN_VAULT = address(0xd50f561322fe3235DBc9Ec8b3aB7693383d8A425);

    // ---- tORCL / wtORCL — Oracle Corporation ST0x ----
    /// https://basescan.org/address/0xBaf83f5D1dbC8CF4D5F5BCb93EfE23d0E333223f
    address internal constant ORCL_RECEIPT = address(0xBaf83f5D1dbC8CF4D5F5BCb93EfE23d0E333223f);
    /// https://basescan.org/address/0x57573351f3fdD20a57dEE4a7f836de1cE9900d4B
    address internal constant ORCL_RECEIPT_VAULT = address(0x57573351f3fdD20a57dEE4a7f836de1cE9900d4B);
    /// https://basescan.org/address/0xCB9571aB96aA47374eF30D8E9ACCC1cD51064726
    address internal constant ORCL_WRAPPED_TOKEN_VAULT = address(0xCB9571aB96aA47374eF30D8E9ACCC1cD51064726);

    // ---- tSMCI / wtSMCI — Super Micro Computer, Inc. ST0x ----
    /// https://basescan.org/address/0xC23aC719988d2ABeffEE8AC75C790E328c44Fe79
    address internal constant SMCI_RECEIPT = address(0xC23aC719988d2ABeffEE8AC75C790E328c44Fe79);
    /// https://basescan.org/address/0x8518931497d2A8f07Bc607D1D3295b398D065A65
    address internal constant SMCI_RECEIPT_VAULT = address(0x8518931497d2A8f07Bc607D1D3295b398D065A65);
    /// https://basescan.org/address/0xA759FAbbD866e6DB8bF76613C35825dC2e380bf0
    address internal constant SMCI_WRAPPED_TOKEN_VAULT = address(0xA759FAbbD866e6DB8bF76613C35825dC2e380bf0);

    // ---- tBABA / wtBABA — Alibaba Group Holding Limited ADR ST0x ----
    /// https://basescan.org/address/0x635983387673B0Da01f70a94985c6F88BfAf78c2
    address internal constant BABA_RECEIPT = address(0x635983387673B0Da01f70a94985c6F88BfAf78c2);
    /// https://basescan.org/address/0x6B8fa7288dBEc7C1c62BfE59Cbd7Bec7EBF846C5
    address internal constant BABA_RECEIPT_VAULT = address(0x6B8fa7288dBEc7C1c62BfE59Cbd7Bec7EBF846C5);
    /// https://basescan.org/address/0x7e5cc7eAe0455A07Ab4abf354E0f5657BA2888BD
    address internal constant BABA_WRAPPED_TOKEN_VAULT = address(0x7e5cc7eAe0455A07Ab4abf354E0f5657BA2888BD);

    // ---- tTQQQ / wtTQQQ — ProShares UltraPro QQQ ST0x ----
    /// https://basescan.org/address/0x81eFD642eBb942D725C4B035e7C3Cad154a37FAF
    address internal constant TQQQ_RECEIPT = address(0x81eFD642eBb942D725C4B035e7C3Cad154a37FAF);
    /// https://basescan.org/address/0xcA1A378F9a250131A2fE51c10f120FeF7EDCa56E
    address internal constant TQQQ_RECEIPT_VAULT = address(0xcA1A378F9a250131A2fE51c10f120FeF7EDCa56E);
    /// https://basescan.org/address/0x295e9eCAb319006900a53b3f8D6Fcb0C131F4ada
    address internal constant TQQQ_WRAPPED_TOKEN_VAULT = address(0x295e9eCAb319006900a53b3f8D6Fcb0C131F4ada);

    // ---- tFTF / wtFTF — Franklin Limited Duration Income Trust ST0x ----
    /// https://basescan.org/address/0x4CA18bF0DcCCBbD80CeF238f4c9399eFBDE3927b
    address internal constant FTF_RECEIPT = address(0x4CA18bF0DcCCBbD80CeF238f4c9399eFBDE3927b);
    /// https://basescan.org/address/0x51D5C8C8040358686952A30fAC116aAC32390d6A
    address internal constant FTF_RECEIPT_VAULT = address(0x51D5C8C8040358686952A30fAC116aAC32390d6A);
    /// https://basescan.org/address/0x9bDe199Ac6E7E050334306D9267c93e3D6d38333
    address internal constant FTF_WRAPPED_TOKEN_VAULT = address(0x9bDe199Ac6E7E050334306D9267c93e3D6d38333);

    // ---- tCBRS / wtCBRS — Cerebras Systems Inc. ST0x ----
    /// https://basescan.org/address/0xAe8aD2340aa19749A0b935C7F2245823fC4F14FB
    address internal constant CBRS_RECEIPT = address(0xAe8aD2340aa19749A0b935C7F2245823fC4F14FB);
    /// https://basescan.org/address/0xBeB0c2011bd5520A0998b69132E9245E39Ac5D1D
    address internal constant CBRS_RECEIPT_VAULT = address(0xBeB0c2011bd5520A0998b69132E9245E39Ac5D1D);
    /// https://basescan.org/address/0xB457cfBF31995d3aAAa704dA9999cC0b011820ca
    address internal constant CBRS_WRAPPED_TOKEN_VAULT = address(0xB457cfBF31995d3aAAa704dA9999cC0b011820ca);

    // ---- tAIR.PA / wtAIR.PA — Airbus SE ST0x ----
    /// https://basescan.org/address/0xa618f8eB7c33a23C84d1500c5191746f86F98b2A
    address internal constant AIR_PA_RECEIPT = address(0xa618f8eB7c33a23C84d1500c5191746f86F98b2A);
    /// https://basescan.org/address/0xDdB07ADd0e23BB7eC97f53C0959d9c6Cc09624f4
    address internal constant AIR_PA_RECEIPT_VAULT = address(0xDdB07ADd0e23BB7eC97f53C0959d9c6Cc09624f4);
    /// https://basescan.org/address/0x1C600EF167c675C878BF3222f3935C4fA2A43C31
    address internal constant AIR_PA_WRAPPED_TOKEN_VAULT = address(0x1C600EF167c675C878BF3222f3935C4fA2A43C31);

    // ---- tBMW.DE / wtBMW.DE — Bayerische Motoren Werke Aktiengesellschaft ST0x ----
    /// https://basescan.org/address/0x30864F2921886Dc491326D86015eB66c9601BF2b
    address internal constant BMW_DE_RECEIPT = address(0x30864F2921886Dc491326D86015eB66c9601BF2b);
    /// https://basescan.org/address/0x9610C265EB8F38B22Fec78498C74924D9fe55891
    address internal constant BMW_DE_RECEIPT_VAULT = address(0x9610C265EB8F38B22Fec78498C74924D9fe55891);
    /// https://basescan.org/address/0xD0269618455cF7dA71665856f16C2D03A1b26290
    address internal constant BMW_DE_WRAPPED_TOKEN_VAULT = address(0xD0269618455cF7dA71665856f16C2D03A1b26290);

    // ---- tMC.PA / wtMC.PA — LVMH Moët Hennessy Louis Vuitton SE ST0x ----
    /// https://basescan.org/address/0xBEDD4C7219E35E6C45BE792F31F076737481FF2c
    address internal constant MC_PA_RECEIPT = address(0xBEDD4C7219E35E6C45BE792F31F076737481FF2c);
    /// https://basescan.org/address/0xF5245a17E5eb64D53dEa213d40aBa01821D465Cd
    address internal constant MC_PA_RECEIPT_VAULT = address(0xF5245a17E5eb64D53dEa213d40aBa01821D465Cd);
    /// https://basescan.org/address/0xd92cc92557BFC33028195983ED31465F99b4A01c
    address internal constant MC_PA_WRAPPED_TOKEN_VAULT = address(0xd92cc92557BFC33028195983ED31465F99b4A01c);

    // ---- tSIE.DE / wtSIE.DE — Siemens Aktiengesellschaft ST0x ----
    /// https://basescan.org/address/0xe89995E4Bf9691486445917e3C69ed3d935183f1
    address internal constant SIE_DE_RECEIPT = address(0xe89995E4Bf9691486445917e3C69ed3d935183f1);
    /// https://basescan.org/address/0xa662066a60964a528aD05209139a79BDa3a7577f
    address internal constant SIE_DE_RECEIPT_VAULT = address(0xa662066a60964a528aD05209139a79BDa3a7577f);
    /// https://basescan.org/address/0xed0B0fdD92F7eece606A0FB0457352616d6e6B34
    address internal constant SIE_DE_WRAPPED_TOKEN_VAULT = address(0xed0B0fdD92F7eece606A0FB0457352616d6e6B34);

    // ---- tMBG.DE / wtMBG.DE — Mercedes-Benz Group AG ST0x ----
    /// https://basescan.org/address/0x984d884fc03D17e7b9cCfE6A32f27e9b6d9B92bd
    address internal constant MBG_DE_RECEIPT = address(0x984d884fc03D17e7b9cCfE6A32f27e9b6d9B92bd);
    /// https://basescan.org/address/0x07d7ca9384812b86e7E429473dF354fb59DA73A0
    address internal constant MBG_DE_RECEIPT_VAULT = address(0x07d7ca9384812b86e7E429473dF354fb59DA73A0);
    /// https://basescan.org/address/0xfae641bfE7009B5326396048b951E3aa31902a2B
    address internal constant MBG_DE_WRAPPED_TOKEN_VAULT = address(0xfae641bfE7009B5326396048b951E3aa31902a2B);

    // ---- tRHM.DE / wtRHM.DE — Rheinmetall AG ST0x ----
    /// https://basescan.org/address/0xfbd76467e4FBbd64dD43057bF137a75ec676C3c2
    address internal constant RHM_DE_RECEIPT = address(0xfbd76467e4FBbd64dD43057bF137a75ec676C3c2);
    /// https://basescan.org/address/0x725E0Df28D1EB09338f63776B76bCfc00f3b6f44
    address internal constant RHM_DE_RECEIPT_VAULT = address(0x725E0Df28D1EB09338f63776B76bCfc00f3b6f44);
    /// https://basescan.org/address/0xD3c42aB4D5A60A50401b3A67D10B03Ce7D96DA19
    address internal constant RHM_DE_WRAPPED_TOKEN_VAULT = address(0xD3c42aB4D5A60A50401b3A67D10B03Ce7D96DA19);

    // ---- tMCD / wtMCD — McDonald's Corporation ST0x ----
    /// https://basescan.org/address/0x1Cfa3Af9DcEc40dCa8f8588c7b7FCE5a1BA6eC3f
    address internal constant MCD_RECEIPT = address(0x1Cfa3Af9DcEc40dCa8f8588c7b7FCE5a1BA6eC3f);
    /// https://basescan.org/address/0x6363657E19A82ABE0E210e9b8c88Ea61d96eceaB
    address internal constant MCD_RECEIPT_VAULT = address(0x6363657E19A82ABE0E210e9b8c88Ea61d96eceaB);
    /// https://basescan.org/address/0x7ecAE30Ed8ee4F72653ada7b0941bDE7a0a8eE8d
    address internal constant MCD_WRAPPED_TOKEN_VAULT = address(0x7ecAE30Ed8ee4F72653ada7b0941bDE7a0a8eE8d);

    // ---- tNKE / wtNKE — NIKE, Inc. ST0x ----
    /// https://basescan.org/address/0x8A0037757d67084f5431c02eE2A352593eFe2957
    address internal constant NKE_RECEIPT = address(0x8A0037757d67084f5431c02eE2A352593eFe2957);
    /// https://basescan.org/address/0x88C3F4E2E0a977Fed97ed246c70BFD7A01070246
    address internal constant NKE_RECEIPT_VAULT = address(0x88C3F4E2E0a977Fed97ed246c70BFD7A01070246);
    /// https://basescan.org/address/0x0883f32d23Ed5535057a4B5E3eB1970FE08606AF
    address internal constant NKE_WRAPPED_TOKEN_VAULT = address(0x0883f32d23Ed5535057a4B5E3eB1970FE08606AF);

    // ---- tGRND / wtGRND — Grindr Inc. ST0x ----
    /// https://basescan.org/address/0xca4495d2fe8e82951DEbda1102A1dCf09DB7Bba6
    address internal constant GRND_RECEIPT = address(0xca4495d2fe8e82951DEbda1102A1dCf09DB7Bba6);
    /// https://basescan.org/address/0xA4178410216F5f00C718BE88C2fF8AC24de192bc
    address internal constant GRND_RECEIPT_VAULT = address(0xA4178410216F5f00C718BE88C2fF8AC24de192bc);
    /// https://basescan.org/address/0x1197E6FA778c4D13E47875bD1761c68C22c928e0
    address internal constant GRND_WRAPPED_TOKEN_VAULT = address(0x1197E6FA778c4D13E47875bD1761c68C22c928e0);

    // ---- tDNUT / wtDNUT — Krispy Kreme, Inc. ST0x ----
    /// https://basescan.org/address/0xE06eD5d80Db468a10fCfadF27ee9771DD73C7e35
    address internal constant DNUT_RECEIPT = address(0xE06eD5d80Db468a10fCfadF27ee9771DD73C7e35);
    /// https://basescan.org/address/0x6C2b6Ed57d4d9e93F3E4975FAc70eE4B180F4Eb9
    address internal constant DNUT_RECEIPT_VAULT = address(0x6C2b6Ed57d4d9e93F3E4975FAc70eE4B180F4Eb9);
    /// https://basescan.org/address/0x1db49Ff8BEe88ec73F82F395B0BEAd372BdcAdb7
    address internal constant DNUT_WRAPPED_TOKEN_VAULT = address(0x1db49Ff8BEe88ec73F82F395B0BEAd372BdcAdb7);

    // ---- tGM / wtGM — General Motors Company ST0x ----
    // Deployed 2026-09-06, never launched — swapped out for FGI before launch; recorded, not pinned.
    // /// https://basescan.org/address/0x912193f95512480167B0894E20DDe5062105F3b7
    // address internal constant GM_RECEIPT = address(0x912193f95512480167B0894E20DDe5062105F3b7);
    // /// https://basescan.org/address/0x47C04A6f705f755C10641E975607ecE8f18BC60c
    // address internal constant GM_RECEIPT_VAULT = address(0x47C04A6f705f755C10641E975607ecE8f18BC60c);
    // /// https://basescan.org/address/0x761d56D1FE1E390A96A5ECf58dE69838A231A37c
    // address internal constant GM_WRAPPED_TOKEN_VAULT = address(0x761d56D1FE1E390A96A5ECf58dE69838A231A37c);

    // ---- tPLBY / wtPLBY — Playboy, Inc. ST0x ----
    /// https://basescan.org/address/0x5978B2FA7B3DDA36847eb7D2003EC7AE112258AA
    address internal constant PLBY_RECEIPT = address(0x5978B2FA7B3DDA36847eb7D2003EC7AE112258AA);
    /// https://basescan.org/address/0xe9bc7eF69f123cA2bcA1021D1BE30224271a9217
    address internal constant PLBY_RECEIPT_VAULT = address(0xe9bc7eF69f123cA2bcA1021D1BE30224271a9217);
    /// https://basescan.org/address/0x35fDe767dBFAa610D12cf99914bCd6CFEda73B7B
    address internal constant PLBY_WRAPPED_TOKEN_VAULT = address(0x35fDe767dBFAa610D12cf99914bCd6CFEda73B7B);

    // ---- tTR / wtTR — Tootsie Roll Industries, Inc. ST0x ----
    /// https://basescan.org/address/0xf5e5d2d3b6be819Ff65cB364F4178252C9dbf5B7
    address internal constant TR_RECEIPT = address(0xf5e5d2d3b6be819Ff65cB364F4178252C9dbf5B7);
    /// https://basescan.org/address/0xeF935b17d5BE5b7ecA803158a845A08A7A9383f2
    address internal constant TR_RECEIPT_VAULT = address(0xeF935b17d5BE5b7ecA803158a845A08A7A9383f2);
    /// https://basescan.org/address/0x433fd2Fc0964B07E9820e4cd01774eDE59D1F002
    address internal constant TR_WRAPPED_TOKEN_VAULT = address(0x433fd2Fc0964B07E9820e4cd01774eDE59D1F002);

    // ---- tWEN / wtWEN — The Wendy's Company ST0x ----
    /// https://basescan.org/address/0x6c26044FAa1Ea4459a03c3760F4aAA1826a1e392
    address internal constant WEN_RECEIPT = address(0x6c26044FAa1Ea4459a03c3760F4aAA1826a1e392);
    /// https://basescan.org/address/0xedA4df511dEA07b6529db2196998B30E03791d87
    address internal constant WEN_RECEIPT_VAULT = address(0xedA4df511dEA07b6529db2196998B30E03791d87);
    /// https://basescan.org/address/0x31Fa821F8B1BDea7Db357ec9622d1A2f6aFE903d
    address internal constant WEN_WRAPPED_TOKEN_VAULT = address(0x31Fa821F8B1BDea7Db357ec9622d1A2f6aFE903d);

    // ---- tFGI / wtFGI — FGI Industries Ltd. ST0x ----
    /// https://basescan.org/address/0x46b25F089fFf268E28286C0d7A837c2f13Ad0952
    address internal constant FGI_RECEIPT = address(0x46b25F089fFf268E28286C0d7A837c2f13Ad0952);
    /// https://basescan.org/address/0x785BD77B8e92866f87E01416D1022d729975D529
    address internal constant FGI_RECEIPT_VAULT = address(0x785BD77B8e92866f87E01416D1022d729975D529);
    /// https://basescan.org/address/0x6aed8b1aCfb04F4e0e6db580F12fF41438a394e5
    address internal constant FGI_WRAPPED_TOKEN_VAULT = address(0x6aed8b1aCfb04F4e0e6db580F12fF41438a394e5);

    /// @notice Returns the 56 production token instance triples on Base, in
    /// the order they were deployed. This is the structured source of truth
    /// the flat `productionReceiptVaults()` accessor derives from; consumers
    /// that need the receipt / wrapped-vault legs or the underlying join key
    /// (cross-chain parity, per-token config checks) iterate this instead.
    /// @return tokens The 56 production token instances on Base.
    function productionTokensBase() internal pure returns (TokenInstance[] memory tokens) {
        tokens = new TokenInstance[](56);
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
        tokens[28] = TokenInstance("RKLB", RKLB_RECEIPT, RKLB_RECEIPT_VAULT, RKLB_WRAPPED_TOKEN_VAULT);
        // Deployed on Base across 2026-07-27, 2026-08-05 and 2026-08-14, each
        // wired onto the shared V4 authoriser and handed to the Base
        // token-owner Safe. All twelve were copied onto Ethereum and HyperEVM
        // by `20260807-deploy-missing-tokens`, so rows 29-41 exist on all
        // three chains, as does every row below them.
        //
        // tMETA and tPLTR are deliberately absent from the array: META is
        // deployed but never launched (absent from the registry, the logos and
        // the Turnkey token set), and PLTR's `owner()` is still the deployer
        // EOA rather than the Safe, so pinning it would break
        // `assertUniformOwnership`. Both are recorded as commented-out rows at
        // the index they would occupy — see below — so their addresses are on
        // the record without entering the array or
        // `20260807-deploy-missing-tokens`' selection.
        tokens[29] = TokenInstance("GOOGL", GOOGL_RECEIPT, GOOGL_RECEIPT_VAULT, GOOGL_WRAPPED_TOKEN_VAULT);
        // tMETA — deployed 2026-07-27, never launched; recorded here, deliberately not in the array.
        // tokens[..] = TokenInstance("META", META_RECEIPT, META_RECEIPT_VAULT, META_WRAPPED_TOKEN_VAULT);
        tokens[30] = TokenInstance("AAPL", AAPL_RECEIPT, AAPL_RECEIPT_VAULT, AAPL_WRAPPED_TOKEN_VAULT);
        tokens[31] = TokenInstance("MSFT", MSFT_RECEIPT, MSFT_RECEIPT_VAULT, MSFT_WRAPPED_TOKEN_VAULT);
        // tPLTR — deployed 2026-07-27, never launched, `owner()` still the deployer EOA; not in the array.
        // tokens[..] = TokenInstance("PLTR", PLTR_RECEIPT, PLTR_RECEIPT_VAULT, PLTR_WRAPPED_TOKEN_VAULT);
        tokens[32] = TokenInstance("LLY", LLY_RECEIPT, LLY_RECEIPT_VAULT, LLY_WRAPPED_TOKEN_VAULT);
        tokens[33] = TokenInstance("PTY", PTY_RECEIPT, PTY_RECEIPT_VAULT, PTY_WRAPPED_TOKEN_VAULT);
        tokens[34] = TokenInstance("INTC", INTC_RECEIPT, INTC_RECEIPT_VAULT, INTC_WRAPPED_TOKEN_VAULT);
        tokens[35] = TokenInstance("HOOD", HOOD_RECEIPT, HOOD_RECEIPT_VAULT, HOOD_WRAPPED_TOKEN_VAULT);
        tokens[36] = TokenInstance("ORCL", ORCL_RECEIPT, ORCL_RECEIPT_VAULT, ORCL_WRAPPED_TOKEN_VAULT);
        tokens[37] = TokenInstance("SMCI", SMCI_RECEIPT, SMCI_RECEIPT_VAULT, SMCI_WRAPPED_TOKEN_VAULT);
        tokens[38] = TokenInstance("BABA", BABA_RECEIPT, BABA_RECEIPT_VAULT, BABA_WRAPPED_TOKEN_VAULT);
        tokens[39] = TokenInstance("TQQQ", TQQQ_RECEIPT, TQQQ_RECEIPT_VAULT, TQQQ_WRAPPED_TOKEN_VAULT);
        tokens[40] = TokenInstance("FTF", FTF_RECEIPT, FTF_RECEIPT_VAULT, FTF_WRAPPED_TOKEN_VAULT);
        tokens[41] = TokenInstance("CBRS", CBRS_RECEIPT, CBRS_RECEIPT_VAULT, CBRS_WRAPPED_TOKEN_VAULT);
        // The EU batch (2026-08-27), MCD and NKE (2026-09-03), GRND
        // (2026-09-04) and the 2026-09-06 batch. Deployed on Base first and
        // copied onto Ethereum and HyperEVM on 2026-09-07 by
        // `20260807-deploy-missing-tokens` (runs 34127693038 and 34129816326),
        // which diffs Base against the target chain's table and selected
        // exactly these fourteen rows. All three tables are now 56 rows deep
        // and mirror each other index-for-index.
        tokens[42] = TokenInstance("AIR.PA", AIR_PA_RECEIPT, AIR_PA_RECEIPT_VAULT, AIR_PA_WRAPPED_TOKEN_VAULT);
        tokens[43] = TokenInstance("BMW.DE", BMW_DE_RECEIPT, BMW_DE_RECEIPT_VAULT, BMW_DE_WRAPPED_TOKEN_VAULT);
        tokens[44] = TokenInstance("MC.PA", MC_PA_RECEIPT, MC_PA_RECEIPT_VAULT, MC_PA_WRAPPED_TOKEN_VAULT);
        tokens[45] = TokenInstance("SIE.DE", SIE_DE_RECEIPT, SIE_DE_RECEIPT_VAULT, SIE_DE_WRAPPED_TOKEN_VAULT);
        tokens[46] = TokenInstance("MBG.DE", MBG_DE_RECEIPT, MBG_DE_RECEIPT_VAULT, MBG_DE_WRAPPED_TOKEN_VAULT);
        tokens[47] = TokenInstance("RHM.DE", RHM_DE_RECEIPT, RHM_DE_RECEIPT_VAULT, RHM_DE_WRAPPED_TOKEN_VAULT);
        tokens[48] = TokenInstance("MCD", MCD_RECEIPT, MCD_RECEIPT_VAULT, MCD_WRAPPED_TOKEN_VAULT);
        tokens[49] = TokenInstance("NKE", NKE_RECEIPT, NKE_RECEIPT_VAULT, NKE_WRAPPED_TOKEN_VAULT);
        tokens[50] = TokenInstance("GRND", GRND_RECEIPT, GRND_RECEIPT_VAULT, GRND_WRAPPED_TOKEN_VAULT);
        tokens[51] = TokenInstance("DNUT", DNUT_RECEIPT, DNUT_RECEIPT_VAULT, DNUT_WRAPPED_TOKEN_VAULT);
        // tGM — deployed 2026-09-06, swapped out for FGI before launch; recorded, deliberately not in the array.
        // tokens[..] = TokenInstance("GM", GM_RECEIPT, GM_RECEIPT_VAULT, GM_WRAPPED_TOKEN_VAULT);
        tokens[52] = TokenInstance("PLBY", PLBY_RECEIPT, PLBY_RECEIPT_VAULT, PLBY_WRAPPED_TOKEN_VAULT);
        tokens[53] = TokenInstance("TR", TR_RECEIPT, TR_RECEIPT_VAULT, TR_WRAPPED_TOKEN_VAULT);
        tokens[54] = TokenInstance("WEN", WEN_RECEIPT, WEN_RECEIPT_VAULT, WEN_WRAPPED_TOKEN_VAULT);
        tokens[55] = TokenInstance("FGI", FGI_RECEIPT, FGI_RECEIPT_VAULT, FGI_WRAPPED_TOKEN_VAULT);
    }

    /// @notice Returns the production token instance triples on Ethereum
    /// mainnet — Base's underlyings in Base row order, so the tables pair by
    /// index as well as by key.
    /// @return tokens The 56 production token instances on Ethereum.
    function productionTokensEthereum() internal pure returns (TokenInstance[] memory tokens) {
        // Deployed on Ethereum mainnet 2026-07-22 by
        // `20260706-deploy-tokens-ethereum` (manual-broadcast run
        // 29921218929): 28 tokens via the 0.1.1 unified deployer, each wired
        // onto the Ethereum V4 authoriser and handed to the Ethereum
        // token-owner Safe in the same broadcast. Addresses pinned from the
        // run's logged (underlying, receipt, receiptVault, wrapped) tuples.
        // Order and underlyings match Base row-for-row (the cross-chain
        // parity pin asserts this).
        tokens = new TokenInstance[](56);
        tokens[0] = TokenInstance(
            "MSTR",
            address(0xE3772C8695c2cf3dcAA2Dd29759f4Bb91a342763),
            address(0x8500189061e2206Bc33Bf04DC10fFB1Fe7dED637),
            address(0xd9fE7488B86D3aEaf457b181C744BD1A5a120833)
        );
        tokens[1] = TokenInstance(
            "TSLA",
            address(0x3a3E00d6fb65E686941f77DD375ca677Ad7772c2),
            address(0xB41fD00d0bA60D9Ae8dCE405cB6AAd5710E5F84d),
            address(0x550499e28A3CE8cb1dB3e3Db23fDD0357eD3ff48)
        );
        tokens[2] = TokenInstance(
            "COIN",
            address(0x5cF43A3fFd5B979C36B6512800cdAa6A2EF4f352),
            address(0x5100ED387Ab3ED37667199aD8f9F6D963157d28e),
            address(0xa3d1be1Ab9F4E72309Cb9Bfeaa14aFe46D012e36)
        );
        tokens[3] = TokenInstance(
            "SPYM",
            address(0xB023d277f4a50cE056Dd921C28fF7e27F56B3445),
            address(0x484AaA9e6542774026b24aeD4EC3058400eD2439),
            address(0x7dF3ad1ECC10DBF0296D05F91a697e4A059771c2)
        );
        tokens[4] = TokenInstance(
            "SIVR",
            address(0x89dC2d5B33e8DcbD24A2e4A07f7B06f55b5bb24e),
            address(0xc6100518997004eFb0701Da3c56000B3d093470a),
            address(0x2B310218001C38cf82816c2098AedDCE22D3Df27)
        );
        tokens[5] = TokenInstance(
            "CRCL",
            address(0xDf228279B380e8445970a3B4162B9509D4339520),
            address(0xeF63EdB9F39Dcd03C103A11e2e7E1878308b9586),
            address(0x25Ab6926BA171e1618b214cda774104B2f6ec884)
        );
        tokens[6] = TokenInstance(
            "NVDA",
            address(0xA26C89357e6cb53Bf670db2e0e939f5489Ba26A8),
            address(0xf6A89b0c9FF897000E37bBD06397992278FfC50d),
            address(0xa3947d2A74F5a3A7135A9d0c66B28fC7315f30Da)
        );
        tokens[7] = TokenInstance(
            "IAU",
            address(0x9003CAc529d1299891C2aaa08b4c810b81F49488),
            address(0xb9A1D1822F57f52959b8c5097A8322D534bceDEe),
            address(0x33f3a6401ce08f705eE4B8a03fc37F298395b720)
        );
        tokens[8] = TokenInstance(
            "PPLT",
            address(0x216cbEeC16cF7e4dBd53e6e3D8B54b7dA23BE146),
            address(0x47C2e6644eFDF58E86dA45dC60e0f67A65043B99),
            address(0xCbD06C802BFe993de94d0d635AB5B1fa764519D8)
        );
        tokens[9] = TokenInstance(
            "AMZN",
            address(0xA583addaA69142E8588D9ffE3767Dbb0F23fd516),
            address(0x6615f3D82989949fa7d167b40FEc0Ef30cdbA476),
            address(0x4404E24629a33b85FC1E2D7beA673Cd283054594)
        );
        tokens[10] = TokenInstance(
            "BMNR",
            address(0x34BF824C28121EbD421026D70a03A7Ec9Ee5a0d4),
            address(0x00472aA0D0611F933c22b8148F02B0cDd1Ae5fbc),
            address(0x35e1D3d3Fa6D43438641d2b8f63cBf84C84435c0)
        );
        tokens[11] = TokenInstance(
            "IBHG",
            address(0x8e05CB17994Ee9B207e87993717F6Fb2ee7D0bD3),
            address(0x36b30F5B5D1AcD3D8135Afe7a5516A300021f139),
            address(0x03bBb4148ba82d63993D32fB8E6Eff8Cc51A56f2)
        );
        tokens[12] = TokenInstance(
            "SGOV",
            address(0xE4B5Af0bAc3dC97b77d6eE4E95F59c74c679ee5c),
            address(0x344147366F648640076d363FAF659c214788E99d),
            address(0x06b17E431a957Dd8522Bf106653BAc6B39F437E6)
        );
        tokens[13] = TokenInstance(
            "QQQM",
            address(0x1Eb9583d1BB2b00B3CB5ead921d021b445F77dBc),
            address(0x5Aa65dfF455C7f18C21370086EaFaEe4f2b63608),
            address(0x63fDfe9cf53cB1FD5d98fE7537B881B86aE04A31)
        );
        tokens[14] = TokenInstance(
            "VWO",
            address(0x1A09A154E2ae3890d1e18507a37bC3e2FCfA10cc),
            address(0x2cc8DCfC649f9633C482C81473cC251226375fE3),
            address(0x01EE8b582147D1Aa8A8f2Adc2EBB91fA60082AB0)
        );
        tokens[15] = TokenInstance(
            "ARKK",
            address(0xF1E5f11e7fAA40b2C2CEdfAD825D81207f793862),
            address(0xDf406836D5A092894ee5d5bdC7F58e5bdc8D196A),
            address(0x5D80cAcaABCe0ab4C1541493ceB25D97970D250a)
        );
        tokens[16] = TokenInstance(
            "SPCX",
            address(0x46dC08972b1d5D5876d244292c551dbbbC7d7e80),
            address(0x659Ea9dd1C833fc76E5328E0E616d8b9D9836dc3),
            address(0xC32C8166164E2cA18BB5fbf3E82CB776943d97FB)
        );
        tokens[17] = TokenInstance(
            "CEG",
            address(0x99Ffbf38E7c0D9C440BA629D0108E7d0E96cB710),
            address(0x6240E93f1A08d43002e52b210cD49c54C813D780),
            address(0xc842fC56Dd39B62357d027a0F3B3266353cac991)
        );
        tokens[18] = TokenInstance(
            "DRAM",
            address(0xbD4Fa8Fd2643b46eADC499b5A468108817988830),
            address(0x5F5a1Bdc00ade7702ea5944B1374DC598dA3759f),
            address(0x7e1263f1e1EeF7eCe7fA7e568842f213a6CEa956)
        );
        tokens[19] = TokenInstance(
            "TSM",
            address(0x2Ce6A6B9E573ec0444C00103ACEee9dC23223621),
            address(0x7Ac659f601bEa2d9f490E0D0D8a68c4282fD9B21),
            address(0x050dB961D36DC2047c779798694AeE455CD40BE6)
        );
        tokens[20] = TokenInstance(
            "SKHY",
            address(0xd3150728FFDb338eFd9b07ae90A7D5e688bc3B20),
            address(0xa3a7BEcF428b250Ec1b88Dbc65F579a9570670c7),
            address(0xD13bBc46C4582246656868d32227A99A538D97E1)
        );
        tokens[21] = TokenInstance(
            "ASML",
            address(0x6AEBd84df448d2E25080590797075b399Ca43549),
            address(0x77Ee94C8B85cF48a426F84B0F2d796eC77e41c7b),
            address(0xb8605a64B57E7A8631c87F3187c783493231bdD9)
        );
        tokens[22] = TokenInstance(
            "MU",
            address(0x98A3887f51AA93079978D265Cb20E215AfEB8b0f),
            address(0x2C845ed32c5fDE012eb14508d0d24BD3300B1D71),
            address(0xF01523C4ca52dF88f07938D4Fb32FCBb6b159867)
        );
        tokens[23] = TokenInstance(
            "AMD",
            address(0x0e257A952817ef779407aA27E5CD5F27863883Aa),
            address(0xe2De878d8Ca6bA544BFE80a10fAb0395DF32Cff0),
            address(0xb904955bC71FE6c8e6aBE676ACca640Abc771622)
        );
        tokens[24] = TokenInstance(
            "AVGO",
            address(0x607991FE92F9476eBedA4761295E5E2cc37e2834),
            address(0x503a69b2918DFA152eb0e0803174ed90ba5be756),
            address(0xCee4981Fc273C105e2b9eA1fD19031Aa9a6cf113)
        );
        tokens[25] = TokenInstance(
            "AMAT",
            address(0x8C8810F83a0F5a8C1A3D541411100DBFB68C5b0c),
            address(0x26139195f7a82a52c62C4047F843C99c61Ed9a5E),
            address(0x44DE27A07B33CD708A49fa79629fAC1df03C56d3)
        );
        tokens[26] = TokenInstance(
            "LRCX",
            address(0x2630CA3D952b265F88C189f3679FA985dF34A93D),
            address(0xe68A46547CdBBB181587B32cCD1A505Bedf0a994),
            address(0xD1c1D974837d3f79A92E14048993AD28a6228831)
        );
        tokens[27] = TokenInstance(
            "TTWO",
            address(0x47E3487B12272Bb1F933452F855CEb1C5e27204E),
            address(0xb62E913f0cC881862527Fa7e41e1C98eEf09cedD),
            address(0x1D6F0763e58FA6d472d470Eaaef0a4C08080d208)
        );
        // RKLB was accidentally omitted from the table when the 28-token
        // Ethereum broadcast ran; a gap-filling broadcast (EXECUTED
        // 2026-07-22, manual-broadcast run 29924926246) deployed it and this
        // row pins the logged tuple. That per-chain script has since been
        // superseded by `20260807-deploy-missing-tokens`.
        tokens[28] = TokenInstance(
            "RKLB",
            address(0xFf5b15a4f478F296893b0b244D9b118Be87bCda2),
            address(0xED0c085d92C262FB46937CB0B3C9763Af7fCCf30),
            address(0x8FC87Be766C0cB6f254F1FDc9351D4B85B560FB3)
        );
        // Deployed 2026-08-12 by `20260807-deploy-missing-tokens` across two
        // manual-broadcast runs (31613854321, 31624478447) — the five 2026-08-05
        // tokens then the six 2026-07-27 ones. Each was wired onto this
        // chain's V4 authoriser and handed to its token-owner Safe in the same
        // broadcast; these rows pin the logged tuples, which the runs produced
        // but no PR ever recorded. Verified on chain before pinning: every
        // `owner()` is the Safe and every `authorizer()` the V4 clone.
        tokens[29] = TokenInstance(
            "GOOGL",
            address(0xdC29d07D2125699FA44cAB7e940542b526dB0abd),
            address(0x50DE74136b67911799fc39B726bFC2707cCec769),
            address(0xca678d0d69F9E815d1A4f4dF05C904b2DDE017f8)
        );
        tokens[30] = TokenInstance(
            "AAPL",
            address(0x5f1DBfBf9345f3185C52aC3c080a0EDDb4f540c2),
            address(0xb526Bf49DAB7F72B772FEF4B6D572C254A454ef7),
            address(0x4E3600f48C61eF4513c72923ab50851bD546FFA9)
        );
        tokens[31] = TokenInstance(
            "MSFT",
            address(0x824eA918F35821a72E34b4eaD257AF60603cb20C),
            address(0xb3f9A61b0e97c7F7Bb85Ea5E9Dad0da8f3496B57),
            address(0xAbb2641950C7dE9D3ec9AA05668e112E1DB701F6)
        );
        tokens[32] = TokenInstance(
            "LLY",
            address(0x9a288A27a9898f145AF9575b46617bB1DF705106),
            address(0x1eE2cE9654FFa008029e8e328a95f45EBfB3bC63),
            address(0xa6890e89D99Fd4F275c016d89A28ec24A428846D)
        );
        tokens[33] = TokenInstance(
            "PTY",
            address(0x7b66449B3d7cD6569F1e235f6E4A664C24538EA8),
            address(0xdf4F0897Ec6f0C37Bfc974a815cA440A3c2C2e8B),
            address(0xc80730995D2C53114BAaFd2736E02f4E274D5B83)
        );
        tokens[34] = TokenInstance(
            "INTC",
            address(0x8CF3E580465e8DFaE05FF42BbFCe0d98BfF79580),
            address(0x06aE3f6CFaE124039902a79Da44ad2a4A4489250),
            address(0xd702276d50fdCf58b0E41b3f1f9651faBC1141f4)
        );
        tokens[35] = TokenInstance(
            "HOOD",
            address(0x9e2C9bE59aEB0D9ea7bF070B37fc02AF8a5af239),
            address(0xDA52106FC0D44096Fd500E096b9045FdAc1d27B9),
            address(0x3209384FB852E7D0510aFa896236f3f866c3876f)
        );
        tokens[36] = TokenInstance(
            "ORCL",
            address(0xE3D23D83a750789D6c4150B70013D896e623c948),
            address(0xC982730643321f3643436Eb4a6E910219Caa55f0),
            address(0x1B2A2C8c3621642c64cf1245016488fA0f76da78)
        );
        tokens[37] = TokenInstance(
            "SMCI",
            address(0x1B5df34bD6397Ba7d9A365263692A006e7a2972a),
            address(0x3b3936b5Ec170Cdb5823012dBF4dF1d56Cfa1ba5),
            address(0x8DdAEC53399E5324BbC60a368eA853c713629B1d)
        );
        tokens[38] = TokenInstance(
            "BABA",
            address(0xB7D42b94A8E51b098270ac92ceD23fDC8042FDB3),
            address(0x15d415952a36D4cE80671e918B2531bdB25274E5),
            address(0x908266E3C3bFBb603d2EdF295deBE37C88985239)
        );
        tokens[39] = TokenInstance(
            "TQQQ",
            address(0x58916AC4e186ad201376288a6655Ea46b55b8ac5),
            address(0xf3875383506677BCdA6b9F12c48Ff7fE300970D7),
            address(0x04eE4ED5FF6643eA955503f966012b684f479966)
        );
        // FTF, deployed 2026-08-14 by `20260807-deploy-missing-tokens` (run
        // 31835550273) — the sole token the dispatch selected, Base having been
        // pinned to 41 first. Wired onto this chain's V4 authoriser and handed
        // to its token-owner Safe in the same broadcast.
        tokens[40] = TokenInstance(
            "FTF",
            address(0x05215bE061F61d341703a6b63AcFDFf396965425),
            address(0x334ccaD2e7D774F5e6A13437977dD0878926deF8),
            address(0x710A14a41a8Ea2e25376124C48bf9cAdc1E69be5)
        );
        // CBRS, deployed 2026-08-14 by `20260807-deploy-missing-tokens` (run
        // 31845108154) — the sole token that dispatch selected. It was never pinned
        // here: the pin PR (#310) stayed open, so this table sat a row behind
        // the chain. Verified live before pinning — symbol() tCBRS, receipt()
        // and owner() the chain's token-owner Safe.
        tokens[41] = TokenInstance(
            "CBRS",
            address(0x8Ea1ba9Fc0CF7338B41DdDa5B778a9118274AEA8),
            address(0x75E0d127794b9C26eE35c55fbaBcc41c53Ccb37C),
            address(0x15925E1c19c0F0d392F6FCb40FdE9144Dd823962)
        );
        // Deployed 2026-09-07 by `20260807-deploy-missing-tokens`
        // (manual-broadcast run 34127693038) — the fourteen Base rows this table
        // was missing: the EU batch (2026-08-27), MCD and NKE (2026-09-03),
        // GRND (2026-09-04) and the 2026-09-06 batch. Each was wired onto this
        // chain's V4 authoriser and handed to its token-owner Safe in the same
        // broadcast; these rows pin the logged tuples. Verified on chain before
        // pinning: every `receipt()` matches, every `owner()` is the chain's
        // token-owner Safe, every `symbol()` is the expected t-ticker and every
        // wrapper has code.
        tokens[42] = TokenInstance(
            "AIR.PA",
            address(0x9452c603A552f35003206f9001C51007C36F530F),
            address(0x4Da175A70020EeEFa71C36d710307ed0803Aed60),
            address(0xc3bc6EEf91FfAeBACB13f4c48aC0515C820d2b0c)
        );
        tokens[43] = TokenInstance(
            "BMW.DE",
            address(0x7bc0B10f99c95F9F3e1e12a436a3869B53c9cb9C),
            address(0x6872cEe8E1a07Dd8C1154755f7e215F2973caE52),
            address(0x36FE4dc30b3b4906c9A64D5C957D49388E8d38E8)
        );
        tokens[44] = TokenInstance(
            "MC.PA",
            address(0xc562dB7c3B8A41cBF8B84D3C057787723BD13d2F),
            address(0xaE7115d434c84F2f4a1196BaD67415d479804af1),
            address(0xeaA6da57f120D5a0acB9Ff4807F7990EfBbE303a)
        );
        tokens[45] = TokenInstance(
            "SIE.DE",
            address(0xee6F971a9Bf473355286749b52Bfe614Df5fC129),
            address(0x269CA594b6463F0D94086fb2D77dFaad32d1c6C4),
            address(0x08A85a5AcE300e881e7c8828412A3Bdfd6F99054)
        );
        tokens[46] = TokenInstance(
            "MBG.DE",
            address(0x5536F0308E969C2DB0e52dBe99CB6871cC9E35f4),
            address(0xA1768baE756058fE00dD281C405DDe1C48B00F3B),
            address(0x6a73364EaE305199B62585C4486C24f3b72b2C72)
        );
        tokens[47] = TokenInstance(
            "RHM.DE",
            address(0xbf56725da5a71B3111C660c2279ADA6D1270772E),
            address(0x8790337c4Ce51b66CBa179129d830A3683780ff6),
            address(0x24ae429A29882b06898afCBAef20BfDb93f67e20)
        );
        tokens[48] = TokenInstance(
            "MCD",
            address(0x37BbE0cd96266CFc10960521EfB32A822ef780E0),
            address(0xC04160F3e18e120C2259f3FE33864823bF3b9015),
            address(0xe26b53fb8B0819682432d27C88D6505883cabafF)
        );
        tokens[49] = TokenInstance(
            "NKE",
            address(0x6884986776e2e221B7Cd5c566bBD9338051F24fB),
            address(0x5e6e803242E52451FfdA82Fd7b5Ce4967B95C76E),
            address(0x8fe134109A9Eb38D3f071a9Df4911081B4aa0814)
        );
        tokens[50] = TokenInstance(
            "GRND",
            address(0x9765A993735a639191ea2AAd2ac92eb122Bd394c),
            address(0xdca06fddf5320870C8E9D0534aa102677C36bCc4),
            address(0xB80Bd4D599EeBBF2851d4E7F5594918B82FF1823)
        );
        tokens[51] = TokenInstance(
            "DNUT",
            address(0x0eE9d8bB4D7d035b5Dc33937573Cc03BDb419c6e),
            address(0x4a88c84AA04a5151997e8E503BEe7fD92E0918A9),
            address(0xb7fC2b7881cceeB73D8DEccf69B6AcB8aC2E0826)
        );
        tokens[52] = TokenInstance(
            "PLBY",
            address(0xea8AF911CE3582d8fB5d6F1cd4695Ba115d1BdCA),
            address(0x4a18036Dce22168D8891919a1c75aC2CAf9a08AB),
            address(0xBe127eeD812DC1F622227FAdc8639d4138B47b2e)
        );
        tokens[53] = TokenInstance(
            "TR",
            address(0xEb36fc7B191b8358c0Cc839A873fCe1108fc36d1),
            address(0xF88e511a3c762eE7E9ddd348a417F8e8db45BDEE),
            address(0x1abADE2601DA2617f441e2c2B3Fff870445FEfd1)
        );
        tokens[54] = TokenInstance(
            "WEN",
            address(0x8231910EA52Ce2753C70D07545cEBfe476a609bA),
            address(0x6c6f1CBe2fA860b1a15A02922d97A2d614db4923),
            address(0x441Eaae749B7BA0C4462F2b19a47fBe8De0DFac2)
        );
        tokens[55] = TokenInstance(
            "FGI",
            address(0x7B3aA82Ca4Ef0eE146C32183366f3dED77400E0c),
            address(0xfEa217600e2b00bBB2172a99345016a0cEb7d29f),
            address(0x685DFd386968B58D895F934485820C479C79a8bB)
        );
    }

    /// @notice Returns the 56 production token instance triples on HyperEVM,
    /// in the same row order as `productionTokensBase()` (the cross-chain
    /// parity pin asserts the alignment).
    /// @return tokens The 56 production token instances on HyperEVM.
    function productionTokensHyperEvm() internal pure returns (TokenInstance[] memory tokens) {
        // Deployed on HyperEVM 2026-07-24 (manual-broadcast run 30114307165):
        // all 29 tokens via the 0.1.1 unified deployer, each wired onto the
        // HyperEVM V4 authoriser and handed to the HyperEVM token-owner Safe
        // in the same broadcast. Addresses pinned from the run's logged
        // (underlying, receipt, receiptVault, wrapped) tuples. The script that
        // ran it was per-chain and has since been superseded by
        // `20260807-deploy-missing-tokens`, so this is the record of the run.
        tokens = new TokenInstance[](56);
        tokens[0] = TokenInstance(
            "MSTR",
            0xE3772C8695c2cf3dcAA2Dd29759f4Bb91a342763,
            0x8500189061e2206Bc33Bf04DC10fFB1Fe7dED637,
            0xd9fE7488B86D3aEaf457b181C744BD1A5a120833
        );
        tokens[1] = TokenInstance(
            "TSLA",
            0x3a3E00d6fb65E686941f77DD375ca677Ad7772c2,
            0xB41fD00d0bA60D9Ae8dCE405cB6AAd5710E5F84d,
            0x550499e28A3CE8cb1dB3e3Db23fDD0357eD3ff48
        );
        tokens[2] = TokenInstance(
            "COIN",
            0x5cF43A3fFd5B979C36B6512800cdAa6A2EF4f352,
            0x5100ED387Ab3ED37667199aD8f9F6D963157d28e,
            0xa3d1be1Ab9F4E72309Cb9Bfeaa14aFe46D012e36
        );
        tokens[3] = TokenInstance(
            "SPYM",
            0xB023d277f4a50cE056Dd921C28fF7e27F56B3445,
            0x484AaA9e6542774026b24aeD4EC3058400eD2439,
            0x7dF3ad1ECC10DBF0296D05F91a697e4A059771c2
        );
        tokens[4] = TokenInstance(
            "SIVR",
            0x89dC2d5B33e8DcbD24A2e4A07f7B06f55b5bb24e,
            0xc6100518997004eFb0701Da3c56000B3d093470a,
            0x2B310218001C38cf82816c2098AedDCE22D3Df27
        );
        tokens[5] = TokenInstance(
            "CRCL",
            0xDf228279B380e8445970a3B4162B9509D4339520,
            0xeF63EdB9F39Dcd03C103A11e2e7E1878308b9586,
            0x25Ab6926BA171e1618b214cda774104B2f6ec884
        );
        tokens[6] = TokenInstance(
            "NVDA",
            0xA26C89357e6cb53Bf670db2e0e939f5489Ba26A8,
            0xf6A89b0c9FF897000E37bBD06397992278FfC50d,
            0xa3947d2A74F5a3A7135A9d0c66B28fC7315f30Da
        );
        tokens[7] = TokenInstance(
            "IAU",
            0x9003CAc529d1299891C2aaa08b4c810b81F49488,
            0xb9A1D1822F57f52959b8c5097A8322D534bceDEe,
            0x33f3a6401ce08f705eE4B8a03fc37F298395b720
        );
        tokens[8] = TokenInstance(
            "PPLT",
            0x216cbEeC16cF7e4dBd53e6e3D8B54b7dA23BE146,
            0x47C2e6644eFDF58E86dA45dC60e0f67A65043B99,
            0xCbD06C802BFe993de94d0d635AB5B1fa764519D8
        );
        tokens[9] = TokenInstance(
            "AMZN",
            0xA583addaA69142E8588D9ffE3767Dbb0F23fd516,
            0x6615f3D82989949fa7d167b40FEc0Ef30cdbA476,
            0x4404E24629a33b85FC1E2D7beA673Cd283054594
        );
        tokens[10] = TokenInstance(
            "BMNR",
            0x34BF824C28121EbD421026D70a03A7Ec9Ee5a0d4,
            0x00472aA0D0611F933c22b8148F02B0cDd1Ae5fbc,
            0x35e1D3d3Fa6D43438641d2b8f63cBf84C84435c0
        );
        tokens[11] = TokenInstance(
            "IBHG",
            0x8e05CB17994Ee9B207e87993717F6Fb2ee7D0bD3,
            0x36b30F5B5D1AcD3D8135Afe7a5516A300021f139,
            0x03bBb4148ba82d63993D32fB8E6Eff8Cc51A56f2
        );
        tokens[12] = TokenInstance(
            "SGOV",
            0xE4B5Af0bAc3dC97b77d6eE4E95F59c74c679ee5c,
            0x344147366F648640076d363FAF659c214788E99d,
            0x06b17E431a957Dd8522Bf106653BAc6B39F437E6
        );
        tokens[13] = TokenInstance(
            "QQQM",
            0x1Eb9583d1BB2b00B3CB5ead921d021b445F77dBc,
            0x5Aa65dfF455C7f18C21370086EaFaEe4f2b63608,
            0x63fDfe9cf53cB1FD5d98fE7537B881B86aE04A31
        );
        tokens[14] = TokenInstance(
            "VWO",
            0x1A09A154E2ae3890d1e18507a37bC3e2FCfA10cc,
            0x2cc8DCfC649f9633C482C81473cC251226375fE3,
            0x01EE8b582147D1Aa8A8f2Adc2EBB91fA60082AB0
        );
        tokens[15] = TokenInstance(
            "ARKK",
            0xF1E5f11e7fAA40b2C2CEdfAD825D81207f793862,
            0xDf406836D5A092894ee5d5bdC7F58e5bdc8D196A,
            0x5D80cAcaABCe0ab4C1541493ceB25D97970D250a
        );
        tokens[16] = TokenInstance(
            "SPCX",
            0x46dC08972b1d5D5876d244292c551dbbbC7d7e80,
            0x659Ea9dd1C833fc76E5328E0E616d8b9D9836dc3,
            0xC32C8166164E2cA18BB5fbf3E82CB776943d97FB
        );
        tokens[17] = TokenInstance(
            "CEG",
            0x99Ffbf38E7c0D9C440BA629D0108E7d0E96cB710,
            0x6240E93f1A08d43002e52b210cD49c54C813D780,
            0xc842fC56Dd39B62357d027a0F3B3266353cac991
        );
        tokens[18] = TokenInstance(
            "DRAM",
            0xbD4Fa8Fd2643b46eADC499b5A468108817988830,
            0x5F5a1Bdc00ade7702ea5944B1374DC598dA3759f,
            0x7e1263f1e1EeF7eCe7fA7e568842f213a6CEa956
        );
        tokens[19] = TokenInstance(
            "TSM",
            0x2Ce6A6B9E573ec0444C00103ACEee9dC23223621,
            0x7Ac659f601bEa2d9f490E0D0D8a68c4282fD9B21,
            0x050dB961D36DC2047c779798694AeE455CD40BE6
        );
        tokens[20] = TokenInstance(
            "SKHY",
            0xd3150728FFDb338eFd9b07ae90A7D5e688bc3B20,
            0xa3a7BEcF428b250Ec1b88Dbc65F579a9570670c7,
            0xD13bBc46C4582246656868d32227A99A538D97E1
        );
        tokens[21] = TokenInstance(
            "ASML",
            0x6AEBd84df448d2E25080590797075b399Ca43549,
            0x77Ee94C8B85cF48a426F84B0F2d796eC77e41c7b,
            0xb8605a64B57E7A8631c87F3187c783493231bdD9
        );
        tokens[22] = TokenInstance(
            "MU",
            0x98A3887f51AA93079978D265Cb20E215AfEB8b0f,
            0x2C845ed32c5fDE012eb14508d0d24BD3300B1D71,
            0xF01523C4ca52dF88f07938D4Fb32FCBb6b159867
        );
        tokens[23] = TokenInstance(
            "AMD",
            0x0e257A952817ef779407aA27E5CD5F27863883Aa,
            0xe2De878d8Ca6bA544BFE80a10fAb0395DF32Cff0,
            0xb904955bC71FE6c8e6aBE676ACca640Abc771622
        );
        tokens[24] = TokenInstance(
            "AVGO",
            0x607991FE92F9476eBedA4761295E5E2cc37e2834,
            0x503a69b2918DFA152eb0e0803174ed90ba5be756,
            0xCee4981Fc273C105e2b9eA1fD19031Aa9a6cf113
        );
        tokens[25] = TokenInstance(
            "AMAT",
            0x8C8810F83a0F5a8C1A3D541411100DBFB68C5b0c,
            0x26139195f7a82a52c62C4047F843C99c61Ed9a5E,
            0x44DE27A07B33CD708A49fa79629fAC1df03C56d3
        );
        tokens[26] = TokenInstance(
            "LRCX",
            0x2630CA3D952b265F88C189f3679FA985dF34A93D,
            0xe68A46547CdBBB181587B32cCD1A505Bedf0a994,
            0xD1c1D974837d3f79A92E14048993AD28a6228831
        );
        tokens[27] = TokenInstance(
            "TTWO",
            0x47E3487B12272Bb1F933452F855CEb1C5e27204E,
            0xb62E913f0cC881862527Fa7e41e1C98eEf09cedD,
            0x1D6F0763e58FA6d472d470Eaaef0a4C08080d208
        );
        tokens[28] = TokenInstance(
            "RKLB",
            0xFf5b15a4f478F296893b0b244D9b118Be87bCda2,
            0xED0c085d92C262FB46937CB0B3C9763Af7fCCf30,
            0x8FC87Be766C0cB6f254F1FDc9351D4B85B560FB3
        );
        // Deployed 2026-08-12 by `20260807-deploy-missing-tokens` across two
        // manual-broadcast runs (31614605147, 31625585429) — the five 2026-08-05
        // tokens then the six 2026-07-27 ones. Each was wired onto this
        // chain's V4 authoriser and handed to its token-owner Safe in the same
        // broadcast; these rows pin the logged tuples, which the runs produced
        // but no PR ever recorded. Verified on chain before pinning: every
        // `owner()` is the Safe and every `authorizer()` the V4 clone.
        tokens[29] = TokenInstance(
            "GOOGL",
            0xdC29d07D2125699FA44cAB7e940542b526dB0abd,
            0x50DE74136b67911799fc39B726bFC2707cCec769,
            0xca678d0d69F9E815d1A4f4dF05C904b2DDE017f8
        );
        tokens[30] = TokenInstance(
            "AAPL",
            0x5f1DBfBf9345f3185C52aC3c080a0EDDb4f540c2,
            0xb526Bf49DAB7F72B772FEF4B6D572C254A454ef7,
            0x4E3600f48C61eF4513c72923ab50851bD546FFA9
        );
        tokens[31] = TokenInstance(
            "MSFT",
            0x824eA918F35821a72E34b4eaD257AF60603cb20C,
            0xb3f9A61b0e97c7F7Bb85Ea5E9Dad0da8f3496B57,
            0xAbb2641950C7dE9D3ec9AA05668e112E1DB701F6
        );
        tokens[32] = TokenInstance(
            "LLY",
            0x9a288A27a9898f145AF9575b46617bB1DF705106,
            0x1eE2cE9654FFa008029e8e328a95f45EBfB3bC63,
            0xa6890e89D99Fd4F275c016d89A28ec24A428846D
        );
        tokens[33] = TokenInstance(
            "PTY",
            0x7b66449B3d7cD6569F1e235f6E4A664C24538EA8,
            0xdf4F0897Ec6f0C37Bfc974a815cA440A3c2C2e8B,
            0xc80730995D2C53114BAaFd2736E02f4E274D5B83
        );
        tokens[34] = TokenInstance(
            "INTC",
            0x8CF3E580465e8DFaE05FF42BbFCe0d98BfF79580,
            0x06aE3f6CFaE124039902a79Da44ad2a4A4489250,
            0xd702276d50fdCf58b0E41b3f1f9651faBC1141f4
        );
        tokens[35] = TokenInstance(
            "HOOD",
            0x9e2C9bE59aEB0D9ea7bF070B37fc02AF8a5af239,
            0xDA52106FC0D44096Fd500E096b9045FdAc1d27B9,
            0x3209384FB852E7D0510aFa896236f3f866c3876f
        );
        tokens[36] = TokenInstance(
            "ORCL",
            0xE3D23D83a750789D6c4150B70013D896e623c948,
            0xC982730643321f3643436Eb4a6E910219Caa55f0,
            0x1B2A2C8c3621642c64cf1245016488fA0f76da78
        );
        tokens[37] = TokenInstance(
            "SMCI",
            0x1B5df34bD6397Ba7d9A365263692A006e7a2972a,
            0x3b3936b5Ec170Cdb5823012dBF4dF1d56Cfa1ba5,
            0x8DdAEC53399E5324BbC60a368eA853c713629B1d
        );
        tokens[38] = TokenInstance(
            "BABA",
            0xB7D42b94A8E51b098270ac92ceD23fDC8042FDB3,
            0x15d415952a36D4cE80671e918B2531bdB25274E5,
            0x908266E3C3bFBb603d2EdF295deBE37C88985239
        );
        tokens[39] = TokenInstance(
            "TQQQ",
            0x58916AC4e186ad201376288a6655Ea46b55b8ac5,
            0xf3875383506677BCdA6b9F12c48Ff7fE300970D7,
            0x04eE4ED5FF6643eA955503f966012b684f479966
        );
        // FTF, deployed 2026-08-14 by `20260807-deploy-missing-tokens` (run
        // 31835971348) — the sole token the dispatch selected, Base having been
        // pinned to 41 first. Wired onto this chain's V4 authoriser and handed
        // to its token-owner Safe in the same broadcast.
        tokens[40] = TokenInstance(
            "FTF",
            0x05215bE061F61d341703a6b63AcFDFf396965425,
            0x334ccaD2e7D774F5e6A13437977dD0878926deF8,
            0x710A14a41a8Ea2e25376124C48bf9cAdc1E69be5
        );
        // CBRS, deployed 2026-08-14 by `20260807-deploy-missing-tokens` (run
        // 31845492796) — the sole token that dispatch selected. It was never pinned
        // here: the pin PR (#310) stayed open, so this table sat a row behind
        // the chain. Verified live before pinning — symbol() tCBRS, receipt()
        // and owner() the chain's token-owner Safe.
        tokens[41] = TokenInstance(
            "CBRS",
            0x8Ea1ba9Fc0CF7338B41DdDa5B778a9118274AEA8,
            0x75E0d127794b9C26eE35c55fbaBcc41c53Ccb37C,
            0x15925E1c19c0F0d392F6FCb40FdE9144Dd823962
        );
        // Deployed 2026-09-07 by `20260807-deploy-missing-tokens`
        // (manual-broadcast run 34129816326) — the fourteen Base rows this table
        // was missing: the EU batch (2026-08-27), MCD and NKE (2026-09-03),
        // GRND (2026-09-04) and the 2026-09-06 batch. Each was wired onto this
        // chain's V4 authoriser and handed to its token-owner Safe in the same
        // broadcast; these rows pin the logged tuples. Verified on chain before
        // pinning: every `receipt()` matches, every `owner()` is the chain's
        // token-owner Safe, every `symbol()` is the expected t-ticker and every
        // wrapper has code.
        tokens[42] = TokenInstance(
            "AIR.PA",
            0x9452c603A552f35003206f9001C51007C36F530F,
            0x4Da175A70020EeEFa71C36d710307ed0803Aed60,
            0xc3bc6EEf91FfAeBACB13f4c48aC0515C820d2b0c
        );
        tokens[43] = TokenInstance(
            "BMW.DE",
            0x7bc0B10f99c95F9F3e1e12a436a3869B53c9cb9C,
            0x6872cEe8E1a07Dd8C1154755f7e215F2973caE52,
            0x36FE4dc30b3b4906c9A64D5C957D49388E8d38E8
        );
        tokens[44] = TokenInstance(
            "MC.PA",
            0xc562dB7c3B8A41cBF8B84D3C057787723BD13d2F,
            0xaE7115d434c84F2f4a1196BaD67415d479804af1,
            0xeaA6da57f120D5a0acB9Ff4807F7990EfBbE303a
        );
        tokens[45] = TokenInstance(
            "SIE.DE",
            0xee6F971a9Bf473355286749b52Bfe614Df5fC129,
            0x269CA594b6463F0D94086fb2D77dFaad32d1c6C4,
            0x08A85a5AcE300e881e7c8828412A3Bdfd6F99054
        );
        tokens[46] = TokenInstance(
            "MBG.DE",
            0x5536F0308E969C2DB0e52dBe99CB6871cC9E35f4,
            0xA1768baE756058fE00dD281C405DDe1C48B00F3B,
            0x6a73364EaE305199B62585C4486C24f3b72b2C72
        );
        tokens[47] = TokenInstance(
            "RHM.DE",
            0xbf56725da5a71B3111C660c2279ADA6D1270772E,
            0x8790337c4Ce51b66CBa179129d830A3683780ff6,
            0x24ae429A29882b06898afCBAef20BfDb93f67e20
        );
        tokens[48] = TokenInstance(
            "MCD",
            0x37BbE0cd96266CFc10960521EfB32A822ef780E0,
            0xC04160F3e18e120C2259f3FE33864823bF3b9015,
            0xe26b53fb8B0819682432d27C88D6505883cabafF
        );
        tokens[49] = TokenInstance(
            "NKE",
            0x6884986776e2e221B7Cd5c566bBD9338051F24fB,
            0x5e6e803242E52451FfdA82Fd7b5Ce4967B95C76E,
            0x8fe134109A9Eb38D3f071a9Df4911081B4aa0814
        );
        tokens[50] = TokenInstance(
            "GRND",
            0x9765A993735a639191ea2AAd2ac92eb122Bd394c,
            0xdca06fddf5320870C8E9D0534aa102677C36bCc4,
            0xB80Bd4D599EeBBF2851d4E7F5594918B82FF1823
        );
        tokens[51] = TokenInstance(
            "DNUT",
            0x0eE9d8bB4D7d035b5Dc33937573Cc03BDb419c6e,
            0x4a88c84AA04a5151997e8E503BEe7fD92E0918A9,
            0xb7fC2b7881cceeB73D8DEccf69B6AcB8aC2E0826
        );
        tokens[52] = TokenInstance(
            "PLBY",
            0xea8AF911CE3582d8fB5d6F1cd4695Ba115d1BdCA,
            0x4a18036Dce22168D8891919a1c75aC2CAf9a08AB,
            0xBe127eeD812DC1F622227FAdc8639d4138B47b2e
        );
        tokens[53] = TokenInstance(
            "TR",
            0xEb36fc7B191b8358c0Cc839A873fCe1108fc36d1,
            0xF88e511a3c762eE7E9ddd348a417F8e8db45BDEE,
            0x1abADE2601DA2617f441e2c2B3Fff870445FEfd1
        );
        tokens[54] = TokenInstance(
            "WEN",
            0x8231910EA52Ce2753C70D07545cEBfe476a609bA,
            0x6c6f1CBe2fA860b1a15A02922d97A2d614db4923,
            0x441Eaae749B7BA0C4462F2b19a47fBe8De0DFac2
        );
        tokens[55] = TokenInstance(
            "FGI",
            0x7B3aA82Ca4Ef0eE146C32183366f3dED77400E0c,
            0xfEa217600e2b00bBB2172a99345016a0cEb7d29f,
            0x685DFd386968B58D895F934485820C479C79a8bB
        );
    }

    /// @notice Returns the production token instance triples on Robinhood
    /// Chain (chain id 4663) — Base's underlyings in Base row order, so the
    /// tables pair by index as well as by key (the cross-chain parity pin
    /// asserts the alignment).
    ///
    /// Deployed on Robinhood Chain by `20260807-deploy-missing-tokens` on
    /// `robinhood`, in two broadcasts, each via the 0.1.1 unified deployer
    /// against beacons already on 0.1.30, each token wired onto this chain's
    /// V4 authoriser and handed to its token-owner Safe in the same
    /// broadcast. Addresses pinned from each run's logged
    /// (underlying, receipt, receiptVault, wrapped) tuples:
    ///
    ///   rows 0-40   2026-09-10  manual-broadcast run 34542355140 (41 tokens)
    ///   rows 41-55  2026-09-11  manual-broadcast run 34588739371 (15 tokens)
    ///
    /// The second run is the copy of the fifteen Base rows Base itself only
    /// picked up in #339 (CBRS, the EU batch, MCD/NKE, GRND/DNUT and the
    /// 2026-09-06 batch); the script diffed Base against this table and
    /// selected exactly those fifteen.
    /// @return tokens The 56 production token instances on Robinhood Chain.
    function productionTokensRobinhood() internal pure returns (TokenInstance[] memory tokens) {
        tokens = new TokenInstance[](56);
        tokens[0] = TokenInstance(
            "MSTR",
            0xE3772C8695c2cf3dcAA2Dd29759f4Bb91a342763,
            0x8500189061e2206Bc33Bf04DC10fFB1Fe7dED637,
            0xd9fE7488B86D3aEaf457b181C744BD1A5a120833
        );
        tokens[1] = TokenInstance(
            "TSLA",
            0x3a3E00d6fb65E686941f77DD375ca677Ad7772c2,
            0xB41fD00d0bA60D9Ae8dCE405cB6AAd5710E5F84d,
            0x550499e28A3CE8cb1dB3e3Db23fDD0357eD3ff48
        );
        tokens[2] = TokenInstance(
            "COIN",
            0x5cF43A3fFd5B979C36B6512800cdAa6A2EF4f352,
            0x5100ED387Ab3ED37667199aD8f9F6D963157d28e,
            0xa3d1be1Ab9F4E72309Cb9Bfeaa14aFe46D012e36
        );
        tokens[3] = TokenInstance(
            "SPYM",
            0xB023d277f4a50cE056Dd921C28fF7e27F56B3445,
            0x484AaA9e6542774026b24aeD4EC3058400eD2439,
            0x7dF3ad1ECC10DBF0296D05F91a697e4A059771c2
        );
        tokens[4] = TokenInstance(
            "SIVR",
            0x89dC2d5B33e8DcbD24A2e4A07f7B06f55b5bb24e,
            0xc6100518997004eFb0701Da3c56000B3d093470a,
            0x2B310218001C38cf82816c2098AedDCE22D3Df27
        );
        tokens[5] = TokenInstance(
            "CRCL",
            0xDf228279B380e8445970a3B4162B9509D4339520,
            0xeF63EdB9F39Dcd03C103A11e2e7E1878308b9586,
            0x25Ab6926BA171e1618b214cda774104B2f6ec884
        );
        tokens[6] = TokenInstance(
            "NVDA",
            0xA26C89357e6cb53Bf670db2e0e939f5489Ba26A8,
            0xf6A89b0c9FF897000E37bBD06397992278FfC50d,
            0xa3947d2A74F5a3A7135A9d0c66B28fC7315f30Da
        );
        tokens[7] = TokenInstance(
            "IAU",
            0x9003CAc529d1299891C2aaa08b4c810b81F49488,
            0xb9A1D1822F57f52959b8c5097A8322D534bceDEe,
            0x33f3a6401ce08f705eE4B8a03fc37F298395b720
        );
        tokens[8] = TokenInstance(
            "PPLT",
            0x216cbEeC16cF7e4dBd53e6e3D8B54b7dA23BE146,
            0x47C2e6644eFDF58E86dA45dC60e0f67A65043B99,
            0xCbD06C802BFe993de94d0d635AB5B1fa764519D8
        );
        tokens[9] = TokenInstance(
            "AMZN",
            0xA583addaA69142E8588D9ffE3767Dbb0F23fd516,
            0x6615f3D82989949fa7d167b40FEc0Ef30cdbA476,
            0x4404E24629a33b85FC1E2D7beA673Cd283054594
        );
        tokens[10] = TokenInstance(
            "BMNR",
            0x34BF824C28121EbD421026D70a03A7Ec9Ee5a0d4,
            0x00472aA0D0611F933c22b8148F02B0cDd1Ae5fbc,
            0x35e1D3d3Fa6D43438641d2b8f63cBf84C84435c0
        );
        tokens[11] = TokenInstance(
            "IBHG",
            0x8e05CB17994Ee9B207e87993717F6Fb2ee7D0bD3,
            0x36b30F5B5D1AcD3D8135Afe7a5516A300021f139,
            0x03bBb4148ba82d63993D32fB8E6Eff8Cc51A56f2
        );
        tokens[12] = TokenInstance(
            "SGOV",
            0xE4B5Af0bAc3dC97b77d6eE4E95F59c74c679ee5c,
            0x344147366F648640076d363FAF659c214788E99d,
            0x06b17E431a957Dd8522Bf106653BAc6B39F437E6
        );
        tokens[13] = TokenInstance(
            "QQQM",
            0x1Eb9583d1BB2b00B3CB5ead921d021b445F77dBc,
            0x5Aa65dfF455C7f18C21370086EaFaEe4f2b63608,
            0x63fDfe9cf53cB1FD5d98fE7537B881B86aE04A31
        );
        tokens[14] = TokenInstance(
            "VWO",
            0x1A09A154E2ae3890d1e18507a37bC3e2FCfA10cc,
            0x2cc8DCfC649f9633C482C81473cC251226375fE3,
            0x01EE8b582147D1Aa8A8f2Adc2EBB91fA60082AB0
        );
        tokens[15] = TokenInstance(
            "ARKK",
            0xF1E5f11e7fAA40b2C2CEdfAD825D81207f793862,
            0xDf406836D5A092894ee5d5bdC7F58e5bdc8D196A,
            0x5D80cAcaABCe0ab4C1541493ceB25D97970D250a
        );
        tokens[16] = TokenInstance(
            "SPCX",
            0x46dC08972b1d5D5876d244292c551dbbbC7d7e80,
            0x659Ea9dd1C833fc76E5328E0E616d8b9D9836dc3,
            0xC32C8166164E2cA18BB5fbf3E82CB776943d97FB
        );
        tokens[17] = TokenInstance(
            "CEG",
            0x99Ffbf38E7c0D9C440BA629D0108E7d0E96cB710,
            0x6240E93f1A08d43002e52b210cD49c54C813D780,
            0xc842fC56Dd39B62357d027a0F3B3266353cac991
        );
        tokens[18] = TokenInstance(
            "DRAM",
            0xbD4Fa8Fd2643b46eADC499b5A468108817988830,
            0x5F5a1Bdc00ade7702ea5944B1374DC598dA3759f,
            0x7e1263f1e1EeF7eCe7fA7e568842f213a6CEa956
        );
        tokens[19] = TokenInstance(
            "TSM",
            0x2Ce6A6B9E573ec0444C00103ACEee9dC23223621,
            0x7Ac659f601bEa2d9f490E0D0D8a68c4282fD9B21,
            0x050dB961D36DC2047c779798694AeE455CD40BE6
        );
        tokens[20] = TokenInstance(
            "SKHY",
            0xd3150728FFDb338eFd9b07ae90A7D5e688bc3B20,
            0xa3a7BEcF428b250Ec1b88Dbc65F579a9570670c7,
            0xD13bBc46C4582246656868d32227A99A538D97E1
        );
        tokens[21] = TokenInstance(
            "ASML",
            0x6AEBd84df448d2E25080590797075b399Ca43549,
            0x77Ee94C8B85cF48a426F84B0F2d796eC77e41c7b,
            0xb8605a64B57E7A8631c87F3187c783493231bdD9
        );
        tokens[22] = TokenInstance(
            "MU",
            0x98A3887f51AA93079978D265Cb20E215AfEB8b0f,
            0x2C845ed32c5fDE012eb14508d0d24BD3300B1D71,
            0xF01523C4ca52dF88f07938D4Fb32FCBb6b159867
        );
        tokens[23] = TokenInstance(
            "AMD",
            0x0e257A952817ef779407aA27E5CD5F27863883Aa,
            0xe2De878d8Ca6bA544BFE80a10fAb0395DF32Cff0,
            0xb904955bC71FE6c8e6aBE676ACca640Abc771622
        );
        tokens[24] = TokenInstance(
            "AVGO",
            0x607991FE92F9476eBedA4761295E5E2cc37e2834,
            0x503a69b2918DFA152eb0e0803174ed90ba5be756,
            0xCee4981Fc273C105e2b9eA1fD19031Aa9a6cf113
        );
        tokens[25] = TokenInstance(
            "AMAT",
            0x8C8810F83a0F5a8C1A3D541411100DBFB68C5b0c,
            0x26139195f7a82a52c62C4047F843C99c61Ed9a5E,
            0x44DE27A07B33CD708A49fa79629fAC1df03C56d3
        );
        tokens[26] = TokenInstance(
            "LRCX",
            0x2630CA3D952b265F88C189f3679FA985dF34A93D,
            0xe68A46547CdBBB181587B32cCD1A505Bedf0a994,
            0xD1c1D974837d3f79A92E14048993AD28a6228831
        );
        tokens[27] = TokenInstance(
            "TTWO",
            0x47E3487B12272Bb1F933452F855CEb1C5e27204E,
            0xb62E913f0cC881862527Fa7e41e1C98eEf09cedD,
            0x1D6F0763e58FA6d472d470Eaaef0a4C08080d208
        );
        tokens[28] = TokenInstance(
            "RKLB",
            0xFf5b15a4f478F296893b0b244D9b118Be87bCda2,
            0xED0c085d92C262FB46937CB0B3C9763Af7fCCf30,
            0x8FC87Be766C0cB6f254F1FDc9351D4B85B560FB3
        );
        tokens[29] = TokenInstance(
            "GOOGL",
            0x9e2C9bE59aEB0D9ea7bF070B37fc02AF8a5af239,
            0xDA52106FC0D44096Fd500E096b9045FdAc1d27B9,
            0x3209384FB852E7D0510aFa896236f3f866c3876f
        );
        tokens[30] = TokenInstance(
            "AAPL",
            0xE3D23D83a750789D6c4150B70013D896e623c948,
            0xC982730643321f3643436Eb4a6E910219Caa55f0,
            0x1B2A2C8c3621642c64cf1245016488fA0f76da78
        );
        tokens[31] = TokenInstance(
            "MSFT",
            0x1B5df34bD6397Ba7d9A365263692A006e7a2972a,
            0x3b3936b5Ec170Cdb5823012dBF4dF1d56Cfa1ba5,
            0x8DdAEC53399E5324BbC60a368eA853c713629B1d
        );
        tokens[32] = TokenInstance(
            "LLY",
            0xB7D42b94A8E51b098270ac92ceD23fDC8042FDB3,
            0x15d415952a36D4cE80671e918B2531bdB25274E5,
            0x908266E3C3bFBb603d2EdF295deBE37C88985239
        );
        tokens[33] = TokenInstance(
            "PTY",
            0x58916AC4e186ad201376288a6655Ea46b55b8ac5,
            0xf3875383506677BCdA6b9F12c48Ff7fE300970D7,
            0x04eE4ED5FF6643eA955503f966012b684f479966
        );
        tokens[34] = TokenInstance(
            "INTC",
            0x5f1DBfBf9345f3185C52aC3c080a0EDDb4f540c2,
            0xb526Bf49DAB7F72B772FEF4B6D572C254A454ef7,
            0x4E3600f48C61eF4513c72923ab50851bD546FFA9
        );
        tokens[35] = TokenInstance(
            "HOOD",
            0xdC29d07D2125699FA44cAB7e940542b526dB0abd,
            0x50DE74136b67911799fc39B726bFC2707cCec769,
            0xca678d0d69F9E815d1A4f4dF05C904b2DDE017f8
        );
        tokens[36] = TokenInstance(
            "ORCL",
            0x8CF3E580465e8DFaE05FF42BbFCe0d98BfF79580,
            0x06aE3f6CFaE124039902a79Da44ad2a4A4489250,
            0xd702276d50fdCf58b0E41b3f1f9651faBC1141f4
        );
        tokens[37] = TokenInstance(
            "SMCI",
            0x9a288A27a9898f145AF9575b46617bB1DF705106,
            0x1eE2cE9654FFa008029e8e328a95f45EBfB3bC63,
            0xa6890e89D99Fd4F275c016d89A28ec24A428846D
        );
        tokens[38] = TokenInstance(
            "BABA",
            0x824eA918F35821a72E34b4eaD257AF60603cb20C,
            0xb3f9A61b0e97c7F7Bb85Ea5E9Dad0da8f3496B57,
            0xAbb2641950C7dE9D3ec9AA05668e112E1DB701F6
        );
        tokens[39] = TokenInstance(
            "TQQQ",
            0x7b66449B3d7cD6569F1e235f6E4A664C24538EA8,
            0xdf4F0897Ec6f0C37Bfc974a815cA440A3c2C2e8B,
            0xc80730995D2C53114BAaFd2736E02f4E274D5B83
        );
        tokens[40] = TokenInstance(
            "FTF",
            0x05215bE061F61d341703a6b63AcFDFf396965425,
            0x334ccaD2e7D774F5e6A13437977dD0878926deF8,
            0x710A14a41a8Ea2e25376124C48bf9cAdc1E69be5
        );
        // Rows 41-55: Base's later deployments, copied onto this chain by
        // `20260807-deploy-missing-tokens` on 2026-09-11 (manual-broadcast run
        // 34588739371) — the fifteen rows the dispatch selected, in Base order.
        tokens[41] = TokenInstance(
            "CBRS",
            0x8Ea1ba9Fc0CF7338B41DdDa5B778a9118274AEA8,
            0x75E0d127794b9C26eE35c55fbaBcc41c53Ccb37C,
            0x15925E1c19c0F0d392F6FCb40FdE9144Dd823962
        );
        tokens[42] = TokenInstance(
            "AIR.PA",
            0x9452c603A552f35003206f9001C51007C36F530F,
            0x4Da175A70020EeEFa71C36d710307ed0803Aed60,
            0xc3bc6EEf91FfAeBACB13f4c48aC0515C820d2b0c
        );
        tokens[43] = TokenInstance(
            "BMW.DE",
            0x7bc0B10f99c95F9F3e1e12a436a3869B53c9cb9C,
            0x6872cEe8E1a07Dd8C1154755f7e215F2973caE52,
            0x36FE4dc30b3b4906c9A64D5C957D49388E8d38E8
        );
        tokens[44] = TokenInstance(
            "MC.PA",
            0xc562dB7c3B8A41cBF8B84D3C057787723BD13d2F,
            0xaE7115d434c84F2f4a1196BaD67415d479804af1,
            0xeaA6da57f120D5a0acB9Ff4807F7990EfBbE303a
        );
        tokens[45] = TokenInstance(
            "SIE.DE",
            0xee6F971a9Bf473355286749b52Bfe614Df5fC129,
            0x269CA594b6463F0D94086fb2D77dFaad32d1c6C4,
            0x08A85a5AcE300e881e7c8828412A3Bdfd6F99054
        );
        tokens[46] = TokenInstance(
            "MBG.DE",
            0x5536F0308E969C2DB0e52dBe99CB6871cC9E35f4,
            0xA1768baE756058fE00dD281C405DDe1C48B00F3B,
            0x6a73364EaE305199B62585C4486C24f3b72b2C72
        );
        tokens[47] = TokenInstance(
            "RHM.DE",
            0xbf56725da5a71B3111C660c2279ADA6D1270772E,
            0x8790337c4Ce51b66CBa179129d830A3683780ff6,
            0x24ae429A29882b06898afCBAef20BfDb93f67e20
        );
        tokens[48] = TokenInstance(
            "MCD",
            0x37BbE0cd96266CFc10960521EfB32A822ef780E0,
            0xC04160F3e18e120C2259f3FE33864823bF3b9015,
            0xe26b53fb8B0819682432d27C88D6505883cabafF
        );
        tokens[49] = TokenInstance(
            "NKE",
            0x6884986776e2e221B7Cd5c566bBD9338051F24fB,
            0x5e6e803242E52451FfdA82Fd7b5Ce4967B95C76E,
            0x8fe134109A9Eb38D3f071a9Df4911081B4aa0814
        );
        tokens[50] = TokenInstance(
            "GRND",
            0x9765A993735a639191ea2AAd2ac92eb122Bd394c,
            0xdca06fddf5320870C8E9D0534aa102677C36bCc4,
            0xB80Bd4D599EeBBF2851d4E7F5594918B82FF1823
        );
        tokens[51] = TokenInstance(
            "DNUT",
            0x0eE9d8bB4D7d035b5Dc33937573Cc03BDb419c6e,
            0x4a88c84AA04a5151997e8E503BEe7fD92E0918A9,
            0xb7fC2b7881cceeB73D8DEccf69B6AcB8aC2E0826
        );
        tokens[52] = TokenInstance(
            "PLBY",
            0xea8AF911CE3582d8fB5d6F1cd4695Ba115d1BdCA,
            0x4a18036Dce22168D8891919a1c75aC2CAf9a08AB,
            0xBe127eeD812DC1F622227FAdc8639d4138B47b2e
        );
        tokens[53] = TokenInstance(
            "TR",
            0xEb36fc7B191b8358c0Cc839A873fCe1108fc36d1,
            0xF88e511a3c762eE7E9ddd348a417F8e8db45BDEE,
            0x1abADE2601DA2617f441e2c2B3Fff870445FEfd1
        );
        tokens[54] = TokenInstance(
            "WEN",
            0x8231910EA52Ce2753C70D07545cEBfe476a609bA,
            0x6c6f1CBe2fA860b1a15A02922d97A2d614db4923,
            0x441Eaae749B7BA0C4462F2b19a47fBe8De0DFac2
        );
        tokens[55] = TokenInstance(
            "FGI",
            0x7B3aA82Ca4Ef0eE146C32183366f3dED77400E0c,
            0xfEa217600e2b00bBB2172a99345016a0cEb7d29f,
            0x685DFd386968B58D895F934485820C479C79a8bB
        );
    }

    /// @notice Returns the production token instance triples on BNB Smart
    /// Chain (chain id 56) — Base's underlyings in Base row order, so the
    /// tables pair by index as well as by key (the cross-chain parity pin
    /// asserts the alignment).
    ///
    /// Deployed on BNB Smart Chain by `20260807-deploy-missing-tokens` on
    /// `bsc`, in two broadcasts, each via the 0.1.1 unified deployer against
    /// beacons already on 0.1.30, each token wired onto this chain's V4
    /// authoriser and handed to its token-owner Safe in the same broadcast.
    /// Addresses pinned from each run's logged
    /// (underlying, receipt, receiptVault, wrapped) tuples:
    ///
    ///   rows 0-40   2026-09-11  manual-broadcast run 34545683866 (41 tokens)
    ///   rows 41-55  2026-09-11  manual-broadcast run 34589363778 (15 tokens)
    ///
    /// An EARLIER run, 34542307257, also broadcast all 41 tokens on this
    /// chain and was never pinned; its vaults are live, Safe-owned and
    /// zero-supply, and nothing references them. They are NOT in this table
    /// and must not be pinned into it by mistake — see issue #364.
    ///
    /// Two address facts that look like copy-paste bugs and are not. These
    /// are nonce-ordered deploys from one key, so equal deployer nonces give
    /// equal addresses across chains, and this chain's nonce cursor is 41
    /// ahead of Robinhood's because of run 34542307257:
    ///
    ///   - the orphan set from 34542307257 sits at the addresses Robinhood
    ///     rows 0-40 occupy, and
    ///   - rows 0-14 HERE sit at the addresses Robinhood rows 41-55 occupy.
    ///
    /// Neither is a duplicate pin: each address is a distinct contract on its
    /// own chain, carrying that chain's own symbol. Rows 41-55 here were
    /// broadcast past both windows and collide with nothing on Robinhood.
    /// @return tokens The 56 production token instances on BNB Smart Chain.
    function productionTokensBsc() internal pure returns (TokenInstance[] memory tokens) {
        tokens = new TokenInstance[](56);
        tokens[0] = TokenInstance(
            "MSTR",
            0x8Ea1ba9Fc0CF7338B41DdDa5B778a9118274AEA8,
            0x75E0d127794b9C26eE35c55fbaBcc41c53Ccb37C,
            0x15925E1c19c0F0d392F6FCb40FdE9144Dd823962
        );
        tokens[1] = TokenInstance(
            "TSLA",
            0x9452c603A552f35003206f9001C51007C36F530F,
            0x4Da175A70020EeEFa71C36d710307ed0803Aed60,
            0xc3bc6EEf91FfAeBACB13f4c48aC0515C820d2b0c
        );
        tokens[2] = TokenInstance(
            "COIN",
            0x7bc0B10f99c95F9F3e1e12a436a3869B53c9cb9C,
            0x6872cEe8E1a07Dd8C1154755f7e215F2973caE52,
            0x36FE4dc30b3b4906c9A64D5C957D49388E8d38E8
        );
        tokens[3] = TokenInstance(
            "SPYM",
            0xc562dB7c3B8A41cBF8B84D3C057787723BD13d2F,
            0xaE7115d434c84F2f4a1196BaD67415d479804af1,
            0xeaA6da57f120D5a0acB9Ff4807F7990EfBbE303a
        );
        tokens[4] = TokenInstance(
            "SIVR",
            0xee6F971a9Bf473355286749b52Bfe614Df5fC129,
            0x269CA594b6463F0D94086fb2D77dFaad32d1c6C4,
            0x08A85a5AcE300e881e7c8828412A3Bdfd6F99054
        );
        tokens[5] = TokenInstance(
            "CRCL",
            0x5536F0308E969C2DB0e52dBe99CB6871cC9E35f4,
            0xA1768baE756058fE00dD281C405DDe1C48B00F3B,
            0x6a73364EaE305199B62585C4486C24f3b72b2C72
        );
        tokens[6] = TokenInstance(
            "NVDA",
            0xbf56725da5a71B3111C660c2279ADA6D1270772E,
            0x8790337c4Ce51b66CBa179129d830A3683780ff6,
            0x24ae429A29882b06898afCBAef20BfDb93f67e20
        );
        tokens[7] = TokenInstance(
            "IAU",
            0x37BbE0cd96266CFc10960521EfB32A822ef780E0,
            0xC04160F3e18e120C2259f3FE33864823bF3b9015,
            0xe26b53fb8B0819682432d27C88D6505883cabafF
        );
        tokens[8] = TokenInstance(
            "PPLT",
            0x6884986776e2e221B7Cd5c566bBD9338051F24fB,
            0x5e6e803242E52451FfdA82Fd7b5Ce4967B95C76E,
            0x8fe134109A9Eb38D3f071a9Df4911081B4aa0814
        );
        tokens[9] = TokenInstance(
            "AMZN",
            0x9765A993735a639191ea2AAd2ac92eb122Bd394c,
            0xdca06fddf5320870C8E9D0534aa102677C36bCc4,
            0xB80Bd4D599EeBBF2851d4E7F5594918B82FF1823
        );
        tokens[10] = TokenInstance(
            "BMNR",
            0x0eE9d8bB4D7d035b5Dc33937573Cc03BDb419c6e,
            0x4a88c84AA04a5151997e8E503BEe7fD92E0918A9,
            0xb7fC2b7881cceeB73D8DEccf69B6AcB8aC2E0826
        );
        tokens[11] = TokenInstance(
            "IBHG",
            0xea8AF911CE3582d8fB5d6F1cd4695Ba115d1BdCA,
            0x4a18036Dce22168D8891919a1c75aC2CAf9a08AB,
            0xBe127eeD812DC1F622227FAdc8639d4138B47b2e
        );
        tokens[12] = TokenInstance(
            "SGOV",
            0xEb36fc7B191b8358c0Cc839A873fCe1108fc36d1,
            0xF88e511a3c762eE7E9ddd348a417F8e8db45BDEE,
            0x1abADE2601DA2617f441e2c2B3Fff870445FEfd1
        );
        tokens[13] = TokenInstance(
            "QQQM",
            0x8231910EA52Ce2753C70D07545cEBfe476a609bA,
            0x6c6f1CBe2fA860b1a15A02922d97A2d614db4923,
            0x441Eaae749B7BA0C4462F2b19a47fBe8De0DFac2
        );
        tokens[14] = TokenInstance(
            "VWO",
            0x7B3aA82Ca4Ef0eE146C32183366f3dED77400E0c,
            0xfEa217600e2b00bBB2172a99345016a0cEb7d29f,
            0x685DFd386968B58D895F934485820C479C79a8bB
        );
        tokens[15] = TokenInstance(
            "ARKK",
            0x34a8386fd0a943D4c1F182e9eb6b5e125509dFF2,
            0x2E04C503ebd584C3c0Bb1d57E0C51E7B7EaE28E1,
            0xe93A1Bb48e797dDa936f405A7A253f55040584D5
        );
        tokens[16] = TokenInstance(
            "SPCX",
            0xc3f3EAfCc5927C645cdb22CEEB68844D53AA7C7C,
            0x76D34283ec6d29b1b07E0e6077f5c436AD163B9c,
            0xfBA650082205E5807a5eAF28BdcC8E851bB2f753
        );
        tokens[17] = TokenInstance(
            "CEG",
            0x4ed13d2C1f545FA73f53bE8c0BB82D279738C10f,
            0xF8bF43D61E4Cd2a5b5DfaD01BaC84693d7B95e51,
            0x06096908dBC38fc54509024674E4fd1891B5F7CA
        );
        tokens[18] = TokenInstance(
            "DRAM",
            0x395717EE8201419b21B40A400ea959a7D7d43A36,
            0xfAE9AfE275E57759f8Fbae5f252c65aDBF1b773F,
            0x23A0944e82766242dA76cb0f77e0b7812e5487EA
        );
        tokens[19] = TokenInstance(
            "TSM",
            0x9835e52FAFA9A92678C8A9420034706B1edD431e,
            0x4d4D633bf04ABF6e4cF152C7c5c1ecD906Ab3de4,
            0x5Ce8b84756dDdE011734F04dC4bA2930C981B443
        );
        tokens[20] = TokenInstance(
            "SKHY",
            0x29e7fe750DFffd4D7C8e907C126324B8a5A9AdB7,
            0xd78025Aa344E549A1D76eCE1591c481cC7Bc3548,
            0x81f40cbCFAE7A1aD1f4474eD95A210DfA3B90B0f
        );
        tokens[21] = TokenInstance(
            "ASML",
            0xe509C440B68c4FBf95e24d7476d3e5Bc8b25a8BB,
            0x89857176e95973FDC8f365532CF4c162b3EE11f0,
            0x88c10BEcFf283c21e9253d688ec06804359cF795
        );
        tokens[22] = TokenInstance(
            "MU",
            0x7e26dE68d52b54f9CBc8D64833c1fEDA82C36A92,
            0xdab834808F67f8aC69642996A28571D4B2aD484E,
            0xE828671B6EDd47122e4AcDE7aba6D12c58F244A3
        );
        tokens[23] = TokenInstance(
            "AMD",
            0xe26C011A6dcFd8286a3Cf47718F14299d33f9478,
            0xb4e960909A3fe9179Ed7e0FBC6ABF3301Ce85536,
            0x5d6775Cb5b22faF47471986e99265C1a4846d845
        );
        tokens[24] = TokenInstance(
            "AVGO",
            0x25A8D39070510B41889000b2Cc35c4f7DBD72134,
            0xaAb11f0141C2AA6B9A3845EFdB1a6D16DC40924a,
            0xF4a7b2f0D02C488099e80874Bb035A5490fBB063
        );
        tokens[25] = TokenInstance(
            "AMAT",
            0x53405346fc8a6235408083FE612bbc41703a32e2,
            0x516d6c697C40E24De9D17811e642a07a6D70Cf07,
            0xFF4d9a957868fAa99c8E46B16614527806BF9Df5
        );
        tokens[26] = TokenInstance(
            "LRCX",
            0xe8A142fbDCFa6Ca663b507d4f23Df20d71cb4EFB,
            0x012ec0436407b8ade9A00614e01Abf1FaAB69755,
            0x8135482f5590e25eD8CCaFa3aD4165A3c57C84DF
        );
        tokens[27] = TokenInstance(
            "TTWO",
            0xd06c1c388769FFeB47BDE408B0C5BBb071797aE1,
            0xe319e212860ef85c4082B3B73641bD25721c88B2,
            0x5A61EF0b15e4B2805aE066848f63ECA646988129
        );
        tokens[28] = TokenInstance(
            "RKLB",
            0xBF907e8bE14FfFeDef6FD2f02E780E03176Fc514,
            0x2C594750DBE8e5B2D8d155b4FcB39FEd307A91b9,
            0xcF06ba5e81B5148f371823d86e88a9508FA3c7E9
        );
        tokens[29] = TokenInstance(
            "GOOGL",
            0xCe5a91f916A91e005fC0a87CFf161B560e608e42,
            0x925eB169Ed82889a7AFE5292D97998acb26B6233,
            0xc7f956fc103bDD062C01B9cAaa1829a55fC9dE9F
        );
        tokens[30] = TokenInstance(
            "AAPL",
            0xC617Fe6239A8Eb2aD2CB2151fb56C9B5ACb72cE6,
            0xfa63F568c4487711124D9f258D3A9167a89797c3,
            0x407DEa5B6a1B7B7DbA021C55A9ecb294530A89Df
        );
        tokens[31] = TokenInstance(
            "MSFT",
            0xaCfd9C413fe0253dc9336dA97e426eaaB9A5AfbD,
            0xb9c3a133e2425eeC6D8a1dAD9A0D78308BE79a5E,
            0x2CFe46d386Ea8D7E4cDAE588C933560674BB9085
        );
        tokens[32] = TokenInstance(
            "LLY",
            0x698E03e7504dcACF0D526d79713f51F363e961D4,
            0xd2F6AbFB251a3e43df9191486485dE0E46a9E6A5,
            0x55b3dcc96d635495831c3BE68ef7b1A28982De60
        );
        tokens[33] = TokenInstance(
            "PTY",
            0x27544f69AAceca9752714FE0c44B580FFef7f59A,
            0xD170Ed7698508f228bB5A67D0f4548eeeA6f15CB,
            0xEf58b9197cA61C09d140f37F009dAF5df5c811e8
        );
        tokens[34] = TokenInstance(
            "INTC",
            0x58535e864CD6C9174b26b90B8F3da82A6c5b976c,
            0x2aA2258B97f44425769cF1a4E92a3562060A93E8,
            0x73d02c80d3611FB1E33fa61E9c99B4FD732418F3
        );
        tokens[35] = TokenInstance(
            "HOOD",
            0x78E9123ba21f52B976FaB92dCF8944E8dE32b9Be,
            0x0D2029Ed7497A8CC5c65E808393CEd0AF2259385,
            0x83527768c19F845fC981A2deAeaD8C4E6c33b9Ce
        );
        tokens[36] = TokenInstance(
            "ORCL",
            0x5Ac28Db4773d6B1903c96479E7ecfaBe83E90f8A,
            0x683dd1C36169b25355c8c110942A820f395FFB7d,
            0xDE616a1935C6292Bcbe650b701C9abE300DEd13B
        );
        tokens[37] = TokenInstance(
            "SMCI",
            0x0d685C1A795059Ed93873b80FE87617B99D01897,
            0x185CcB3c9C09300b3877f71E747f041604f7603F,
            0xaE817035eEabF45E7Ae1a145c29EBEb285349474
        );
        tokens[38] = TokenInstance(
            "BABA",
            0x9d846203E00d5561F57648A6063d1D9E80B920AE,
            0xcb8b0c80560a66c96A25297cc98b23fa1d7ACC6A,
            0xDE6d3a82B44ac3a5618e348646591d72448Ae7e0
        );
        tokens[39] = TokenInstance(
            "TQQQ",
            0xfAC9480634A8CD16d4ad0DA795fC2bd9fef9e9A5,
            0xCd49DA53D0570E6d34AB786aA4EB4F9E0e6aB045,
            0x2304ad0f88635f6088522FBe2703D27C4c3168c1
        );
        tokens[40] = TokenInstance(
            "FTF",
            0xaa10C79156b09701A8ca313a985dbB671FaAe04D,
            0x162d65E4E4313b88D7eFc37F9c8110b334110406,
            0xd6c50a60b46eeF15ae2E8dbeFC417A6F0F154bc5
        );
        // Rows 41-55: Base's later deployments, copied onto this chain by
        // `20260807-deploy-missing-tokens` on 2026-09-11 (manual-broadcast run
        // 34589363778) — the fifteen rows the dispatch selected, in Base order.
        tokens[41] = TokenInstance(
            "CBRS",
            0xdEa3AA3Ad91C7989Dd9986b8E5558d0e9889d718,
            0xB51C6A5c30A37814128E143e307E1f9c8cC9E32B,
            0x13C799519E62eB07bf324896241F535f16dEdAe6
        );
        tokens[42] = TokenInstance(
            "AIR.PA",
            0x079E9711E66b8e7A206ef23737374F4eD2Ff821b,
            0x7a54A3D95721E086bC9F7F50ae6B6A2f440c5983,
            0xADF02BecE4427217C2e2f5c221F625b6bfC02d0d
        );
        tokens[43] = TokenInstance(
            "BMW.DE",
            0x2d5656B1861B7dE521dBd5dF8a0AaC3aA822D035,
            0x710645EE06D013581617f9fDbCcFbcc8D891D43a,
            0x11E2B27101A8074779195019937b43195234D1C8
        );
        tokens[44] = TokenInstance(
            "MC.PA",
            0x5c5957E4bDCE3845D21fa33a71F425D57da8e1a2,
            0x194C6Ebe9919C8681aa17C8814ee6c8A0534b28f,
            0x20BAdF51225A689B3C5b17eAA71927c1D3C1d481
        );
        tokens[45] = TokenInstance(
            "SIE.DE",
            0x56371804af362136D8f6F6b9ECd21D3e5c8dA740,
            0xEA6093BAD015aF29ADfa4013904e0f75f140b59b,
            0x795B83223EC78f2Ba6abD2Db23ddd4D6163A4e5C
        );
        tokens[46] = TokenInstance(
            "MBG.DE",
            0x22122e8717ef11FE544495e700a1Fba8B5aF3d07,
            0xa814255182F68cd5176bdb356A57411340F87d84,
            0x3ef1367B12A4099caa73A003a4DB273Dd9a11E18
        );
        tokens[47] = TokenInstance(
            "RHM.DE",
            0x8F63D208EFD46bD8632d93e97f9bA3A53089AF11,
            0xc6E584f4341E418962A0DDe3F2969B6be58f1920,
            0x83f8828b6EAd177Fb3D516b3dD7C2E96c39F84CE
        );
        tokens[48] = TokenInstance(
            "MCD",
            0x78182C3f2940a335A6D79BFCAFa1E10cD9abe17A,
            0x1169CDA99AeC045f9A42227D32DF005650Bc0d9D,
            0xf0FA8bC5ca94BeE5074dA2467dF3c8057a2D0502
        );
        tokens[49] = TokenInstance(
            "NKE",
            0x883588E050768B90eacf49e24C1fb0554815B133,
            0x2FA89b48915FDaa098E0d2Eb61ff7a72760A558C,
            0x1Cf7DCAd8f2Cd57FD84B3058eB389a31BD49C47e
        );
        tokens[50] = TokenInstance(
            "GRND",
            0xF0F9bbC8D7c862DEa88F89FEb127cB78BC0b20f1,
            0x4fdCE96b5EB6545C157619f835DA16dc71DE5E2e,
            0x473E004a6d659ea17666100A445C79A5171D2D9b
        );
        tokens[51] = TokenInstance(
            "DNUT",
            0x8E6176f684Ed70A790B86B69F1F7Fa5ac45Ce299,
            0x543e33E9276Cf00B74689c8E41FD7fC921128ba0,
            0x52f2718831848dC72867198d73bA7a53737019e8
        );
        tokens[52] = TokenInstance(
            "PLBY",
            0x80c55176C9F1D155B0B8E546e49368516813a8ec,
            0xE2593dB54E7893d311cBF5087CDB7a9027b9a7fD,
            0x1007B4ad2c1f29ebf5897F8a49494FB8a1f12dE2
        );
        tokens[53] = TokenInstance(
            "TR",
            0xFeBDb50a8256c762E219a66047155D1927d68A63,
            0xc67038BbFf91F2568B902ff171E9f9C06ed98815,
            0xCf819a3E3746B543343D268B092BaB5244F8fE12
        );
        tokens[54] = TokenInstance(
            "WEN",
            0x8c7D787e6377B1f07bf5f644fB6A5629506FEA3e,
            0xBCA97cc57916734130c9f05eA8B217682A249b75,
            0x82894CeD5F0b7009E4D531abe81863A523F4d9A5
        );
        tokens[55] = TokenInstance(
            "FGI",
            0xE05a93a2d1D0E8bA13F2bC0D1017Cb0D93308F4e,
            0x042Dfd33De6766a8858f188DFcf207D311da6488,
            0x5A5c3b64907823b1c5ea9d75D5AF44dFD06b03ea
        );
    }

    /// @notice Returns the 56 production receipt vault addresses on Base, in
    /// the order they were deployed. Provided so consumers (e.g. invariant
    /// assertions, migration scripts) can iterate without hardcoding the
    /// list inline.
    /// @dev Derived from `productionTokensBase()` so the token table is the
    /// single source of truth and the two accessors cannot drift.
    /// @return vaults The 56 production receipt vault addresses on Base.
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

    /// @notice Migration-window variant of `assertUniformOwnership`: every
    /// receipt vault in the supplied table must report `pre` OR `post` as
    /// `owner()` before `deadline`, and exactly `post` at/after it. Lets
    /// the governance-timelock ownership invariant merge alongside the
    /// migration script instead of waiting for on-chain execution — both
    /// sides of the transition are cron-covered, and a migration left
    /// un-run past the deadline red-lines via `MigrationDeadlinePassed`.
    /// @dev Each vault is asserted independently, so a half-landed
    /// migration (some vaults on `pre`, some on `post`) passes before the
    /// deadline — the bundle is atomic per Safe execution, but this leg
    /// does not assume that. Any third owner trips `MigrationStateDrift`
    /// immediately regardless of the deadline.
    /// @param tokens The token table whose receipt vaults are checked.
    /// @param pre The accepted owner before the migration runs.
    /// @param post The accepted owner after the migration runs.
    /// @param deadline Unix timestamp past which only `post` is accepted.
    function assertUniformOwnershipMigration(TokenInstance[] memory tokens, address pre, address post, uint256 deadline)
        internal
        view
    {
        for (uint256 i = 0; i < tokens.length; i++) {
            LibMigrationInvariant.assertMigration(
                "receiptVault.owner()", IOwnable(tokens[i].receiptVault).owner(), pre, post, deadline
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
    /// meaningful once the Safe itself has been validated. The authoriser is
    /// parameterised rather than hardcoded so this lib stays free of
    /// cross-facet dependencies; the orchestrator supplies the pinned address.
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

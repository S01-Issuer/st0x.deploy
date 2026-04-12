// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title LibProdTokensBase
/// @notice Production token instance addresses on Base. These are beacon proxy
/// instances created via the V1 deployer, not implementation contracts.
/// Each token set consists of a receipt (ERC-1155), receipt vault (ERC-20),
/// and wrapped token vault (ERC-4626).
library LibProdTokensBase {
    // =========================================================================
    // tMSTR / wtMSTR — MicroStrategy Incorporated ST0x
    // Deployed via V1 OffchainAssetReceiptVaultBeaconSetDeployer + V1 StoxWrappedTokenVaultBeaconSetDeployer
    // =========================================================================

    /// @dev Receipt (ERC-1155) for tMSTR.
    /// https://basescan.org/address/0x1c1fEF6f7b8e576219554b1d11c8aF29D00C0cEC
    address constant MSTR_RECEIPT = address(0x1c1fEF6f7b8e576219554b1d11c8aF29D00C0cEC);

    /// @dev Receipt vault (ERC-20, "tMSTR") — the OffchainAssetReceiptVault instance.
    /// https://basescan.org/address/0x013b782F402d61aa1004CCA95b9f5Bb402c9d5FE
    address constant MSTR_RECEIPT_VAULT = address(0x013b782F402d61aa1004CCA95b9f5Bb402c9d5FE);

    /// @dev Wrapped token vault (ERC-4626, "wtMSTR") — the StoxWrappedTokenVault instance.
    /// https://basescan.org/address/0xFF05E1bD696900dc6A52CA35Ca61Bb1024eDa8e2
    address constant MSTR_WRAPPED_TOKEN_VAULT = address(0xFF05E1bD696900dc6A52CA35Ca61Bb1024eDa8e2);

    // =========================================================================
    // tTSLA / wtTSLA — Tesla Inc ST0x
    // =========================================================================

    /// @dev Receipt (ERC-1155) for tTSLA.
    /// https://basescan.org/address/0x660923230fAA859622711a5fC80f532dd588b125
    address constant TSLA_RECEIPT = address(0x660923230fAA859622711a5fC80f532dd588b125);

    /// @dev Receipt vault (ERC-20, "tTSLA") — the OffchainAssetReceiptVault instance.
    /// https://basescan.org/address/0x4E169cD2Ab4f82640a8c65C68feD55863866fDB0
    address constant TSLA_RECEIPT_VAULT = address(0x4E169cD2Ab4f82640a8c65C68feD55863866fDB0);

    /// @dev Wrapped token vault (ERC-4626, "wtTSLA") — the StoxWrappedTokenVault instance.
    /// https://basescan.org/address/0x219A8d384a10BF19b9f24cB5cC53F79Dd0e5A03D
    address constant TSLA_WRAPPED_TOKEN_VAULT = address(0x219A8d384a10BF19b9f24cB5cC53F79Dd0e5A03D);

    // =========================================================================
    // tCOIN / wtCOIN — Coinbase Global Inc ST0x
    // =========================================================================

    /// @dev Receipt (ERC-1155) for tCOIN.
    /// https://basescan.org/address/0xBA1B8836A5510815e96103F067715b7CCC7c2E0E
    address constant COIN_RECEIPT = address(0xBA1B8836A5510815e96103F067715b7CCC7c2E0E);

    /// @dev Receipt vault (ERC-20, "tCOIN") — the OffchainAssetReceiptVault instance.
    /// https://basescan.org/address/0x626757e6F50675D17fcAd312E82f989aE7A23d38
    address constant COIN_RECEIPT_VAULT = address(0x626757e6F50675D17fcAd312E82f989aE7A23d38);

    /// @dev Wrapped token vault (ERC-4626, "wtCOIN") — the StoxWrappedTokenVault instance.
    /// https://basescan.org/address/0x5cDa0E1CA4ce2af96315f7F8963C85399c172204
    address constant COIN_WRAPPED_TOKEN_VAULT = address(0x5cDa0E1CA4ce2af96315f7F8963C85399c172204);

    // =========================================================================
    // tSPYM / wtSPYM — State Street SPDR Portfolio S&P 500 ETF ST0x
    // =========================================================================

    /// @dev Receipt (ERC-1155) for tSPYM.
    /// https://basescan.org/address/0x957056dD6e2E594742E36675e8AA5A567163E5bd
    address constant SPYM_RECEIPT = address(0x957056dD6e2E594742E36675e8AA5A567163E5bd);

    /// @dev Receipt vault (ERC-20, "tSPYM") — the OffchainAssetReceiptVault instance.
    /// https://basescan.org/address/0x8Fdf41116F755771Bfe0747D5F8C3711D5DEbfBb
    address constant SPYM_RECEIPT_VAULT = address(0x8Fdf41116F755771Bfe0747D5F8C3711D5DEbfBb);

    /// @dev Wrapped token vault (ERC-4626, "wtSPYM") — the StoxWrappedTokenVault instance.
    /// https://basescan.org/address/0x31C2C14134e6E3B7ef9478297F199331133Fc2d8
    address constant SPYM_WRAPPED_TOKEN_VAULT = address(0x31C2C14134e6E3B7ef9478297F199331133Fc2d8);

    // =========================================================================
    // tSIVR / wtSIVR — abrdn Physical Silver Shares ETF ST0x
    // =========================================================================

    /// @dev Receipt (ERC-1155) for tSIVR.
    /// https://basescan.org/address/0x053F52109a3439b4F292056D2DceC0486B544e82
    address constant SIVR_RECEIPT = address(0x053F52109a3439b4F292056D2DceC0486B544e82);

    /// @dev Receipt vault (ERC-20, "tSIVR") — the OffchainAssetReceiptVault instance.
    /// https://basescan.org/address/0x58cE5024B89B4f73C27814C0f0aBbEa331C99Be8
    address constant SIVR_RECEIPT_VAULT = address(0x58cE5024B89B4f73C27814C0f0aBbEa331C99Be8);

    /// @dev Wrapped token vault (ERC-4626, "wtSIVR") — the StoxWrappedTokenVault instance.
    /// https://basescan.org/address/0xEB7F3E4093C9d68253b6104FbbfF561F3eC0442F
    address constant SIVR_WRAPPED_TOKEN_VAULT = address(0xEB7F3E4093C9d68253b6104FbbfF561F3eC0442F);

    // =========================================================================
    // tCRCL / wtCRCL — Circle Internet Group Inc ST0x
    // =========================================================================

    /// @dev Receipt (ERC-1155) for tCRCL.
    /// https://basescan.org/address/0xd508B97975fBE04E62bFf18959549b046bD8FA78
    address constant CRCL_RECEIPT = address(0xd508B97975fBE04E62bFf18959549b046bD8FA78);

    /// @dev Receipt vault (ERC-20, "tCRCL") — the OffchainAssetReceiptVault instance.
    /// https://basescan.org/address/0x38Eb797892ED71Da69bDc27A456A7c83Ff813b52
    address constant CRCL_RECEIPT_VAULT = address(0x38Eb797892ED71Da69bDc27A456A7c83Ff813b52);

    /// @dev Wrapped token vault (ERC-4626, "wtCRCL") — the StoxWrappedTokenVault instance.
    /// https://basescan.org/address/0x8AFba81DEc38DE0A18E2Df5E1967a7493651eebf
    address constant CRCL_WRAPPED_TOKEN_VAULT = address(0x8AFba81DEc38DE0A18E2Df5E1967a7493651eebf);

    // =========================================================================
    // tNVDA / wtNVDA — NVIDIA Corporation ST0x
    // =========================================================================

    /// @dev Receipt (ERC-1155) for tNVDA.
    /// https://basescan.org/address/0x8Dd4c6f08E446075879310AFae8167CC4DE2f805
    address constant NVDA_RECEIPT = address(0x8Dd4c6f08E446075879310AFae8167CC4DE2f805);

    /// @dev Receipt vault (ERC-20, "tNVDA") — the OffchainAssetReceiptVault instance.
    /// https://basescan.org/address/0x7271A3C91Bb6070eD09333B84a815949D4f16d14
    address constant NVDA_RECEIPT_VAULT = address(0x7271A3C91Bb6070eD09333B84a815949D4f16d14);

    /// @dev Wrapped token vault (ERC-4626, "wtNVDA") — the StoxWrappedTokenVault instance.
    /// https://basescan.org/address/0xFb5B41acdbA20a3230F84BE995173CFb98b8D6E7
    address constant NVDA_WRAPPED_TOKEN_VAULT = address(0xFb5B41acdbA20a3230F84BE995173CFb98b8D6E7);

    // =========================================================================
    // tIAU / wtIAU — iShares Gold Trust ST0x
    // =========================================================================

    /// @dev Receipt (ERC-1155) for tIAU.
    /// https://basescan.org/address/0x9E128159ff53Ce113df52D760C032DD65DDb0E64
    address constant IAU_RECEIPT = address(0x9E128159ff53Ce113df52D760C032DD65DDb0E64);

    /// @dev Receipt vault (ERC-20, "tIAU") — the OffchainAssetReceiptVault instance.
    /// https://basescan.org/address/0x9A507314EA2a6C5686C0D07BfecB764dCF324dFF
    address constant IAU_RECEIPT_VAULT = address(0x9A507314EA2a6C5686C0D07BfecB764dCF324dFF);

    /// @dev Wrapped token vault (ERC-4626, "wtIAU") — the StoxWrappedTokenVault instance.
    /// https://basescan.org/address/0x1E46d7eFef64A833AFB1CD49299a7AD5B439f4d8
    address constant IAU_WRAPPED_TOKEN_VAULT = address(0x1E46d7eFef64A833AFB1CD49299a7AD5B439f4d8);

    // =========================================================================
    // tPPLT / wtPPLT — abrdn Physical Platinum Shares ETF ST0x
    // =========================================================================

    /// @dev Receipt (ERC-1155) for tPPLT.
    /// https://basescan.org/address/0x61b5a0424cD3adcd3b312619fC58B6fCeFA1ECb6
    address constant PPLT_RECEIPT = address(0x61b5a0424cD3adcd3b312619fC58B6fCeFA1ECb6);

    /// @dev Receipt vault (ERC-20, "tPPLT") — the OffchainAssetReceiptVault instance.
    /// https://basescan.org/address/0x1f17523b147CcC2A2328c0F014f6d49c479ea063
    address constant PPLT_RECEIPT_VAULT = address(0x1f17523b147CcC2A2328c0F014f6d49c479ea063);

    /// @dev Wrapped token vault (ERC-4626, "wtPPLT") — the StoxWrappedTokenVault instance.
    /// https://basescan.org/address/0x82f5BAEE1076334357a34A19E04f7c282D51cE47
    address constant PPLT_WRAPPED_TOKEN_VAULT = address(0x82f5BAEE1076334357a34A19E04f7c282D51cE47);

    // =========================================================================
    // tAMZN / wtAMZN — Amazon.com Inc ST0x
    // =========================================================================

    /// @dev Receipt (ERC-1155) for tAMZN.
    /// https://basescan.org/address/0x3C4895df971e5c1fDCa81bF74aDb8eeE94F24721
    address constant AMZN_RECEIPT = address(0x3C4895df971e5c1fDCa81bF74aDb8eeE94F24721);

    /// @dev Receipt vault (ERC-20, "tAMZN") — the OffchainAssetReceiptVault instance.
    /// https://basescan.org/address/0x466CB2e46Fa1AfC0AB5e22274B34d0391db18eFd
    address constant AMZN_RECEIPT_VAULT = address(0x466CB2e46Fa1AfC0AB5e22274B34d0391db18eFd);

    /// @dev Wrapped token vault (ERC-4626, "wtAMZN") — the StoxWrappedTokenVault instance.
    /// https://basescan.org/address/0x997baE3EC193a249596d3708C3fAB7C501Bb8a53
    address constant AMZN_WRAPPED_TOKEN_VAULT = address(0x997baE3EC193a249596d3708C3fAB7C501Bb8a53);

    // =========================================================================
    // tBMNR / wtBMNR — Bitmine Immersion Technologies, Inc ST0x
    // =========================================================================

    /// @dev Receipt (ERC-1155) for tBMNR.
    /// https://basescan.org/address/0x67aeAFD8c274F62933fEc34E8c0724189AaD01fc
    address constant BMNR_RECEIPT = address(0x67aeAFD8c274F62933fEc34E8c0724189AaD01fc);

    /// @dev Receipt vault (ERC-20, "tBMNR") — the OffchainAssetReceiptVault instance.
    /// https://basescan.org/address/0xfBde45dF60249203b12148452fC77C3B5F811eB2
    address constant BMNR_RECEIPT_VAULT = address(0xfBde45dF60249203b12148452fC77C3B5F811eB2);

    /// @dev Wrapped token vault (ERC-4626, "wtBMNR") — the StoxWrappedTokenVault instance.
    /// https://basescan.org/address/0x2512EC661f0bA089c275EA105E31bAD6FcFcf319
    address constant BMNR_WRAPPED_TOKEN_VAULT = address(0x2512EC661f0bA089c275EA105E31bAD6FcFcf319);
}

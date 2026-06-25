// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IOwnable} from "../interface/IOwnable.sol";
import {IAuthorisable} from "../interface/IAuthorisable.sol";

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

    /// @notice The single authoriser every production receipt vault is gated
    /// by, as a token-side invariant. Pinned here as the expected value for
    /// `assertUniformAuthoriser`; updated post-swap when the receipt vaults
    /// are rewired onto a new authoriser clone.
    /// @dev Read from `authorizer()` on the live vaults on Base. A vault
    /// reporting any other authoriser is gated by a different RBAC contract
    /// than the rest of the system and trips the invariant.
    address internal constant STOX_PROD_AUTHORISER = address(0x35f9fA9d80aAF2B0fB27f0FF015641B3408d7456);

    /// @notice Returns the 13 production receipt vault addresses on Base, in
    /// the order they were deployed. Provided so consumers (e.g. invariant
    /// assertions, migration scripts) can iterate without hardcoding the
    /// list inline.
    /// @return vaults The 13 production receipt vault addresses on Base.
    function productionReceiptVaults() internal pure returns (address[] memory vaults) {
        vaults = new address[](13);
        vaults[0] = MSTR_RECEIPT_VAULT;
        vaults[1] = TSLA_RECEIPT_VAULT;
        vaults[2] = COIN_RECEIPT_VAULT;
        vaults[3] = SPYM_RECEIPT_VAULT;
        vaults[4] = SIVR_RECEIPT_VAULT;
        vaults[5] = CRCL_RECEIPT_VAULT;
        vaults[6] = NVDA_RECEIPT_VAULT;
        vaults[7] = IAU_RECEIPT_VAULT;
        vaults[8] = PPLT_RECEIPT_VAULT;
        vaults[9] = AMZN_RECEIPT_VAULT;
        vaults[10] = BMNR_RECEIPT_VAULT;
        vaults[11] = IBHG_RECEIPT_VAULT;
        vaults[12] = SGOV_RECEIPT_VAULT;
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
        address[] memory vaults = productionReceiptVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            address actualOwner = IOwnable(vaults[i]).owner();
            if (actualOwner != expectedOwner) {
                revert ReceiptVaultOwnerMismatch(vaults[i], expectedOwner, actualOwner);
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
        address[] memory vaults = productionReceiptVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            address actual = IAuthorisable(vaults[i]).authorizer();
            if (actual != expected) {
                revert ReceiptVaultAuthoriserMismatch(vaults[i], expected, actual);
            }
        }
    }

    /// @notice Full token-side invariant bundle: every production receipt
    /// vault reports the supplied Safe as its `owner()` AND the supplied
    /// authoriser as its `authorizer()`. Pre-flight / post-state hook for
    /// any script touching the production receipt vault set; consumers
    /// asserting the full production state (Safe + token + authoriser)
    /// compose this alongside `LibSafeInvariants.assertAll` and
    /// `LibAuthoriserInvariants.assertAll` via `LibInvariants.assertAll`.
    /// @dev Both legs run last in the composed bundle because each is
    /// `O(13)` external calls and only meaningful once the Safe itself
    /// has been validated. The authoriser is parameterised rather than
    /// hardcoded so this lib stays free of cross-facet dependencies; the
    /// orchestrator supplies the pinned address.
    /// @param safe The Safe address every production receipt vault is
    /// expected to report as `owner()`.
    /// @param expectedAuthoriser The authoriser address every production
    /// receipt vault is expected to report as `authorizer()`.
    function assertAll(address safe, address expectedAuthoriser) internal view {
        assertUniformOwnership(safe);
        assertUniformAuthoriser(expectedAuthoriser);
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @notice Minimal `Ownable`-like surface used by ST0x receipt vaults.
/// Every production receipt vault exposes `owner()`; this library only
/// needs the getter, not the transfer/renounce mutators.
interface IOwnable {
    /// @notice The current owner of the contract.
    /// @return The owner address.
    function owner() external view returns (address);
}

/// @notice A receipt vault's `owner()` does not match the caller-supplied
/// expected owner. Used by `assertUniformOwnership` to surface the exact
/// vault address that breaks the invariant rather than a generic mismatch.
/// @param vault The receipt vault whose owner was read.
/// @param expected The caller-supplied expected owner.
/// @param actual The owner address returned by `vault.owner()`.
error ReceiptVaultOwnerMismatch(address vault, address expected, address actual);

/// @title LibTokenOwnership
/// @notice Pinned addresses for the ST0x receipt vaults on Base and helpers
/// for asserting that every vault shares the same `owner()`. Used by the
/// RAI-296 migration tooling to confirm that the Safe whose threshold is
/// being changed actually controls every production vault before the
/// migration runs, and that no vault has drifted out of the shared
/// ownership set.
/// @dev Addresses are sourced from `st0x.registry/token-lists/base.json`
/// (`extensions.unwrappedAddress` per token entry). The legacy NVDA
/// receipt vault is included because it still has an `owner()` on chain
/// and so still participates in the uniform-ownership invariant; the
/// other "legacyAddress" entries in the registry are not receipt vaults
/// (they're older wrapper variants without a uniform `owner()` surface).
library LibTokenOwnership {
    /// @notice NVIDIA wtNVDA receipt vault — current.
    address internal constant ST0X_RECEIPT_VAULT_NVDA = 0x7271A3C91Bb6070eD09333B84a815949D4f16d14;

    /// @notice Amazon wtAMZN receipt vault — current.
    address internal constant ST0X_RECEIPT_VAULT_AMZN = 0x466CB2e46Fa1AfC0AB5e22274B34d0391db18eFd;

    /// @notice Tesla wtTSLA receipt vault — current.
    address internal constant ST0X_RECEIPT_VAULT_TSLA = 0x4E169cD2Ab4f82640a8c65C68feD55863866fDB0;

    /// @notice MicroStrategy wtMSTR receipt vault — current.
    address internal constant ST0X_RECEIPT_VAULT_MSTR = 0x013b782F402d61aa1004CCA95b9f5Bb402c9d5FE;

    /// @notice iShares Gold Trust wtIAU receipt vault — current.
    address internal constant ST0X_RECEIPT_VAULT_IAU = 0x9A507314EA2a6C5686C0D07BfecB764dCF324dFF;

    /// @notice Coinbase wtCOIN receipt vault — current.
    address internal constant ST0X_RECEIPT_VAULT_COIN = 0x626757e6F50675D17fcAd312E82f989aE7A23d38;

    /// @notice SPDR Portfolio S&P 500 wtSPYM receipt vault — current.
    address internal constant ST0X_RECEIPT_VAULT_SPYM = 0x8Fdf41116F755771Bfe0747D5F8C3711D5DEbfBb;

    /// @notice abrdn Physical Silver wtSIVR receipt vault — current.
    address internal constant ST0X_RECEIPT_VAULT_SIVR = 0x58cE5024B89B4f73C27814C0f0aBbEa331C99Be8;

    /// @notice Circle wtCRCL receipt vault — current.
    address internal constant ST0X_RECEIPT_VAULT_CRCL = 0x38Eb797892ED71Da69bDc27A456A7c83Ff813b52;

    /// @notice Bitmine Immersion wtBMNR receipt vault — current.
    address internal constant ST0X_RECEIPT_VAULT_BMNR = 0xfBde45dF60249203b12148452fC77C3B5F811eB2;

    /// @notice abrdn Physical Platinum wtPPLT receipt vault — current.
    address internal constant ST0X_RECEIPT_VAULT_PPLT = 0x1f17523b147CcC2A2328c0F014f6d49c479ea063;

    /// @notice iShares iBonds 2027 HY wtIBHG receipt vault — current.
    address internal constant ST0X_RECEIPT_VAULT_IBHG = 0x3c0F093aa1eD511910279b2C8d56eF5c96f1a6cF;

    /// @notice iShares 0-3 Month Treasury wtSGOV receipt vault — current.
    address internal constant ST0X_RECEIPT_VAULT_SGOV = 0xc941C1506B7555Ba8C506Fb6c9b9CC259902d612;

    /// @notice Legacy NVIDIA receipt vault. Still on chain with the same
    /// `owner()` surface as the current vaults, so still participates in
    /// the uniform-ownership invariant — drift here would indicate the
    /// legacy vault was sold/transferred without coordinating with the
    /// current Safe-managed ownership model.
    address internal constant ST0X_RECEIPT_VAULT_LEGACY_NVDA = 0x69FCA9f7fAd46a7eEF3aCeF5BEAc9Df5B7Eca73B;

    /// @notice The 13 production receipt vaults backing the current
    /// `wt<TICKER>` wrappers, in registry order (NVDA, AMZN, TSLA, MSTR,
    /// IAU, COIN, SPYM, SIVR, CRCL, BMNR, PPLT, IBHG, SGOV). Useful when
    /// callers want to assert against the live set without picking up the
    /// legacy NVDA vault. Order is fixed so callers can index into it
    /// against the registry without re-sorting.
    /// @return The current-production receipt vault addresses.
    function productionReceiptVaults() internal pure returns (address[] memory) {
        address[] memory vaults = new address[](13);
        vaults[0] = ST0X_RECEIPT_VAULT_NVDA;
        vaults[1] = ST0X_RECEIPT_VAULT_AMZN;
        vaults[2] = ST0X_RECEIPT_VAULT_TSLA;
        vaults[3] = ST0X_RECEIPT_VAULT_MSTR;
        vaults[4] = ST0X_RECEIPT_VAULT_IAU;
        vaults[5] = ST0X_RECEIPT_VAULT_COIN;
        vaults[6] = ST0X_RECEIPT_VAULT_SPYM;
        vaults[7] = ST0X_RECEIPT_VAULT_SIVR;
        vaults[8] = ST0X_RECEIPT_VAULT_CRCL;
        vaults[9] = ST0X_RECEIPT_VAULT_BMNR;
        vaults[10] = ST0X_RECEIPT_VAULT_PPLT;
        vaults[11] = ST0X_RECEIPT_VAULT_IBHG;
        vaults[12] = ST0X_RECEIPT_VAULT_SGOV;
        return vaults;
    }

    /// @notice All 14 receipt vaults the uniform-ownership invariant
    /// applies to: the 13 production vaults plus the legacy NVDA vault.
    /// This is the set callers should iterate when asserting "every ST0x
    /// receipt vault owns the same Safe".
    /// @return The production and legacy receipt vault addresses.
    function allReceiptVaults() internal pure returns (address[] memory) {
        address[] memory production = productionReceiptVaults();
        address[] memory all = new address[](production.length + 1);
        for (uint256 i = 0; i < production.length; i++) {
            all[i] = production[i];
        }
        all[production.length] = ST0X_RECEIPT_VAULT_LEGACY_NVDA;
        return all;
    }

    /// @notice Assert that every receipt vault returned by
    /// `allReceiptVaults()` has its `owner()` set to `expectedOwner`.
    /// Reverts with `ReceiptVaultOwnerMismatch` on first mismatch,
    /// surfacing the offending vault and both owners so the migration
    /// script's pre-flight pinpoints the drift.
    /// @param expectedOwner The owner every receipt vault is expected to
    /// report.
    function assertUniformOwnership(address expectedOwner) internal view {
        address[] memory vaults = allReceiptVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            address actualOwner = IOwnable(vaults[i]).owner();
            if (actualOwner != expectedOwner) {
                revert ReceiptVaultOwnerMismatch(vaults[i], expectedOwner, actualOwner);
            }
        }
    }
}

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
/// @notice Pinned addresses for the ST0x production receipt vaults on Base
/// and helpers for asserting that every vault shares the same `owner()`.
/// Consumed by the multisig threshold migration tooling to confirm that the
/// Safe whose threshold is being changed actually controls every production
/// vault before the migration runs, and that no vault has drifted out of
/// the shared ownership set.
/// @dev Addresses are sourced from `st0x.registry/token-lists/base.json`
/// (`extensions.unwrappedAddress` per token entry). Only the 13 current
/// production receipt vaults participate in the invariant — deprecated
/// (legacy) receipt vaults are intentionally excluded because they are not
/// part of ongoing operations and bundling them into an operational
/// invariant would tie live drift detection to assets that are no longer
/// actively managed.
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

    /// @notice The 13 production receipt vaults backing the current
    /// `wt<TICKER>` wrappers, in registry order (NVDA, AMZN, TSLA, MSTR,
    /// IAU, COIN, SPYM, SIVR, CRCL, BMNR, PPLT, IBHG, SGOV). Order is
    /// fixed so callers can index into it against the registry without
    /// re-sorting.
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

    /// @notice Assert that every receipt vault returned by
    /// `productionReceiptVaults()` has its `owner()` set to `expectedOwner`.
    /// Reverts with `ReceiptVaultOwnerMismatch` on first mismatch,
    /// surfacing the offending vault and both owners so the calling
    /// pre-flight pinpoints the drift.
    /// @param expectedOwner The owner every production receipt vault is
    /// expected to report.
    function assertUniformOwnership(address expectedOwner) internal view {
        address[] memory vaults = productionReceiptVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            address actualOwner = IOwnable(vaults[i]).owner();
            if (actualOwner != expectedOwner) {
                revert ReceiptVaultOwnerMismatch(vaults[i], expectedOwner, actualOwner);
            }
        }
    }
}

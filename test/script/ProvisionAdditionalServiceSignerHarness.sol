// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ProvisionAdditionalServiceSigner} from "../../script/20260723-provision-additional-service-signer.s.sol";
import {RoleGrant} from "../../src/lib/LibAuthoriserInvariants.sol";
import {SafeTx} from "../../src/lib/LibSafeOps.sol";

/// @title ProvisionAdditionalServiceSignerHarness
/// @notice Exposes the script's internal bundle authoring so the selection
/// logic can be driven directly against any authoriser, and so
/// `vm.expectRevert` can intercept the typed errors it raises (a
/// library-internal revert inlines, and `expectRevert` only sees reverts
/// from a lower call depth than the cheatcode itself). Its own file because
/// Rain convention is one contract per .sol and
/// `rainix-sol-single-contract` enforces it. Mirrors
/// `test/script/DeployMissingTokensHarness.sol`.
contract ProvisionAdditionalServiceSignerHarness is ProvisionAdditionalServiceSigner {
    /// @notice The script's `authorBundle()`, externally callable.
    /// @param authoriser The authoriser whose live role state is read.
    /// @param safeAddr The token-owner Safe filling the map's Safe slots.
    /// @return additional The signer's canonical pairs, in map order.
    /// @return txs One `grantRole` tx per pair the signer does not hold.
    function callAuthorBundle(address authoriser, address safeAddr)
        external
        view
        returns (RoleGrant[] memory additional, SafeTx[] memory txs)
    {
        return authorBundle(authoriser, safeAddr);
    }
}

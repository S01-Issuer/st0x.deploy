// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RevokeFireblocksServiceSigner} from "../../script/20260810-revoke-fireblocks-service-signer.s.sol";
import {RoleGrant} from "../../src/lib/LibAuthoriserInvariants.sol";
import {SafeTx} from "../../src/lib/LibSafeOps.sol";

/// @title RevokeFireblocksServiceSignerHarness
/// @notice Exposes the script's internal bundle authoring so the selection
/// logic can be driven directly against any authoriser, and so
/// `vm.expectRevert` can intercept the typed errors it raises (a
/// library-internal revert inlines, and `expectRevert` only sees reverts
/// from a lower call depth than the cheatcode itself). Its own file because
/// Rain convention is one contract per .sol and
/// `rainix-sol-single-contract` enforces it. Mirrors
/// `test/script/ProvisionAdditionalServiceSignerHarness.sol`.
contract RevokeFireblocksServiceSignerHarness is RevokeFireblocksServiceSigner {
    /// @notice The script's `authorBundle()`, externally callable.
    /// @param authoriser The authoriser whose live role state is read.
    /// @param safeAddr The token-owner Safe filling the map's Safe slots.
    /// @return retired The retired signer's canonical pairs, in map order.
    /// @return txs One `revokeRole` tx per pair the signer still holds.
    function callAuthorBundle(address authoriser, address safeAddr)
        external
        view
        returns (RoleGrant[] memory retired, SafeTx[] memory txs)
    {
        return authorBundle(authoriser, safeAddr);
    }
}

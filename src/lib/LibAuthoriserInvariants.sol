// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibSafeInvariants} from "./LibSafeInvariants.sol";

/// @notice A pinned `(role, grantee)` pair on the live authoriser.
struct RoleGrant {
    bytes32 role;
    address grantee;
}

/// @notice An expected `(role, grantee)` pair is not held on the authoriser.
/// Surfaces the exact pair that breaks the role-grant invariant rather than
/// a generic mismatch.
/// @param authoriser The authoriser address inspected.
/// @param role The role that should be held.
/// @param grantee The grantee that should hold the role.
error ExpectedGrantMissing(address authoriser, bytes32 role, address grantee);

/// @title LibAuthoriserInvariants
/// @notice Reusable invariants for the ST0x production authoriser on Base:
/// the pinned current-state authoriser address, the expected impl behind
/// it, the grantee constants, and the full `(role, grantee)` map enumerated
/// from `RoleGranted` / `RoleRevoked` events on-chain. Each assertion
/// either returns silently when the invariant holds against the live chain
/// state or reverts with a typed error that pinpoints the drift.
/// @dev Owns both the current-state pins and the assert functions. When the
/// authoriser-swap script lands and the live authoriser changes, the pins
/// here are updated (current → new clone address + new impl) so future
/// `assertAll` runs validate the new live state. The role-grant map
/// (`expectedGrants`) does not change pre / post swap because the swap
/// mirrors the same grants forward.
///
/// Composed into `LibInvariants.assertAll` alongside `LibSafeInvariants`
/// and `LibTokenInvariants`; individually callable via `assertAll()` for
/// the focused authoriser drift detector.
///
/// The V4 clone deploy target (the address the upcoming swap script
/// `setAuthorizer`s every receipt vault onto) does **not** live here —
/// that's a deploy artifact, pinned in `LibProdDeployV4`. This lib only
/// holds what the live authoriser **should** look like today.
library LibAuthoriserInvariants {
    /// @notice The current live ST0x authoriser clone on Base. Every
    /// production receipt vault's `authorizer()` returns this address.
    /// Pinned as the current-state invariant; updated post-swap when the
    /// receipt vaults are rewired onto a new authoriser clone, so future
    /// runs of `assertAll` validate the new live state.
    /// https://basescan.org/address/0x35f9fa9d80aaf2b0fb27f0ff015641b3408d7456
    address internal constant STOX_PROD_AUTHORISER = 0x35f9fA9d80aAF2B0fB27f0FF015641B3408d7456;

    /// @notice The implementation behind the live clone. A base
    /// `OffchainAssetReceiptVaultAuthorizerV1` from rain-vats that predates
    /// the corporate-action role-admin extension. Pinned as the
    /// current-state invariant; updated alongside `STOX_PROD_AUTHORISER`
    /// when the live clone changes.
    /// https://basescan.org/address/0x2b4a510c3619d5e888095bfe9f95902d32da5556
    address internal constant STOX_PROD_AUTHORISER_IMPL = 0x2B4A510c3619d5E888095BFE9f95902D32dA5556;

    /// @notice The base role-admin hierarchy used by the live authoriser
    /// sets `<ROLE>_ADMIN` as the admin of each action role rather than
    /// `DEFAULT_ADMIN_ROLE`. Consequently no `DEFAULT_ADMIN_ROLE` grant was
    /// emitted at init and no address holds it. Pinned as the explicit
    /// expectation so the invariant flags any future grant of
    /// `DEFAULT_ADMIN_ROLE` as unexpected.
    bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);

    /// @notice The ST0x token-owner Safe — holds every `_ADMIN` role on the
    /// live authoriser (set at init) and was later granted DEPOSIT, WITHDRAW
    /// and CERTIFY as a privileged operator. Identical to
    /// `LibSafeInvariants.STOX_TOKEN_OWNER_SAFE`; re-exported as a grantee
    /// constant for call-site clarity.
    address internal constant GRANTEE_TOKEN_OWNER_SAFE = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;

    /// @notice External service EOA granted `DEPOSIT` (block 41797262),
    /// `WITHDRAW` (block 41797281) and `CERTIFY` (block 41797297) shortly
    /// after the first service was provisioned. EOA, active service signer.
    /// @dev TODO: confirm identity and rename.
    /// https://basescan.org/address/0x1c66d6708914c40239d54919320b4c48cae3d1a9
    address internal constant GRANTEE_SERVICE_1C66 = 0x1c66D6708914C40239D54919320b4C48cAE3D1A9;

    /// @notice The full `(role, grantee)` map in effect on the live
    /// authoriser. Source of truth folded from `RoleGranted` /
    /// `RoleRevoked` event scan on Base. The 11 entries split into: 5
    /// `_ADMIN` roles held by the token-owner Safe (set at init), 3 action
    /// roles for the service EOA, 3 action roles the Safe later granted
    /// itself for direct operational use.
    /// @return grants The pinned `(role, grantee)` pairs.
    function expectedGrants() internal pure returns (RoleGrant[] memory grants) {
        grants = new RoleGrant[](11);

        // Init grants (block 41715184) — Safe receives every `_ADMIN` role.
        grants[0] = RoleGrant(keccak256("DEPOSIT_ADMIN"), GRANTEE_TOKEN_OWNER_SAFE);
        grants[1] = RoleGrant(keccak256("WITHDRAW_ADMIN"), GRANTEE_TOKEN_OWNER_SAFE);
        grants[2] = RoleGrant(keccak256("CERTIFY_ADMIN"), GRANTEE_TOKEN_OWNER_SAFE);
        grants[3] = RoleGrant(keccak256("CONFISCATE_SHARES_ADMIN"), GRANTEE_TOKEN_OWNER_SAFE);
        grants[4] = RoleGrant(keccak256("CONFISCATE_RECEIPT_ADMIN"), GRANTEE_TOKEN_OWNER_SAFE);

        // Service EOA provisioned at blocks 41797262, 41797281, 41797297.
        grants[5] = RoleGrant(keccak256("DEPOSIT"), GRANTEE_SERVICE_1C66);
        grants[6] = RoleGrant(keccak256("WITHDRAW"), GRANTEE_SERVICE_1C66);
        grants[7] = RoleGrant(keccak256("CERTIFY"), GRANTEE_SERVICE_1C66);

        // Safe later granted itself the corresponding action roles (blocks
        // 42704120, 42704140, 44076075) for direct operational use.
        grants[8] = RoleGrant(keccak256("DEPOSIT"), GRANTEE_TOKEN_OWNER_SAFE);
        grants[9] = RoleGrant(keccak256("WITHDRAW"), GRANTEE_TOKEN_OWNER_SAFE);
        grants[10] = RoleGrant(keccak256("CERTIFY"), GRANTEE_TOKEN_OWNER_SAFE);
    }

    /// @notice Assert every pinned `(role, grantee)` pair in
    /// `expectedGrants()` is held on the supplied authoriser. Reverts with
    /// `ExpectedGrantMissing` on the first pair that fails, surfacing the
    /// exact role + grantee that broke the invariant.
    /// @dev Parameterised on the authoriser address so the same assertion
    /// can run against the live current clone (pre-swap) AND against a
    /// freshly-deployed clone (the script's pre-flight on the swap target)
    /// without duplicating the iteration.
    /// @param authoriser The authoriser to validate.
    function assertExpectedGrants(address authoriser) internal view {
        IAccessControl acl = IAccessControl(authoriser);
        RoleGrant[] memory grants = expectedGrants();
        for (uint256 i = 0; i < grants.length; i++) {
            if (!acl.hasRole(grants[i].role, grants[i].grantee)) {
                revert ExpectedGrantMissing(authoriser, grants[i].role, grants[i].grantee);
            }
        }
    }

    /// @notice Full authoriser-side invariant bundle against the live
    /// pinned `STOX_PROD_AUTHORISER`. Pre-flight at the start of every
    /// migration script and prod-state fork test; if this passes silently
    /// the live authoriser is in its current expected state.
    /// @dev No-arg overload uses the lib's `STOX_PROD_AUTHORISER` constant.
    /// Composed into `LibInvariants.assertAll`.
    function assertAll() internal view {
        assertExpectedGrants(STOX_PROD_AUTHORISER);
    }
}

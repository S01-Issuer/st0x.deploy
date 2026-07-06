// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibSafeInvariants} from "./LibSafeInvariants.sol";
import {LibChainPrincipals, ChainPrincipals} from "./LibChainPrincipals.sol";
import {ERC1167_PREFIX, ERC1167_SUFFIX} from "rain-extrospection-0.1.1/src/lib/LibExtrospectERC1167Proxy.sol";

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

/// @notice A pinned grantee unexpectedly holds `DEFAULT_ADMIN_ROLE`. The role
/// hierarchy admins each action role by its own `<ROLE>_ADMIN`, never by
/// `DEFAULT_ADMIN_ROLE`, so a root-admin holder is an unexpected escalation
/// path outside the pinned grant map.
/// @param authoriser The authoriser inspected.
/// @param holder The grantee found to hold `DEFAULT_ADMIN_ROLE`.
error UnexpectedDefaultAdmin(address authoriser, address holder);

/// @notice The authoriser's runtime codehash is not the EIP-1167 minimal-proxy
/// codehash of the pinned `STOX_PROD_AUTHORISER_IMPL`, i.e. the clone does not
/// proxy the pinned implementation.
/// @param authoriser The authoriser inspected.
/// @param expected The EIP-1167(`STOX_PROD_AUTHORISER_IMPL`) codehash.
/// @param actual The codehash observed on-chain.
error AuthoriserImplCodehashMismatch(address authoriser, bytes32 expected, bytes32 actual);

/// @title LibAuthoriserInvariants
/// @notice Reusable invariants for the ST0x production authorisers: the
/// pinned current-state Base authoriser address, the expected impl behind
/// it, the grantee constants, and the `(role, grantee)` map — defined once
/// as a chain-parametric structure over `ChainPrincipals` and pinned
/// concretely for Base from the `RoleGranted` / `RoleRevoked` event history.
/// Each assertion either returns silently when the invariant holds against
/// the live chain state or reverts with a typed error that pinpoints the
/// drift.
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
    /// expectation so `assertExpectedGrants` reverts `UnexpectedDefaultAdmin`
    /// if any pinned grantee holds it.
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
    /// Identical to `LibChainPrincipals.SERVICE_SIGNER_BASE` (where the
    /// per-chain principal tables own the address); re-exported here for
    /// call-site clarity, mirroring `GRANTEE_TOKEN_OWNER_SAFE`.
    /// @dev TODO: confirm identity and rename.
    /// https://basescan.org/address/0x1c66d6708914c40239d54919320b4c48cae3d1a9
    address internal constant GRANTEE_SERVICE_1C66 = LibChainPrincipals.SERVICE_SIGNER_BASE;

    /// @notice The `(role, grantee)` map every ST0x authoriser carries,
    /// parameterised on the chain's principals. The STRUCTURE — 5 `_ADMIN`
    /// roles held by the token-owner Safe, 3 action roles for the service
    /// signer, 3 action roles held by the Safe directly — is identical on
    /// every chain; the supplied `ChainPrincipals` fills the address slots.
    /// On Base the structure is the folded `RoleGranted` / `RoleRevoked`
    /// event history (see `expectedGrants()`); on a bootstrap chain it is
    /// established in one shot by the grants-mirror bundle, which authors
    /// exactly this map.
    /// @param principals The chain's principal set to fill the grantee slots.
    /// @return grants The expected `(role, grantee)` pairs for that chain.
    function expectedGrants(ChainPrincipals memory principals) internal pure returns (RoleGrant[] memory grants) {
        grants = new RoleGrant[](11);

        // The token-owner Safe holds every `_ADMIN` role (set at authoriser
        // init on every chain).
        grants[0] = RoleGrant(keccak256("DEPOSIT_ADMIN"), principals.tokenOwnerSafe);
        grants[1] = RoleGrant(keccak256("WITHDRAW_ADMIN"), principals.tokenOwnerSafe);
        grants[2] = RoleGrant(keccak256("CERTIFY_ADMIN"), principals.tokenOwnerSafe);
        grants[3] = RoleGrant(keccak256("CONFISCATE_SHARES_ADMIN"), principals.tokenOwnerSafe);
        grants[4] = RoleGrant(keccak256("CONFISCATE_RECEIPT_ADMIN"), principals.tokenOwnerSafe);

        // The service signer holds the operational action roles.
        grants[5] = RoleGrant(keccak256("DEPOSIT"), principals.serviceSigner);
        grants[6] = RoleGrant(keccak256("WITHDRAW"), principals.serviceSigner);
        grants[7] = RoleGrant(keccak256("CERTIFY"), principals.serviceSigner);

        // The Safe holds the corresponding action roles for direct
        // operational use.
        grants[8] = RoleGrant(keccak256("DEPOSIT"), principals.tokenOwnerSafe);
        grants[9] = RoleGrant(keccak256("WITHDRAW"), principals.tokenOwnerSafe);
        grants[10] = RoleGrant(keccak256("CERTIFY"), principals.tokenOwnerSafe);
    }

    /// @notice The full `(role, grantee)` map in effect on the live Base
    /// authoriser. Source of truth folded from `RoleGranted` /
    /// `RoleRevoked` event scan on Base: the 5 `_ADMIN` grants landed at
    /// init (block 41715184), the service EOA's 3 action roles at blocks
    /// 41797262 / 41797281 / 41797297, and the Safe granted itself the 3
    /// action roles at blocks 42704120 / 42704140 / 44076075.
    /// @dev Delegates to the chain-parametric overload with Base's
    /// principals so the structure is defined exactly once.
    /// @return grants The pinned `(role, grantee)` pairs.
    function expectedGrants() internal pure returns (RoleGrant[] memory grants) {
        grants = expectedGrants(LibChainPrincipals.base());
    }

    /// @notice Assert every `(role, grantee)` pair from
    /// `expectedGrants(principals)` is held on the supplied authoriser, and
    /// that no principal holds `DEFAULT_ADMIN_ROLE`. Reverts with
    /// `UnexpectedDefaultAdmin` if a principal holds the root admin role,
    /// or `ExpectedGrantMissing` on the first missing pair, surfacing the exact
    /// role + grantee that broke the invariant.
    /// @dev Parameterised on the authoriser address so the same assertion
    /// can run against the live current clone (pre-swap) AND against a
    /// freshly-deployed clone (the script's pre-flight on the swap target)
    /// without duplicating the iteration; parameterised on the principals so
    /// the identical structural assertion runs against every chain's
    /// authoriser with that chain's principal table. The `DEFAULT_ADMIN_ROLE`
    /// check is a negative assertion over the supplied principals, not an
    /// exhaustive scan (a plain `AccessControl` cannot enumerate members).
    /// @param authoriser The authoriser to validate.
    /// @param principals The chain principals whose grant map is expected.
    function assertExpectedGrants(address authoriser, ChainPrincipals memory principals) internal view {
        IAccessControl acl = IAccessControl(authoriser);
        // No principal holds DEFAULT_ADMIN_ROLE: the hierarchy admins each
        // action role by its own `<ROLE>_ADMIN`, so a root-admin holder would
        // be an escalation path the expected map does not sanction.
        if (acl.hasRole(DEFAULT_ADMIN_ROLE, principals.tokenOwnerSafe)) {
            revert UnexpectedDefaultAdmin(authoriser, principals.tokenOwnerSafe);
        }
        if (acl.hasRole(DEFAULT_ADMIN_ROLE, principals.serviceSigner)) {
            revert UnexpectedDefaultAdmin(authoriser, principals.serviceSigner);
        }
        RoleGrant[] memory grants = expectedGrants(principals);
        for (uint256 i = 0; i < grants.length; i++) {
            if (!acl.hasRole(grants[i].role, grants[i].grantee)) {
                revert ExpectedGrantMissing(authoriser, grants[i].role, grants[i].grantee);
            }
        }
    }

    /// @notice Assert the pinned Base grant map (`expectedGrants()`) against
    /// the supplied authoriser. Delegates to the chain-parametric overload
    /// with Base's principals; existing Base-side scripts and pins call this.
    /// @param authoriser The authoriser to validate.
    function assertExpectedGrants(address authoriser) internal view {
        assertExpectedGrants(authoriser, LibChainPrincipals.base());
    }

    /// @notice Assert the authoriser's runtime codehash is the EIP-1167
    /// minimal-proxy codehash of the pinned `STOX_PROD_AUTHORISER_IMPL`, so the
    /// clone actually proxies the pinned implementation before any
    /// implementation-backed read (`hasRole`) is trusted. Mirrors the
    /// singleton-bytecode pin `LibSafeInvariants` applies to the Safe.
    /// @param authoriser The authoriser clone to validate.
    function assertImplPinned(address authoriser) internal view {
        bytes32 expected = keccak256(abi.encodePacked(ERC1167_PREFIX, STOX_PROD_AUTHORISER_IMPL, ERC1167_SUFFIX));
        bytes32 actual = authoriser.codehash;
        if (actual != expected) {
            revert AuthoriserImplCodehashMismatch(authoriser, expected, actual);
        }
    }

    /// @notice Full authoriser-side invariant bundle against the live pinned
    /// `STOX_PROD_AUTHORISER`: the clone proxies the pinned impl
    /// (`assertImplPinned`) and holds exactly the pinned grant map with no
    /// root admin (`assertExpectedGrants`). Pre-flight at the start of every
    /// migration script and prod-state fork test; if this passes silently the
    /// live authoriser is in its current expected state.
    /// @dev No-arg overload uses the lib's `STOX_PROD_AUTHORISER` constant.
    /// Composed into `LibInvariants.assertAll`.
    function assertAll() internal view {
        assertImplPinned(STOX_PROD_AUTHORISER);
        assertExpectedGrants(STOX_PROD_AUTHORISER);
    }
}

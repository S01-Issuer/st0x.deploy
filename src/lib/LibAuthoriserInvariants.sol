// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibSafeInvariants} from "./LibSafeInvariants.sol";
import {LibProdDeployV4} from "../generated/LibProdDeployV4.sol";

/// @notice A pinned `(role, grantee)` pair on the production authoriser.
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

/// @notice The authoriser's runtime codehash does not match the pinned
/// EIP-1167 minimal-proxy codehash, i.e. the clone does not proxy the
/// audited implementation.
/// @param authoriser The authoriser inspected.
/// @param expected The pinned EIP-1167 codehash.
/// @param actual The codehash observed on-chain.
error AuthoriserImplCodehashMismatch(address authoriser, bytes32 expected, bytes32 actual);

/// @title LibAuthoriserInvariants
/// @notice Reusable invariants for the ST0x production authoriser on Base:
/// the grantee constants and the single master `(role, grantee)` map every
/// consumer asserts. Each assertion either returns silently when the
/// invariant holds against the live chain state or reverts with a typed
/// error that pinpoints the drift.
/// @dev The authoriser-of-record is the V4 clone, whose ADDRESS and
/// CODEHASH pins live in `LibProdDeployV4` (the generated deploy lib) —
/// this lib consumes them rather than carrying copies. `assertAll()`
/// validates the V4 clone: codehash equals
/// `LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH` (the EIP-1167
/// runtime embedding the audited 0.1.1 authoriser impl, so a matching hash
/// proves which implementation the clone proxies) and the full
/// `expectedGrants()` map holds.
///
/// Composed into `LibInvariants.assertAll` alongside `LibSafeInvariants`
/// and `LibTokenInvariants`; individually callable via `assertAll()` for
/// the focused authoriser drift detector.
library LibAuthoriserInvariants {
    /// @notice THE current production authoriser — the single entrypoint
    /// every invariant and script reads. Aliases the V4 clone pinned in
    /// `LibProdDeployV4` (the generated deploy lib is the single source
    /// for the address; this constant is the semantic name "current
    /// authoriser"). Every production receipt vault's `authorizer()` must
    /// return this address — an expectation that goes green when the
    /// `20260623` swap bundle executes on Base.
    /// https://basescan.org/address/0x315b16faa6ee413fabca877d3851b3818369f0cd
    address internal constant STOX_PROD_AUTHORISER = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;

    /// @notice The role-admin hierarchy sets `<ROLE>_ADMIN` as the admin of
    /// each action role rather than `DEFAULT_ADMIN_ROLE`. Consequently no
    /// `DEFAULT_ADMIN_ROLE` grant was emitted at init and no address holds
    /// it. Pinned as the explicit expectation so `assertExpectedGrants`
    /// reverts `UnexpectedDefaultAdmin` if any pinned grantee holds it.
    bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);

    /// @notice The ST0x token-owner Safe — holds every `_ADMIN` role on the
    /// production authoriser and was later granted DEPOSIT, WITHDRAW and
    /// CERTIFY as a privileged operator. Identical to
    /// `LibSafeInvariants.STOX_TOKEN_OWNER_SAFE`; re-exported as a grantee
    /// constant for call-site clarity.
    address internal constant GRANTEE_TOKEN_OWNER_SAFE = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;

    /// @notice External service EOA granted `DEPOSIT` (block 41797262),
    /// `WITHDRAW` (block 41797281) and `CERTIFY` (block 41797297) shortly
    /// after the first service was provisioned. EOA, active service signer.
    /// @dev TODO: confirm identity and rename.
    /// https://basescan.org/address/0x1c66d6708914c40239d54919320b4c48cae3d1a9
    address internal constant GRANTEE_SERVICE_1C66 = 0x1c66D6708914C40239D54919320b4C48cAE3D1A9;

    /// @notice ADDITIONAL service EOA, holding the same three action roles
    /// as `GRANTEE_SERVICE_1C66` — both signers are active side by side.
    /// Provisioned on each live chain's authoriser by the
    /// `20260723-provision-additional-service-signer` Safe bundle; the
    /// ADDRESS is shared across chains while the grants are per-chain
    /// state.
    address internal constant GRANTEE_SERVICE_3D0C = 0x3d0CD66EFA66c05d86c3d4316B03eAE87ab9E8aE;

    /// @notice The full `(role, grantee)` map in effect on the Base
    /// production authoriser. Delegates to the Safe-parametric overload with
    /// Base's token-owner Safe.
    /// @return grants The pinned `(role, grantee)` pairs for Base.
    function expectedGrants() internal pure returns (RoleGrant[] memory grants) {
        grants = expectedGrants(GRANTEE_TOKEN_OWNER_SAFE);
    }

    /// @notice The canonical `(role, grantee)` map the current production
    /// authoriser must carry, parameterised on the chain's token-owner Safe
    /// (the STRUCTURE is chain-agnostic; service signers are shared across
    /// chains, the Safe address is per-chain). The single source of truth
    /// every live-state invariant asserts: a chain is red on any pair until
    /// the operation that grants it executes there, and drift-guarded
    /// thereafter.
    /// @param tokenOwnerSafe The chain's token-owner Safe filling the Safe
    /// grantee slots.
    /// @return grants The `(role, grantee)` pairs for that chain.
    function expectedGrants(address tokenOwnerSafe) internal pure returns (RoleGrant[] memory grants) {
        grants = new RoleGrant[](16);

        // Init grants (block 41715184 on Base) — Safe receives every `_ADMIN`.
        grants[0] = RoleGrant(keccak256("DEPOSIT_ADMIN"), tokenOwnerSafe);
        grants[1] = RoleGrant(keccak256("WITHDRAW_ADMIN"), tokenOwnerSafe);
        grants[2] = RoleGrant(keccak256("CERTIFY_ADMIN"), tokenOwnerSafe);
        grants[3] = RoleGrant(keccak256("CONFISCATE_SHARES_ADMIN"), tokenOwnerSafe);
        grants[4] = RoleGrant(keccak256("CONFISCATE_RECEIPT_ADMIN"), tokenOwnerSafe);

        // The two corporate-action admins the 0.1.1 impl adds. On Base the
        // clone-deploy broadcast transferred them to the Safe alongside the
        // other five and renounced them from the deploy key.
        grants[5] = RoleGrant(keccak256("SCHEDULE_CORPORATE_ACTION_ADMIN"), tokenOwnerSafe);
        grants[6] = RoleGrant(keccak256("CANCEL_CORPORATE_ACTION_ADMIN"), tokenOwnerSafe);

        // Service EOA provisioned at blocks 41797262, 41797281, 41797297 (Base).
        grants[7] = RoleGrant(keccak256("DEPOSIT"), GRANTEE_SERVICE_1C66);
        grants[8] = RoleGrant(keccak256("WITHDRAW"), GRANTEE_SERVICE_1C66);
        grants[9] = RoleGrant(keccak256("CERTIFY"), GRANTEE_SERVICE_1C66);

        // Safe holds the corresponding action roles (Base blocks 42704120,
        // 42704140, 44076075) for direct operational use.
        grants[10] = RoleGrant(keccak256("DEPOSIT"), tokenOwnerSafe);
        grants[11] = RoleGrant(keccak256("WITHDRAW"), tokenOwnerSafe);
        grants[12] = RoleGrant(keccak256("CERTIFY"), tokenOwnerSafe);

        // Additional service signer, provisioned by the 20260723 bundle
        // per chain.
        grants[13] = RoleGrant(keccak256("DEPOSIT"), GRANTEE_SERVICE_3D0C);
        grants[14] = RoleGrant(keccak256("WITHDRAW"), GRANTEE_SERVICE_3D0C);
        grants[15] = RoleGrant(keccak256("CERTIFY"), GRANTEE_SERVICE_3D0C);
    }

    /// @notice Assert every pinned `(role, grantee)` pair in
    /// `expectedGrants()` is held on the supplied authoriser, and that no
    /// pinned grantee holds `DEFAULT_ADMIN_ROLE`. Reverts with
    /// `UnexpectedDefaultAdmin` if a pinned grantee holds the root admin
    /// role, or `ExpectedGrantMissing` on the first missing pair, surfacing
    /// the exact role + grantee that broke the invariant.
    /// @dev Parameterised on the authoriser address so the same assertion
    /// can run against the pinned production clone AND against a
    /// freshly-deployed clone (a script's pre-flight on a swap target)
    /// without duplicating the iteration. The `DEFAULT_ADMIN_ROLE` check is
    /// a negative assertion over the pinned grantees, not an exhaustive
    /// scan (a plain `AccessControl` cannot enumerate members).
    /// @param authoriser The authoriser to validate.
    function assertExpectedGrants(address authoriser) internal view {
        assertExpectedGrants(authoriser, GRANTEE_TOKEN_OWNER_SAFE);
    }

    /// @notice Assert every `(role, grantee)` pair from
    /// `expectedGrants(tokenOwnerSafe)` is held on the supplied authoriser, and
    /// that neither the Safe nor the service signer holds `DEFAULT_ADMIN_ROLE`.
    /// Parameterised on the chain's token-owner Safe so the identical grant
    /// STRUCTURE is asserted against each chain's authoriser with that chain's
    /// Safe address (the service signer is shared).
    /// @param authoriser The authoriser to validate.
    /// @param tokenOwnerSafe The chain's token-owner Safe filling the Safe
    /// grantee slots.
    function assertExpectedGrants(address authoriser, address tokenOwnerSafe) internal view {
        IAccessControl acl = IAccessControl(authoriser);
        // No pinned grantee holds DEFAULT_ADMIN_ROLE: the hierarchy admins each
        // action role by its own `<ROLE>_ADMIN`, so a root-admin holder would
        // be an escalation path the pinned map does not sanction.
        if (acl.hasRole(DEFAULT_ADMIN_ROLE, tokenOwnerSafe)) {
            revert UnexpectedDefaultAdmin(authoriser, tokenOwnerSafe);
        }
        if (acl.hasRole(DEFAULT_ADMIN_ROLE, GRANTEE_SERVICE_1C66)) {
            revert UnexpectedDefaultAdmin(authoriser, GRANTEE_SERVICE_1C66);
        }
        if (acl.hasRole(DEFAULT_ADMIN_ROLE, GRANTEE_SERVICE_3D0C)) {
            revert UnexpectedDefaultAdmin(authoriser, GRANTEE_SERVICE_3D0C);
        }
        RoleGrant[] memory grants = expectedGrants(tokenOwnerSafe);
        for (uint256 i = 0; i < grants.length; i++) {
            if (!acl.hasRole(grants[i].role, grants[i].grantee)) {
                revert ExpectedGrantMissing(authoriser, grants[i].role, grants[i].grantee);
            }
        }
    }

    /// @notice Full authoriser-side invariant bundle against the current
    /// production authoriser (`STOX_PROD_AUTHORISER`): its codehash equals
    /// the pinned EIP-1167 runtime embedding the audited 0.1.1 authoriser
    /// impl (proving which implementation the clone proxies), and the full
    /// `expectedGrants()` map holds. Pre-flight at the start of every
    /// migration script and prod-state fork test; if this passes silently
    /// the production authoriser is in its expected state.
    /// @dev No-arg; composed into `LibInvariants.assertAll`. The retired
    /// V3 clone is deliberately NOT asserted — nothing references it.
    function assertAll() internal view {
        bytes32 expected = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH;
        bytes32 actual = STOX_PROD_AUTHORISER.codehash;
        if (actual != expected) {
            revert AuthoriserImplCodehashMismatch(STOX_PROD_AUTHORISER, expected, actual);
        }
        assertExpectedGrants(STOX_PROD_AUTHORISER);
    }
}

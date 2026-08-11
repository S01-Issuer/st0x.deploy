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

/// @notice The token-owner Safe still holds an `_ADMIN` role that the map
/// assigns to a distinct admin holder. The `_ADMIN` slice must be held
/// EXCLUSIVELY: a Safe that keeps a copy can grant or revoke action roles
/// directly, bypassing the delay the admin holder (the governance timelock)
/// exists to impose.
/// @param authoriser The authoriser inspected.
/// @param role The `_ADMIN` role the Safe unexpectedly retains.
/// @param holder The Safe retaining it.
error UnexpectedRetainedAdminGrant(address authoriser, bytes32 role, address holder);

/// @notice A `(role, grantee)` pair pinned as REVOKED is still held on the
/// authoriser. The retired grantee must hold none of its former roles; a
/// held pair is either an unexecuted revocation bundle or a re-grant
/// outside the pinned map.
/// @param authoriser The authoriser inspected.
/// @param role The role that must not be held.
/// @param grantee The grantee that must not hold it.
error RevokedGrantStillHeld(address authoriser, bytes32 role, address grantee);

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

    /// @notice The number of `_ADMIN` roles in the grant map — its LEADING
    /// slice, so `expectedGrants(...)[0..ADMIN_ROLE_COUNT)` are exactly the
    /// entries that track the admin holder. The slice's position and length
    /// are pinned by `testExpectedGrantsAdminHolderParameterisation`.
    uint256 internal constant ADMIN_ROLE_COUNT = 7;

    /// @notice The ST0x token-owner Safe — holds every `_ADMIN` role on the
    /// production authoriser and was later granted DEPOSIT, WITHDRAW and
    /// CERTIFY as a privileged operator. Identical to
    /// `LibSafeInvariants.STOX_TOKEN_OWNER_SAFE`; re-exported as a grantee
    /// constant for call-site clarity.
    address internal constant GRANTEE_TOKEN_OWNER_SAFE = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;

    /// @notice The RETIRED Fireblocks-custodied service EOA. Holds NO role
    /// on any chain's authoriser: its former action roles are pinned as
    /// revoked (`revokedGrants()`) and asserted ABSENT by
    /// `assertExpectedGrants`.
    /// https://basescan.org/address/0x1c66d6708914c40239d54919320b4c48cae3d1a9
    address internal constant GRANTEE_SERVICE_1C66 = 0x1c66D6708914C40239D54919320b4C48cAE3D1A9;

    /// @notice The active service EOA, holding `DEPOSIT`, `WITHDRAW` and
    /// `CERTIFY` on each chain's authoriser. The ADDRESS is shared across
    /// chains while the grants are per-chain state.
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
        grants = expectedGrants(tokenOwnerSafe, tokenOwnerSafe);
    }

    /// @notice The `(role, grantee)` map parameterised on BOTH the chain's
    /// token-owner Safe AND the holder of the seven `_ADMIN` roles. Before
    /// the governance-timelock migration the Safe is the admin holder (the
    /// two-arg call sites above collapse the parameters); after the
    /// migration the seven `_ADMIN` roles sit on the governance timelock
    /// while the Safe keeps its three direct action roles. This overload is
    /// the single map both states are expressed through, so the migration
    /// script's post-state and the post-migration invariant surface assert
    /// the same structure the pre-migration consumers do.
    /// @param tokenOwnerSafe The chain's token-owner Safe filling the
    /// operational Safe grantee slots.
    /// @param adminHolder The holder of the seven `_ADMIN` roles (the Safe
    /// pre-migration, the governance timelock post-migration).
    /// @return grants The `(role, grantee)` pairs for that chain.
    function expectedGrants(address tokenOwnerSafe, address adminHolder)
        internal
        pure
        returns (RoleGrant[] memory grants)
    {
        grants = new RoleGrant[](13);

        // Init grants (block 41715184 on Base) — the admin holder receives
        // every `_ADMIN` (the Safe at init; the governance timelock once the
        // timelock migration executes).
        grants[0] = RoleGrant(keccak256("DEPOSIT_ADMIN"), adminHolder);
        grants[1] = RoleGrant(keccak256("WITHDRAW_ADMIN"), adminHolder);
        grants[2] = RoleGrant(keccak256("CERTIFY_ADMIN"), adminHolder);
        grants[3] = RoleGrant(keccak256("CONFISCATE_SHARES_ADMIN"), adminHolder);
        grants[4] = RoleGrant(keccak256("CONFISCATE_RECEIPT_ADMIN"), adminHolder);

        // The two corporate-action admins the 0.1.1 impl adds. On Base the
        // clone-deploy broadcast transferred them to the Safe alongside the
        // other five and renounced them from the deploy key.
        grants[5] = RoleGrant(keccak256("SCHEDULE_CORPORATE_ACTION_ADMIN"), adminHolder);
        grants[6] = RoleGrant(keccak256("CANCEL_CORPORATE_ACTION_ADMIN"), adminHolder);

        // Safe holds the action roles (Base blocks 42704120, 42704140,
        // 44076075) for direct operational use.
        grants[7] = RoleGrant(keccak256("DEPOSIT"), tokenOwnerSafe);
        grants[8] = RoleGrant(keccak256("WITHDRAW"), tokenOwnerSafe);
        grants[9] = RoleGrant(keccak256("CERTIFY"), tokenOwnerSafe);

        // The active service signer.
        grants[10] = RoleGrant(keccak256("DEPOSIT"), GRANTEE_SERVICE_3D0C);
        grants[11] = RoleGrant(keccak256("WITHDRAW"), GRANTEE_SERVICE_3D0C);
        grants[12] = RoleGrant(keccak256("CERTIFY"), GRANTEE_SERVICE_3D0C);
    }

    /// @notice The `(role, grantee)` pairs pinned as REVOKED: the retired
    /// Fireblocks service signer's former action roles, which no authoriser
    /// may carry. The negative half of the canonical map — every consumer
    /// of `expectedGrants` asserts these pairs ABSENT via
    /// `assertExpectedGrants`.
    /// @return revoked The pinned revoked `(role, grantee)` pairs.
    function revokedGrants() internal pure returns (RoleGrant[] memory revoked) {
        revoked = new RoleGrant[](3);
        revoked[0] = RoleGrant(keccak256("DEPOSIT"), GRANTEE_SERVICE_1C66);
        revoked[1] = RoleGrant(keccak256("WITHDRAW"), GRANTEE_SERVICE_1C66);
        revoked[2] = RoleGrant(keccak256("CERTIFY"), GRANTEE_SERVICE_1C66);
    }

    /// @notice Assert every pinned `(role, grantee)` pair in
    /// `expectedGrants()` is held on the supplied authoriser, that every
    /// `revokedGrants()` pair is NOT held, and that no pinned grantee holds
    /// `DEFAULT_ADMIN_ROLE`. Reverts with `UnexpectedDefaultAdmin` if a
    /// pinned grantee holds the root admin role, `ExpectedGrantMissing` on
    /// the first missing pair, or `RevokedGrantStillHeld` on the first
    /// revoked pair still held, surfacing the exact role + grantee that
    /// broke the invariant.
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
    /// `expectedGrants(tokenOwnerSafe)` is held on the supplied authoriser,
    /// that every `revokedGrants()` pair is NOT held, and that no pinned
    /// grantee holds `DEFAULT_ADMIN_ROLE`. Parameterised on the chain's
    /// token-owner Safe so the identical grant STRUCTURE is asserted against
    /// each chain's authoriser with that chain's Safe address (the service
    /// signers are shared).
    /// @param authoriser The authoriser to validate.
    /// @param tokenOwnerSafe The chain's token-owner Safe filling the Safe
    /// grantee slots.
    function assertExpectedGrants(address authoriser, address tokenOwnerSafe) internal view {
        assertExpectedGrants(authoriser, tokenOwnerSafe, tokenOwnerSafe);
    }

    /// @notice Assert every `(role, grantee)` pair from
    /// `expectedGrants(tokenOwnerSafe, adminHolder)` is held on the supplied
    /// authoriser, that no named principal — the Safe, the admin holder,
    /// the service signer — holds `DEFAULT_ADMIN_ROLE`, and that when the
    /// admin holder is distinct from the Safe, the Safe retains NO `_ADMIN`
    /// entry (exclusive holding — a retained copy would let the Safe mutate
    /// the grant map without the admin holder's delay). This is the
    /// post-timelock-migration assertion surface: the migration script's
    /// post-state and the migration-window invariants call it with the
    /// governance timelock as `adminHolder`.
    /// @param authoriser The authoriser to validate.
    /// @param tokenOwnerSafe The chain's token-owner Safe filling the
    /// operational Safe grantee slots.
    /// @param adminHolder The holder of the seven `_ADMIN` roles.
    function assertExpectedGrants(address authoriser, address tokenOwnerSafe, address adminHolder) internal view {
        IAccessControl acl = IAccessControl(authoriser);
        assertNoRootAdminHolders(acl, authoriser, tokenOwnerSafe, adminHolder);
        RoleGrant[] memory grants = expectedGrants(tokenOwnerSafe, adminHolder);
        for (uint256 i = 0; i < grants.length; i++) {
            if (!acl.hasRole(grants[i].role, grants[i].grantee)) {
                revert ExpectedGrantMissing(authoriser, grants[i].role, grants[i].grantee);
            }
        }
        assertExclusiveAdminHolding(acl, authoriser, grants, tokenOwnerSafe, adminHolder);
        assertRevokedGrantsAbsent(acl, authoriser);
    }

    /// @notice Assert no pinned principal — the Safe, the admin holder, the
    /// service signers — holds `DEFAULT_ADMIN_ROLE`: the hierarchy admins
    /// each action role by its own `<ROLE>_ADMIN`, so a root-admin holder
    /// would be an escalation path the pinned map does not sanction.
    /// @param acl The authoriser's access-control surface.
    /// @param authoriser The authoriser under validation (surfaced in the
    /// revert).
    /// @param tokenOwnerSafe The chain's token-owner Safe.
    /// @param adminHolder The holder of the seven `_ADMIN` roles.
    function assertNoRootAdminHolders(
        IAccessControl acl,
        address authoriser,
        address tokenOwnerSafe,
        address adminHolder
    ) internal view {
        if (acl.hasRole(DEFAULT_ADMIN_ROLE, tokenOwnerSafe)) {
            revert UnexpectedDefaultAdmin(authoriser, tokenOwnerSafe);
        }
        if (acl.hasRole(DEFAULT_ADMIN_ROLE, adminHolder)) {
            revert UnexpectedDefaultAdmin(authoriser, adminHolder);
        }
        if (acl.hasRole(DEFAULT_ADMIN_ROLE, GRANTEE_SERVICE_1C66)) {
            revert UnexpectedDefaultAdmin(authoriser, GRANTEE_SERVICE_1C66);
        }
        if (acl.hasRole(DEFAULT_ADMIN_ROLE, GRANTEE_SERVICE_3D0C)) {
            revert UnexpectedDefaultAdmin(authoriser, GRANTEE_SERVICE_3D0C);
        }
    }

    /// @notice Assert exclusive `_ADMIN` holding: with a distinct admin
    /// holder, a Safe that retains any admin entry can grant or revoke
    /// action roles directly, bypassing the delay the admin holder exists
    /// to impose. The slice is positional (the map's leading
    /// `ADMIN_ROLE_COUNT` entries) rather than matched by grantee address,
    /// which would mis-slice if the admin holder aliased another grantee.
    /// No-op when the Safe IS the admin holder (the pre-migration state).
    /// @param acl The authoriser's access-control surface.
    /// @param authoriser The authoriser under validation (surfaced in the
    /// revert).
    /// @param grants The map from `expectedGrants(tokenOwnerSafe,
    /// adminHolder)`, whose leading slice carries the `_ADMIN` roles.
    /// @param tokenOwnerSafe The chain's token-owner Safe.
    /// @param adminHolder The holder of the seven `_ADMIN` roles.
    function assertExclusiveAdminHolding(
        IAccessControl acl,
        address authoriser,
        RoleGrant[] memory grants,
        address tokenOwnerSafe,
        address adminHolder
    ) internal view {
        if (adminHolder == tokenOwnerSafe) {
            return;
        }
        for (uint256 i = 0; i < ADMIN_ROLE_COUNT; i++) {
            if (acl.hasRole(grants[i].role, tokenOwnerSafe)) {
                revert UnexpectedRetainedAdminGrant(authoriser, grants[i].role, tokenOwnerSafe);
            }
        }
    }

    /// @notice Assert every `revokedGrants()` pair is absent: the retired
    /// service signer holds none of its former action roles.
    /// @param acl The authoriser's access-control surface.
    /// @param authoriser The authoriser under validation (surfaced in the
    /// revert).
    function assertRevokedGrantsAbsent(IAccessControl acl, address authoriser) internal view {
        RoleGrant[] memory revoked = revokedGrants();
        for (uint256 i = 0; i < revoked.length; i++) {
            if (acl.hasRole(revoked[i].role, revoked[i].grantee)) {
                revert RevokedGrantStillHeld(authoriser, revoked[i].role, revoked[i].grantee);
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

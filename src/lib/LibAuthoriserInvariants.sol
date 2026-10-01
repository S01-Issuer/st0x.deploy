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
/// @param authoriser The authoriser address inspected.
/// @param role The role that should be held.
/// @param grantee The grantee that should hold the role.
error ExpectedGrantMissing(address authoriser, bytes32 role, address grantee);

/// @notice A pinned grantee holds `DEFAULT_ADMIN_ROLE`. The role hierarchy
/// admins each action role by its own `<ROLE>_ADMIN`, never by
/// `DEFAULT_ADMIN_ROLE`, so no address holds it.
/// @param authoriser The authoriser inspected.
/// @param holder The grantee found to hold `DEFAULT_ADMIN_ROLE`.
error UnexpectedDefaultAdmin(address authoriser, address holder);

/// @notice The authoriser's runtime codehash does not match the pinned
/// EIP-1167 minimal-proxy codehash, i.e. the clone does not proxy the
/// pinned implementation.
/// @param authoriser The authoriser inspected.
/// @param expected The pinned EIP-1167 codehash.
/// @param actual The codehash observed on-chain.
error AuthoriserImplCodehashMismatch(address authoriser, bytes32 expected, bytes32 actual);

/// @notice The token-owner Safe holds an `_ADMIN` role that the map assigns
/// to a distinct admin holder. The `_ADMIN` slice is held exclusively: a
/// Safe that keeps a copy can grant or revoke action roles directly,
/// bypassing the delay the admin holder (the governance timelock) imposes.
/// @param authoriser The authoriser inspected.
/// @param role The `_ADMIN` role the Safe retains.
/// @param holder The Safe retaining it.
error UnexpectedRetainedAdminGrant(address authoriser, bytes32 role, address holder);

/// @notice The retired service signer holds an action role.
/// @param authoriser The authoriser carrying the unexpected grant.
/// @param role The action role the retired signer holds.
error UnexpectedRetiredSignerGrant(address authoriser, bytes32 role);

/// @notice Dispatched against a chain without a hydrated authoriser pin.
/// @param chainId The active chain id.
error UnsupportedChainForAuthoriser(uint256 chainId);

/// @notice The active chain's V4 authoriser is not ready (unpinned, no code,
/// or the wrong codehash).
/// @param authoriser The authoriser address inspected.
error AuthoriserNotReady(address authoriser);

/// @title LibAuthoriserInvariants
/// @notice Invariants for the ST0x production authoriser on every chain:
/// the grantee constants and the `(role, grantee)` map every consumer
/// asserts. Each assertion either returns silently when the invariant holds
/// against the live chain state or reverts with a typed error that
/// pinpoints the drift.
/// @dev The authoriser is the V4 clone, whose address and codehash pins live
/// in `LibProdDeployV4`. `assertAll()` validates the V4 clone: codehash
/// equals `LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH` (the
/// EIP-1167 runtime embedding the 0.1.1 authoriser impl, so a matching hash
/// proves which implementation the clone proxies) and the full
/// `expectedGrants()` map holds.
///
/// Composed into `LibInvariants.assertAll` alongside `LibSafeInvariants`
/// and `LibTokenInvariants`; individually callable via `assertAll()`.
library LibAuthoriserInvariants {
    /// @notice A chain's V4 authoriser clone pin, raw: `address(0)` while the
    /// slot is a placeholder. Reverts for a chain without a slot.
    /// @param chainId The chain id.
    /// @return The pinned clone, or zero for a placeholder slot.
    function authoriserForChainId(uint256 chainId) internal pure returns (address) {
        if (chainId == LibSafeInvariants.BASE_CHAIN_ID) {
            return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        }
        if (chainId == LibSafeInvariants.ETHEREUM_CHAIN_ID) {
            return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM;
        }
        if (chainId == LibSafeInvariants.HYPEREVM_CHAIN_ID) {
            return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM;
        }
        if (chainId == LibSafeInvariants.ROBINHOOD_CHAIN_ID) {
            return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ROBINHOOD;
        }
        if (chainId == LibSafeInvariants.BSC_CHAIN_ID) {
            return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_BSC;
        }
        revert UnsupportedChainForAuthoriser(chainId);
    }

    /// @notice The active chain's hydrated V4 authoriser clone, asserted
    /// deployed with the shared EIP-1167 codehash.
    /// @return authoriser The validated authoriser address.
    function activeChainAuthoriser() internal view returns (address authoriser) {
        authoriser = authoriserForChainId(block.chainid);
        if (
            authoriser == address(0) || authoriser.code.length == 0
                || authoriser.codehash != LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH
        ) {
            revert AuthoriserNotReady(authoriser);
        }
    }

    /// @notice The production authoriser on Base. Aliases the V4 clone
    /// pinned in `LibProdDeployV4`. Every production receipt vault's
    /// `authorizer()` returns this address.
    /// https://basescan.org/address/0x315b16faa6ee413fabca877d3851b3818369f0cd
    address internal constant STOX_PROD_AUTHORISER = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;

    /// @notice The role-admin hierarchy sets `<ROLE>_ADMIN` as the admin of
    /// each action role rather than `DEFAULT_ADMIN_ROLE`, so no address
    /// holds `DEFAULT_ADMIN_ROLE`. `assertExpectedGrants` reverts
    /// `UnexpectedDefaultAdmin` if any pinned grantee holds it.
    bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);

    /// @notice The number of `_ADMIN` roles in the grant map, its leading
    /// slice: `expectedGrants(...)[0..ADMIN_ROLE_COUNT)` are exactly the
    /// entries that track the admin holder.
    uint256 internal constant ADMIN_ROLE_COUNT = 7;

    /// @notice The ST0x token-owner Safe on Base, filling the Safe grantee
    /// slots of the grant map. Identical to
    /// `LibSafeInvariants.STOX_TOKEN_OWNER_SAFE`.
    address internal constant GRANTEE_TOKEN_OWNER_SAFE = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;

    /// @notice The retired service EOA. It holds no role on any chain's
    /// authoriser; `assertExpectedGrants` asserts that absence.
    /// https://basescan.org/address/0x1c66d6708914c40239d54919320b4c48cae3d1a9
    address internal constant GRANTEE_SERVICE_1C66 = 0x1c66D6708914C40239D54919320b4C48cAE3D1A9;

    /// @notice The service EOA holding the three action roles on each
    /// chain's authoriser. The address is shared across chains; the grants
    /// are per-chain state.
    address internal constant GRANTEE_SERVICE_3D0C = 0x3d0CD66EFA66c05d86c3d4316B03eAE87ab9E8aE;

    /// @notice The production orchestrator instance, holding `DEPOSIT` and
    /// `WITHDRAW` on each chain's authoriser. Same address on every chain.
    address internal constant GRANTEE_ORCHESTRATOR = LibProdDeployV4.ST0X_ORCHESTRATOR_INSTANCE;

    /// @notice The full `(role, grantee)` map in effect on the Base
    /// production authoriser. Delegates to the Safe-parametric overload with
    /// Base's token-owner Safe.
    /// @return grants The pinned `(role, grantee)` pairs for Base.
    function expectedGrants() internal pure returns (RoleGrant[] memory grants) {
        grants = expectedGrants(GRANTEE_TOKEN_OWNER_SAFE);
    }

    /// @notice The `(role, grantee)` map the production authoriser must
    /// carry, parameterised on the chain's token-owner Safe (the structure
    /// is chain-agnostic; service signers are shared across chains, the Safe
    /// address is per-chain).
    /// @param tokenOwnerSafe The chain's token-owner Safe filling the Safe
    /// grantee slots.
    /// @return grants The `(role, grantee)` pairs for that chain.
    function expectedGrants(address tokenOwnerSafe) internal pure returns (RoleGrant[] memory grants) {
        grants = expectedGrants(tokenOwnerSafe, tokenOwnerSafe);
    }

    /// @notice The `(role, grantee)` map parameterised on both the chain's
    /// token-owner Safe and the holder of the seven `_ADMIN` roles. Before
    /// the governance-timelock migration the Safe is the admin holder (the
    /// two-arg overloads collapse the parameters); after it the seven
    /// `_ADMIN` roles sit on the governance timelock while the Safe keeps
    /// its three direct action roles.
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
        grants = new RoleGrant[](15);

        // The admin holder holds every `_ADMIN`.
        grants[0] = RoleGrant(keccak256("DEPOSIT_ADMIN"), adminHolder);
        grants[1] = RoleGrant(keccak256("WITHDRAW_ADMIN"), adminHolder);
        grants[2] = RoleGrant(keccak256("CERTIFY_ADMIN"), adminHolder);
        grants[3] = RoleGrant(keccak256("CONFISCATE_SHARES_ADMIN"), adminHolder);
        grants[4] = RoleGrant(keccak256("CONFISCATE_RECEIPT_ADMIN"), adminHolder);

        // The two corporate-action admins the 0.1.1 impl adds.
        grants[5] = RoleGrant(keccak256("SCHEDULE_CORPORATE_ACTION_ADMIN"), adminHolder);
        grants[6] = RoleGrant(keccak256("CANCEL_CORPORATE_ACTION_ADMIN"), adminHolder);

        // The Safe holds the corresponding action roles for direct
        // operational use.
        grants[7] = RoleGrant(keccak256("DEPOSIT"), tokenOwnerSafe);
        grants[8] = RoleGrant(keccak256("WITHDRAW"), tokenOwnerSafe);
        grants[9] = RoleGrant(keccak256("CERTIFY"), tokenOwnerSafe);

        // Service signer. The retired `GRANTEE_SERVICE_1C66` has no rows;
        // its absence is asserted in `assertExpectedGrants`.
        grants[10] = RoleGrant(keccak256("DEPOSIT"), GRANTEE_SERVICE_3D0C);
        grants[11] = RoleGrant(keccak256("WITHDRAW"), GRANTEE_SERVICE_3D0C);
        grants[12] = RoleGrant(keccak256("CERTIFY"), GRANTEE_SERVICE_3D0C);

        // Orchestrator vault access.
        grants[13] = RoleGrant(keccak256("DEPOSIT"), GRANTEE_ORCHESTRATOR);
        grants[14] = RoleGrant(keccak256("WITHDRAW"), GRANTEE_ORCHESTRATOR);
    }

    /// @notice Assert every pinned `(role, grantee)` pair in
    /// `expectedGrants()` is held on the supplied authoriser, and that no
    /// pinned grantee holds `DEFAULT_ADMIN_ROLE`. Reverts with
    /// `UnexpectedDefaultAdmin` if a pinned grantee holds the root admin
    /// role, or `ExpectedGrantMissing` on the first missing pair.
    /// @dev The `DEFAULT_ADMIN_ROLE` check is a negative assertion over the
    /// pinned grantees, not an exhaustive scan (a plain `AccessControl`
    /// cannot enumerate members).
    /// @param authoriser The authoriser to validate.
    function assertExpectedGrants(address authoriser) internal view {
        assertExpectedGrants(authoriser, GRANTEE_TOKEN_OWNER_SAFE);
    }

    /// @notice Assert every `(role, grantee)` pair from
    /// `expectedGrants(tokenOwnerSafe)` is held on the supplied authoriser, and
    /// that neither the Safe nor the service signer holds `DEFAULT_ADMIN_ROLE`.
    /// @param authoriser The authoriser to validate.
    /// @param tokenOwnerSafe The chain's token-owner Safe filling the Safe
    /// grantee slots.
    function assertExpectedGrants(address authoriser, address tokenOwnerSafe) internal view {
        assertExpectedGrants(authoriser, tokenOwnerSafe, tokenOwnerSafe);
    }

    /// @notice Assert every `(role, grantee)` pair from
    /// `expectedGrants(tokenOwnerSafe, adminHolder)` is held on the supplied
    /// authoriser, that no named principal (the Safe, the admin holder, the
    /// service signer, the orchestrator) holds `DEFAULT_ADMIN_ROLE`, and
    /// that when the admin holder is distinct from the Safe, the Safe holds
    /// no `_ADMIN` entry.
    /// @param authoriser The authoriser to validate.
    /// @param tokenOwnerSafe The chain's token-owner Safe filling the
    /// operational Safe grantee slots.
    /// @param adminHolder The holder of the seven `_ADMIN` roles.
    function assertExpectedGrants(address authoriser, address tokenOwnerSafe, address adminHolder) internal view {
        IAccessControl acl = IAccessControl(authoriser);
        // No pinned grantee holds DEFAULT_ADMIN_ROLE: the hierarchy admins
        // each action role by its own `<ROLE>_ADMIN`.
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
        if (acl.hasRole(DEFAULT_ADMIN_ROLE, GRANTEE_ORCHESTRATOR)) {
            revert UnexpectedDefaultAdmin(authoriser, GRANTEE_ORCHESTRATOR);
        }
        assertRetiredSignerAbsent(acl, authoriser);
        RoleGrant[] memory grants = expectedGrants(tokenOwnerSafe, adminHolder);
        for (uint256 i = 0; i < grants.length; i++) {
            if (!acl.hasRole(grants[i].role, grants[i].grantee)) {
                revert ExpectedGrantMissing(authoriser, grants[i].role, grants[i].grantee);
            }
        }
        // Exclusive `_ADMIN` holding: with a distinct admin holder, a Safe
        // that retains any admin entry can grant or revoke action roles
        // directly, bypassing the admin holder's delay. The slice is
        // positional (the map's leading `ADMIN_ROLE_COUNT` entries) rather
        // than matched by grantee address, which would mis-slice if the
        // admin holder aliased another grantee.
        if (adminHolder != tokenOwnerSafe) {
            for (uint256 i = 0; i < ADMIN_ROLE_COUNT; i++) {
                if (acl.hasRole(grants[i].role, tokenOwnerSafe)) {
                    revert UnexpectedRetainedAdminGrant(authoriser, grants[i].role, tokenOwnerSafe);
                }
            }
        }
    }

    /// @notice Assert the retired signer holds none of the three action
    /// roles.
    /// @param acl The authoriser as an `IAccessControl`.
    /// @param authoriser The authoriser address, for the revert.
    function assertRetiredSignerAbsent(IAccessControl acl, address authoriser) internal view {
        bytes32[3] memory actionRoles = [keccak256("DEPOSIT"), keccak256("WITHDRAW"), keccak256("CERTIFY")];
        for (uint256 i = 0; i < actionRoles.length; i++) {
            if (acl.hasRole(actionRoles[i], GRANTEE_SERVICE_1C66)) {
                revert UnexpectedRetiredSignerGrant(authoriser, actionRoles[i]);
            }
        }
    }

    /// @notice Full authoriser-side invariant bundle against the Base
    /// production authoriser (`STOX_PROD_AUTHORISER`): its codehash equals
    /// the pinned EIP-1167 runtime embedding the 0.1.1 authoriser impl
    /// (proving which implementation the clone proxies), and the full
    /// `expectedGrants()` map holds.
    /// @dev No-arg; composed into `LibInvariants.assertAll`.
    function assertAll() internal view {
        bytes32 expected = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH;
        bytes32 actual = STOX_PROD_AUTHORISER.codehash;
        if (actual != expected) {
            revert AuthoriserImplCodehashMismatch(STOX_PROD_AUTHORISER, expected, actual);
        }
        assertExpectedGrants(STOX_PROD_AUTHORISER);
    }
}

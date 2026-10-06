// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibAuthoriserInvariants, RoleGrant} from "./LibAuthoriserInvariants.sol";
import {LibSafeInvariants} from "./LibSafeInvariants.sol";
import {LibTimelockInvariants} from "./LibTimelockInvariants.sol";
import {LibProdDeployV4} from "../generated/LibProdDeployV4.sol";

/// @notice An expected `(role, grantee)` pair is missing on the tMC
/// authoriser.
/// @param authoriser The authoriser inspected.
/// @param role The role that should be held.
/// @param grantee The grantee that should hold it.
error LvmhExpectedGrantMissing(address authoriser, bytes32 role, address grantee);

/// @notice A grantee holds a role the tMC map forbids it. This is the
/// exclusivity check: the shared service minter and the orchestrator must
/// not be able to mint or burn tMC, and only the admin holder may hold an
/// `_ADMIN` role.
/// @param authoriser The authoriser inspected.
/// @param role The forbidden role.
/// @param holder The grantee holding it.
error LvmhForbiddenGrant(address authoriser, bytes32 role, address holder);

/// @notice The active chain's tMC authoriser is not ready: unpinned, no
/// code, or not an EIP-1167 clone of the audited 0.1.1 authoriser.
/// @param authoriser The pinned address inspected.
error LvmhAuthoriserNotReady(address authoriser);

/// @notice The tMC authoriser pin was asked for on a chain without one.
/// @param chainId The chain id.
error UnsupportedChainForLvmhAuthoriser(uint256 chainId);

/// @title LibLvmhAuthoriserInvariants
/// @notice tMC is gated by its OWN authoriser on every chain rather than by
/// the chain's shared V4 authoriser, so that a different minter can mint it
/// and the shared service minter cannot. The authoriser is a clone of the
/// same audited 0.1.1 implementation the shared authoriser clones (same
/// EIP-1167 codehash, `LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH`),
/// deployed by `script/20261006-deploy-lvmh-authoriser.s.sol`.
///
/// Role map (per chain, `expectedGrants`):
/// - the seven `_ADMIN` roles: the chain's governance timelock, exclusively —
///   the same holder the shared authoriser has had since
///   `20260729-migrate-governance-to-timelock` executed;
/// - `DEPOSIT`, `WITHDRAW`, `CERTIFY`: the chain's token-owner Safe, mirroring
///   the shared authoriser;
/// - `DEPOSIT`, `WITHDRAW`: the dedicated tMC minter;
/// - `CERTIFY` only: the shared service signer `GRANTEE_SERVICE_3D0C`, so the
///   sft-certify flow keeps certifying tMC like every other token.
///
/// Forbidden (`assertExpectedGrants` reverts `LvmhForbiddenGrant`):
/// `DEPOSIT`/`WITHDRAW` on the service signer or the orchestrator, any action
/// role on the retired 1c66 signer, any `_ADMIN` on anyone named here other
/// than the admin holder, the minter's `CERTIFY`, and `DEFAULT_ADMIN_ROLE` on
/// every named principal.
library LibLvmhAuthoriserInvariants {
    /// @notice The `underlying` join key the token tables use for tMC.
    string internal constant LVMH_UNDERLYING = "MC";

    /// @notice The dedicated tMC minter. Holds `DEPOSIT` and `WITHDRAW` on
    /// the tMC authoriser only.
    address internal constant GRANTEE_LVMH_MINTER = 0x0958d9E94D9D4139280947ACd86D4a50F13bfA8C;

    // -------------------------------------------------------------------------
    // Authoriser pins. TODO: hydrate each from the
    // `20261006-deploy-lvmh-authoriser` broadcast on that chain. Zero means
    // "not deployed yet": the deploy script refuses to run once a pin is set,
    // and `20260807-deploy-missing-tokens` refuses to copy tMC while it is
    // unset.
    //
    // The clone address is CREATE(CloneFactory, factory nonce). At the
    // factory nonces read on 2026-10-06 (Base 6; Ethereum, HyperEVM,
    // Robinhood and BSC 2) the predicted addresses are:
    //   Base:                         0xCE9Efb002B5303FC1368Eed038a56a030b4C9E7f
    //   Ethereum/HyperEVM/RH/BSC:     0x260D3290AEbf7814EDd014869A0067AfF4334421
    // The factory is permissionless, so any clone someone else makes first
    // moves the address. Pin what the broadcast logs, not the prediction.
    // -------------------------------------------------------------------------

    /// @notice tMC authoriser on Base. TODO: pin after broadcast.
    address internal constant LVMH_AUTHORISER_BASE = address(0);
    /// @notice tMC authoriser on Ethereum. TODO: pin after broadcast.
    address internal constant LVMH_AUTHORISER_ETHEREUM = address(0);
    /// @notice tMC authoriser on HyperEVM. TODO: pin after broadcast.
    address internal constant LVMH_AUTHORISER_HYPEREVM = address(0);
    /// @notice tMC authoriser on Robinhood Chain. TODO: pin after broadcast.
    address internal constant LVMH_AUTHORISER_ROBINHOOD = address(0);
    /// @notice tMC authoriser on BNB Smart Chain. TODO: pin after broadcast.
    address internal constant LVMH_AUTHORISER_BSC = address(0);

    /// @notice Number of entries in `expectedGrants`.
    uint256 internal constant EXPECTED_GRANT_COUNT = 13;

    /// @notice Whether `underlying` is tMC's join key.
    /// @param underlying The ticker to test.
    /// @return True for "MC".
    function isLvmh(string memory underlying) internal pure returns (bool) {
        return keccak256(bytes(underlying)) == keccak256(bytes(LVMH_UNDERLYING));
    }

    /// @notice A chain's tMC authoriser pin, raw: zero until hydrated.
    /// Reverts for a chain without a slot rather than falling back to the
    /// shared authoriser.
    /// @param chainId The chain id.
    /// @return The pin, or zero.
    function lvmhAuthoriserForChainId(uint256 chainId) internal pure returns (address) {
        if (chainId == LibSafeInvariants.BASE_CHAIN_ID) return LVMH_AUTHORISER_BASE;
        if (chainId == LibSafeInvariants.ETHEREUM_CHAIN_ID) return LVMH_AUTHORISER_ETHEREUM;
        if (chainId == LibSafeInvariants.HYPEREVM_CHAIN_ID) return LVMH_AUTHORISER_HYPEREVM;
        if (chainId == LibSafeInvariants.ROBINHOOD_CHAIN_ID) return LVMH_AUTHORISER_ROBINHOOD;
        if (chainId == LibSafeInvariants.BSC_CHAIN_ID) return LVMH_AUTHORISER_BSC;
        revert UnsupportedChainForLvmhAuthoriser(chainId);
    }

    /// @notice The seven `_ADMIN` roles the 0.1.1 authoriser `initialize`
    /// grants to `initialAdmin`, in `_grantRole` order.
    /// @return roles The role hashes.
    function adminRoles() internal pure returns (bytes32[7] memory roles) {
        roles[0] = keccak256("CERTIFY_ADMIN");
        roles[1] = keccak256("CONFISCATE_RECEIPT_ADMIN");
        roles[2] = keccak256("CONFISCATE_SHARES_ADMIN");
        roles[3] = keccak256("DEPOSIT_ADMIN");
        roles[4] = keccak256("WITHDRAW_ADMIN");
        roles[5] = keccak256("SCHEDULE_CORPORATE_ACTION_ADMIN");
        roles[6] = keccak256("CANCEL_CORPORATE_ACTION_ADMIN");
    }

    /// @notice The action roles the 0.1.1 authoriser gates mint, burn and
    /// certify on.
    /// @return roles `DEPOSIT`, `WITHDRAW`, `CERTIFY`.
    function actionRoles() internal pure returns (bytes32[3] memory roles) {
        roles[0] = keccak256("DEPOSIT");
        roles[1] = keccak256("WITHDRAW");
        roles[2] = keccak256("CERTIFY");
    }

    /// @notice The tMC authoriser's `(role, grantee)` map. The leading
    /// seven entries are the `_ADMIN` slice; the rest are action grants and
    /// are what the deploy script grants before handing the admins over.
    /// @param tokenOwnerSafe The chain's token-owner Safe.
    /// @param adminHolder The holder of the seven `_ADMIN` roles (the chain's
    /// governance timelock).
    /// @return grants The pinned pairs.
    function expectedGrants(address tokenOwnerSafe, address adminHolder)
        internal
        pure
        returns (RoleGrant[] memory grants)
    {
        grants = new RoleGrant[](EXPECTED_GRANT_COUNT);
        bytes32[7] memory admins = adminRoles();
        for (uint256 i = 0; i < admins.length; i++) {
            grants[i] = RoleGrant(admins[i], adminHolder);
        }
        grants[7] = RoleGrant(keccak256("DEPOSIT"), tokenOwnerSafe);
        grants[8] = RoleGrant(keccak256("WITHDRAW"), tokenOwnerSafe);
        grants[9] = RoleGrant(keccak256("CERTIFY"), tokenOwnerSafe);
        grants[10] = RoleGrant(keccak256("DEPOSIT"), GRANTEE_LVMH_MINTER);
        grants[11] = RoleGrant(keccak256("WITHDRAW"), GRANTEE_LVMH_MINTER);
        grants[12] = RoleGrant(keccak256("CERTIFY"), LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C);
    }

    /// @notice The map for the chain with id `chainId`: its Safe and its
    /// governance timelock.
    /// @param chainId The chain id.
    /// @return grants The pinned pairs for that chain.
    function expectedGrantsForChainId(uint256 chainId) internal pure returns (RoleGrant[] memory grants) {
        grants = expectedGrants(
            LibSafeInvariants.safeForChainId(chainId), LibTimelockInvariants.timelockForChainId(chainId)
        );
    }

    /// @notice Assert the full tMC role map on `authoriser`: every expected
    /// pair holds, and every forbidden pair does not.
    /// @param authoriser The tMC authoriser.
    /// @param tokenOwnerSafe The chain's token-owner Safe.
    /// @param adminHolder The chain's `_ADMIN` holder.
    function assertExpectedGrants(address authoriser, address tokenOwnerSafe, address adminHolder) internal view {
        IAccessControl acl = IAccessControl(authoriser);

        RoleGrant[] memory grants = expectedGrants(tokenOwnerSafe, adminHolder);
        for (uint256 i = 0; i < grants.length; i++) {
            if (!acl.hasRole(grants[i].role, grants[i].grantee)) {
                revert LvmhExpectedGrantMissing(authoriser, grants[i].role, grants[i].grantee);
            }
        }

        address service = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;
        address orchestrator = LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR;
        address retired = LibAuthoriserInvariants.GRANTEE_SERVICE_1C66;

        // The point of the dedicated authoriser: neither the shared service
        // minter nor the orchestrator can mint or burn tMC.
        _forbid(acl, authoriser, keccak256("DEPOSIT"), service);
        _forbid(acl, authoriser, keccak256("WITHDRAW"), service);
        _forbid(acl, authoriser, keccak256("DEPOSIT"), orchestrator);
        _forbid(acl, authoriser, keccak256("WITHDRAW"), orchestrator);
        _forbid(acl, authoriser, keccak256("CERTIFY"), orchestrator);
        // The minter mints and burns; it does not certify.
        _forbid(acl, authoriser, keccak256("CERTIFY"), GRANTEE_LVMH_MINTER);
        // The retired signer holds nothing here either.
        bytes32[3] memory actions = actionRoles();
        for (uint256 i = 0; i < actions.length; i++) {
            _forbid(acl, authoriser, actions[i], retired);
        }

        // `_ADMIN` roles sit on the admin holder exclusively.
        address[5] memory nonAdmins = [tokenOwnerSafe, GRANTEE_LVMH_MINTER, service, orchestrator, retired];
        bytes32[7] memory admins = adminRoles();
        for (uint256 i = 0; i < admins.length; i++) {
            for (uint256 j = 0; j < nonAdmins.length; j++) {
                if (nonAdmins[j] != adminHolder) {
                    _forbid(acl, authoriser, admins[i], nonAdmins[j]);
                }
            }
        }

        // Nobody named holds the root admin role.
        address[6] memory everyone = [adminHolder, tokenOwnerSafe, GRANTEE_LVMH_MINTER, service, orchestrator, retired];
        for (uint256 i = 0; i < everyone.length; i++) {
            _forbid(acl, authoriser, LibAuthoriserInvariants.DEFAULT_ADMIN_ROLE, everyone[i]);
        }
    }

    /// @notice Assert `authoriser` is an EIP-1167 clone of the audited 0.1.1
    /// authoriser — the same codehash the shared authoriser carries.
    /// @param authoriser The address to check.
    function assertIsAuditedClone(address authoriser) internal view {
        if (
            authoriser == address(0) || authoriser.code.length == 0
                || authoriser.codehash != LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH
        ) {
            revert LvmhAuthoriserNotReady(authoriser);
        }
    }

    /// @notice The active chain's tMC authoriser, asserted hydrated, an
    /// audited clone, and carrying exactly the tMC role map with this
    /// chain's Safe and governance timelock.
    /// @return authoriser The validated authoriser.
    function activeChainLvmhAuthoriser() internal view returns (address authoriser) {
        authoriser = lvmhAuthoriserForChainId(block.chainid);
        assertIsAuditedClone(authoriser);
        assertExpectedGrants(
            authoriser,
            LibSafeInvariants.safeForChainId(block.chainid),
            LibTimelockInvariants.timelockForChainId(block.chainid)
        );
    }

    /// @notice Revert `LvmhForbiddenGrant` if `holder` holds `role`.
    /// @param acl The authoriser as `IAccessControl`.
    /// @param authoriser The authoriser address, for the revert.
    /// @param role The forbidden role.
    /// @param holder The grantee that must not hold it.
    function _forbid(IAccessControl acl, address authoriser, bytes32 role, address holder) private view {
        if (acl.hasRole(role, holder)) {
            revert LvmhForbiddenGrant(authoriser, role, holder);
        }
    }
}

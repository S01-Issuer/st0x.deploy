// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibAuthoriserInvariants, RoleGrant} from "./LibAuthoriserInvariants.sol";
import {LibSafeInvariants} from "./LibSafeInvariants.sol";
import {LibTimelockInvariants} from "./LibTimelockInvariants.sol";
import {LibProdDeployV4} from "../generated/LibProdDeployV4.sol";

/// @notice An expected `(role, grantee)` pair is missing.
error EuExpectedGrantMissing(address authoriser, bytes32 role, address grantee);

/// @notice A grantee holds a role the EU assets map forbids.
error EuForbiddenGrant(address authoriser, bytes32 role, address holder);

/// @notice The authoriser is unpinned, has no code, or is not a clone of the
/// audited 0.1.1 authoriser.
error EuAuthoriserNotReady(address authoriser);

/// @notice The chain has no EU assets authoriser slot.
error UnsupportedChainForEuAuthoriser(uint256 chainId);

/// @title LibEuAuthoriserInvariants
/// @notice The EU assets authoriser: a per-chain clone of the audited 0.1.1
/// authoriser that only the EU minter and the Safe can mint through.
library LibEuAuthoriserInvariants {
    address internal constant GRANTEE_EU_MINTER = 0x0958d9E94D9D4139280947ACd86D4a50F13bfA8C;

    // Set once the Safe's handover bundle has executed on that chain.
    address internal constant EU_AUTHORISER_BASE = address(0);
    address internal constant EU_AUTHORISER_ETHEREUM = address(0);
    address internal constant EU_AUTHORISER_HYPEREVM = address(0);
    address internal constant EU_AUTHORISER_ROBINHOOD = address(0);
    address internal constant EU_AUTHORISER_BSC = address(0);

    uint256 internal constant EXPECTED_GRANT_COUNT = 13;

    /// @notice Zero until the chain is pinned.
    function euAuthoriserForChainId(uint256 chainId) internal pure returns (address) {
        if (chainId == LibSafeInvariants.BASE_CHAIN_ID) return EU_AUTHORISER_BASE;
        if (chainId == LibSafeInvariants.ETHEREUM_CHAIN_ID) return EU_AUTHORISER_ETHEREUM;
        if (chainId == LibSafeInvariants.HYPEREVM_CHAIN_ID) return EU_AUTHORISER_HYPEREVM;
        if (chainId == LibSafeInvariants.ROBINHOOD_CHAIN_ID) return EU_AUTHORISER_ROBINHOOD;
        if (chainId == LibSafeInvariants.BSC_CHAIN_ID) return EU_AUTHORISER_BSC;
        revert UnsupportedChainForEuAuthoriser(chainId);
    }

    function adminRoles() internal pure returns (bytes32[7] memory roles) {
        roles[0] = keccak256("CERTIFY_ADMIN");
        roles[1] = keccak256("CONFISCATE_RECEIPT_ADMIN");
        roles[2] = keccak256("CONFISCATE_SHARES_ADMIN");
        roles[3] = keccak256("DEPOSIT_ADMIN");
        roles[4] = keccak256("WITHDRAW_ADMIN");
        roles[5] = keccak256("SCHEDULE_CORPORATE_ACTION_ADMIN");
        roles[6] = keccak256("CANCEL_CORPORATE_ACTION_ADMIN");
    }

    function actionRoles() internal pure returns (bytes32[3] memory roles) {
        roles[0] = keccak256("DEPOSIT");
        roles[1] = keccak256("WITHDRAW");
        roles[2] = keccak256("CERTIFY");
    }

    /// @notice The first seven entries are the `_ADMIN` roles.
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
        grants[10] = RoleGrant(keccak256("DEPOSIT"), GRANTEE_EU_MINTER);
        grants[11] = RoleGrant(keccak256("WITHDRAW"), GRANTEE_EU_MINTER);
        grants[12] = RoleGrant(keccak256("CERTIFY"), LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C);
    }

    /// @notice Every expected grant holds and no named principal holds a
    /// forbidden one.
    function assertExpectedGrants(address authoriser, address tokenOwnerSafe, address adminHolder) internal view {
        IAccessControl acl = IAccessControl(authoriser);

        RoleGrant[] memory grants = expectedGrants(tokenOwnerSafe, adminHolder);
        for (uint256 i = 0; i < grants.length; i++) {
            if (!acl.hasRole(grants[i].role, grants[i].grantee)) {
                revert EuExpectedGrantMissing(authoriser, grants[i].role, grants[i].grantee);
            }
        }

        address service = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;
        address orchestrator = LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR;
        address retired = LibAuthoriserInvariants.GRANTEE_SERVICE_1C66;

        _forbid(acl, authoriser, keccak256("DEPOSIT"), service);
        _forbid(acl, authoriser, keccak256("WITHDRAW"), service);
        _forbid(acl, authoriser, keccak256("DEPOSIT"), orchestrator);
        _forbid(acl, authoriser, keccak256("WITHDRAW"), orchestrator);
        _forbid(acl, authoriser, keccak256("CERTIFY"), orchestrator);
        _forbid(acl, authoriser, keccak256("CERTIFY"), GRANTEE_EU_MINTER);
        bytes32[3] memory actions = actionRoles();
        for (uint256 i = 0; i < actions.length; i++) {
            _forbid(acl, authoriser, actions[i], retired);
        }

        address[5] memory nonAdmins = [tokenOwnerSafe, GRANTEE_EU_MINTER, service, orchestrator, retired];
        bytes32[7] memory admins = adminRoles();
        for (uint256 i = 0; i < admins.length; i++) {
            for (uint256 j = 0; j < nonAdmins.length; j++) {
                if (nonAdmins[j] != adminHolder) {
                    _forbid(acl, authoriser, admins[i], nonAdmins[j]);
                }
            }
        }

        address[6] memory everyone = [adminHolder, tokenOwnerSafe, GRANTEE_EU_MINTER, service, orchestrator, retired];
        for (uint256 i = 0; i < everyone.length; i++) {
            _forbid(acl, authoriser, LibAuthoriserInvariants.DEFAULT_ADMIN_ROLE, everyone[i]);
        }
    }

    function assertIsAuditedClone(address authoriser) internal view {
        if (
            authoriser == address(0) || authoriser.code.length == 0
                || authoriser.codehash != LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH
        ) {
            revert EuAuthoriserNotReady(authoriser);
        }
    }

    function activeChainEuAuthoriser() internal view returns (address authoriser) {
        authoriser = euAuthoriserForChainId(block.chainid);
        assertIsAuditedClone(authoriser);
        assertExpectedGrants(
            authoriser,
            LibSafeInvariants.safeForChainId(block.chainid),
            LibTimelockInvariants.timelockForChainId(block.chainid)
        );
    }

    /// @notice Passes while the chain is unpinned.
    function assertPinnedAuthoriser(uint256 chainId, address tokenOwnerSafe, address adminHolder) internal view {
        address authoriser = euAuthoriserForChainId(chainId);
        if (authoriser == address(0)) return;
        assertIsAuditedClone(authoriser);
        assertExpectedGrants(authoriser, tokenOwnerSafe, adminHolder);
    }

    function _forbid(IAccessControl acl, address authoriser, bytes32 role, address holder) private view {
        if (acl.hasRole(role, holder)) {
            revert EuForbiddenGrant(authoriser, role, holder);
        }
    }
}

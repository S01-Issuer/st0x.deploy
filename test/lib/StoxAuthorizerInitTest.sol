// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Clones} from "@openzeppelin-contracts-5.7.0/proxy/Clones.sol";
import {
    CERTIFY,
    CONFISCATE_RECEIPT,
    CONFISCATE_SHARES,
    DEPOSIT,
    WITHDRAW
} from "rain-vats-0.2.20/src/abstract/OffchainAssetReceiptVault.sol";
import {
    CERTIFY_ADMIN,
    CONFISCATE_RECEIPT_ADMIN,
    CONFISCATE_SHARES_ADMIN,
    DEPOSIT_ADMIN,
    WITHDRAW_ADMIN
} from "rain-vats-0.2.20/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {SCHEDULE_CORPORATE_ACTION, CANCEL_CORPORATE_ACTION} from "../../src/lib/LibCorporateAction.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1,
    SCHEDULE_CORPORATE_ACTION_ADMIN,
    CANCEL_CORPORATE_ACTION_ADMIN
} from "../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";

/// @title StoxAuthorizerInitTest
/// @notice A fresh, uninitialized Stox authorizer clone, and the roles its
/// `initialize` grants: each admin role administers itself and the role at the
/// same index of `governedRoles`.
abstract contract StoxAuthorizerInitTest is Test {
    function newAuthorizer() internal returns (StoxOffchainAssetReceiptVaultAuthorizerV1) {
        return StoxOffchainAssetReceiptVaultAuthorizerV1(
            Clones.clone(address(new StoxOffchainAssetReceiptVaultAuthorizerV1()))
        );
    }

    function adminRoles() internal pure returns (bytes32[7] memory) {
        return [
            CERTIFY_ADMIN,
            CONFISCATE_RECEIPT_ADMIN,
            CONFISCATE_SHARES_ADMIN,
            DEPOSIT_ADMIN,
            WITHDRAW_ADMIN,
            SCHEDULE_CORPORATE_ACTION_ADMIN,
            CANCEL_CORPORATE_ACTION_ADMIN
        ];
    }

    function governedRoles() internal pure returns (bytes32[7] memory) {
        return [
            CERTIFY,
            CONFISCATE_RECEIPT,
            CONFISCATE_SHARES,
            DEPOSIT,
            WITHDRAW,
            SCHEDULE_CORPORATE_ACTION,
            CANCEL_CORPORATE_ACTION
        ];
    }

    function assertHoldsEveryAdminRoleOnly(StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer, address account)
        internal
        view
    {
        bytes32[7] memory admins = adminRoles();
        bytes32[7] memory governed = governedRoles();
        for (uint256 i = 0; i < admins.length; i++) {
            assertTrue(authorizer.hasRole(admins[i], account), "admin role");
            assertFalse(authorizer.hasRole(governed[i], account), "governed role");
        }
        assertFalse(authorizer.hasRole(authorizer.DEFAULT_ADMIN_ROLE(), account), "default admin");
    }

    function assertHoldsNoRole(StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer, address account) internal view {
        bytes32[7] memory admins = adminRoles();
        bytes32[7] memory governed = governedRoles();
        for (uint256 i = 0; i < admins.length; i++) {
            assertFalse(authorizer.hasRole(admins[i], account), "admin role");
            assertFalse(authorizer.hasRole(governed[i], account), "governed role");
        }
        assertFalse(authorizer.hasRole(authorizer.DEFAULT_ADMIN_ROLE(), account), "default admin");
    }

    /// `data`'s first `length` bytes.
    function prefix(bytes memory data, uint256 length) internal pure returns (bytes memory) {
        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = data[i];
        }
        return result;
    }
}

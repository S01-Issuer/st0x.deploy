// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {
    StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1
} from "../../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol";
import {
    OffchainAssetReceiptVaultPaymentMintAuthorizerV1Config
} from "rain-vats-0.2.1/src/concrete/authorize/OffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol";
import {CloneFactory} from "rain-factory-0.1.5/src/concrete/CloneFactory.sol";
import {VerifyAlwaysApproved} from "rain-verify-interface-0.1.0/src/concrete/VerifyAlwaysApproved.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {SCHEDULE_CORPORATE_ACTION, CANCEL_CORPORATE_ACTION} from "../../../../src/lib/LibCorporateAction.sol";
import {MockERC20} from "../../../concrete/MockERC20.sol";

/// @title PaymentMint authorizer corporate-action pairing gap
/// @notice `StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1` does not
/// initialise the corporate-action role admin hierarchy, so
/// `SCHEDULE_CORPORATE_ACTION` and `CANCEL_CORPORATE_ACTION` are administered
/// by the unassigned `DEFAULT_ADMIN_ROLE` and cannot be granted by anyone.
contract StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1CorporateActionPairingGapTest is Test {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    address constant OWNER = address(uint160(uint256(keccak256("OWNER"))));
    address constant SCHEDULER = address(uint160(uint256(keccak256("SCHEDULER"))));

    function newAuthorizer() internal returns (StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1) {
        StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 impl =
            new StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1();
        CloneFactory factory = new CloneFactory();
        bytes memory initData = abi.encode(
            OffchainAssetReceiptVaultPaymentMintAuthorizerV1Config({
                receiptVault: address(this),
                verify: address(new VerifyAlwaysApproved()),
                owner: OWNER,
                paymentToken: address(new MockERC20()),
                maxSharesSupply: 1e27
            })
        );
        return StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1(
            factory.cloneDeterministic(address(impl), initData, bytes32(0))
        );
    }

    /// SCHEDULE_CORPORATE_ACTION's role admin falls back to
    /// DEFAULT_ADMIN_ROLE because the PaymentMint authorizer's initializer
    /// never calls `_setRoleAdmin(SCHEDULE_CORPORATE_ACTION, ...)`.
    function testScheduleCorporateActionRoleAdminFallsBackToDefaultAdmin() external {
        StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 authorizer = newAuthorizer();
        assertEq(IAccessControl(address(authorizer)).getRoleAdmin(SCHEDULE_CORPORATE_ACTION), DEFAULT_ADMIN_ROLE);
    }

    /// Same for CANCEL_CORPORATE_ACTION.
    function testCancelCorporateActionRoleAdminFallsBackToDefaultAdmin() external {
        StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 authorizer = newAuthorizer();
        assertEq(IAccessControl(address(authorizer)).getRoleAdmin(CANCEL_CORPORATE_ACTION), DEFAULT_ADMIN_ROLE);
    }

    /// DEFAULT_ADMIN_ROLE is itself unassigned: the PaymentMint authorizer
    /// doesn't grant it to anyone during init, so nobody can grant
    /// SCHEDULE_CORPORATE_ACTION or CANCEL_CORPORATE_ACTION.
    function testDefaultAdminRoleIsUnassigned() external {
        StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 authorizer = newAuthorizer();
        assertFalse(IAccessControl(address(authorizer)).hasRole(DEFAULT_ADMIN_ROLE, OWNER));
        // The deployer doesn't hold it either.
        assertFalse(IAccessControl(address(authorizer)).hasRole(DEFAULT_ADMIN_ROLE, address(this)));
    }

    /// The owner — who CAN grant other roles configured by the base
    /// authorizer — cannot grant SCHEDULE_CORPORATE_ACTION. AccessControl
    /// reverts because the caller (OWNER) doesn't hold the fallback admin
    /// role (DEFAULT_ADMIN_ROLE).
    function testOwnerCannotGrantScheduleCorporateAction() external {
        StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 authorizer = newAuthorizer();
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, OWNER, DEFAULT_ADMIN_ROLE)
        );
        IAccessControl(address(authorizer)).grantRole(SCHEDULE_CORPORATE_ACTION, SCHEDULER);
    }

    /// Same for cancel.
    function testOwnerCannotGrantCancelCorporateAction() external {
        StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 authorizer = newAuthorizer();
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, OWNER, DEFAULT_ADMIN_ROLE)
        );
        IAccessControl(address(authorizer)).grantRole(CANCEL_CORPORATE_ACTION, SCHEDULER);
    }
}

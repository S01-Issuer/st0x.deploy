// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {SCHEDULE_CORPORATE_ACTION, CANCEL_CORPORATE_ACTION} from "../../../src/lib/LibCorporateAction.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain.vats/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {Unauthorized} from "rain.vats/interface/IAuthorizeV1.sol";
import {CloneFactory} from "rain.factory/concrete/CloneFactory.sol";

/// @title StoxCorporateActionsFacetAuthorizerIntegrationTest
/// @notice Tests that the real OffchainAssetReceiptVaultAuthorizerV1 handles
/// corporate action permissions via its generic RBAC path.
contract StoxCorporateActionsFacetAuthorizerIntegrationTest is Test {
    address constant ADMIN = address(uint160(uint256(keccak256("ADMIN"))));
    address constant SCHEDULER = address(uint160(uint256(keccak256("SCHEDULER"))));
    address constant CANCELLER = address(uint160(uint256(keccak256("CANCELLER"))));
    address constant NOBODY = address(uint160(uint256(keccak256("NOBODY"))));

    function newAuthorizer() internal returns (StoxOffchainAssetReceiptVaultAuthorizerV1) {
        StoxOffchainAssetReceiptVaultAuthorizerV1 impl = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        CloneFactory factory = new CloneFactory();
        return StoxOffchainAssetReceiptVaultAuthorizerV1(
            factory.clone(address(impl), abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: ADMIN})))
        );
    }

    /// User with SCHEDULE_CORPORATE_ACTION role is authorized.
    function testScheduleRoleAuthorized() external {
        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer = newAuthorizer();

        vm.prank(ADMIN);
        authorizer.grantRole(SCHEDULE_CORPORATE_ACTION, SCHEDULER);

        authorizer.authorize(SCHEDULER, SCHEDULE_CORPORATE_ACTION, "");
    }

    /// User without SCHEDULE_CORPORATE_ACTION role is unauthorized.
    function testScheduleRoleUnauthorized() external {
        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer = newAuthorizer();

        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, NOBODY, SCHEDULE_CORPORATE_ACTION, ""));
        authorizer.authorize(NOBODY, SCHEDULE_CORPORATE_ACTION, "");
    }

    /// User with CANCEL_CORPORATE_ACTION role is authorized.
    function testCancelRoleAuthorized() external {
        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer = newAuthorizer();

        vm.prank(ADMIN);
        authorizer.grantRole(CANCEL_CORPORATE_ACTION, CANCELLER);

        authorizer.authorize(CANCELLER, CANCEL_CORPORATE_ACTION, "");
    }

    /// User without CANCEL_CORPORATE_ACTION role is unauthorized.
    function testCancelRoleUnauthorized() external {
        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer = newAuthorizer();

        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, NOBODY, CANCEL_CORPORATE_ACTION, ""));
        authorizer.authorize(NOBODY, CANCEL_CORPORATE_ACTION, "");
    }

    /// Revoking a corporate action role removes authorization.
    function testRevokeScheduleRole() external {
        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer = newAuthorizer();

        vm.startPrank(ADMIN);
        authorizer.grantRole(SCHEDULE_CORPORATE_ACTION, SCHEDULER);
        authorizer.revokeRole(SCHEDULE_CORPORATE_ACTION, SCHEDULER);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, SCHEDULER, SCHEDULE_CORPORATE_ACTION, ""));
        authorizer.authorize(SCHEDULER, SCHEDULE_CORPORATE_ACTION, "");
    }
}

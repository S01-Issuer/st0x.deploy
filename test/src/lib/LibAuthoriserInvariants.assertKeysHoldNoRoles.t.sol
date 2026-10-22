// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Clones} from "@openzeppelin-contracts-5.7.0/proxy/Clones.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibAuthoriserClone} from "../../../src/lib/LibAuthoriserClone.sol";
import {DeployKeyHoldsRole, LibAuthoriserInvariants} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibStoxConfigFork} from "../../../src/lib/LibStoxConfigFork.sol";
import {RoleGrant} from "../../../src/lib/RoleGrant.sol";
import {LibAuthoriserInvariantsHarness} from "./LibAuthoriserInvariantsHarness.sol";

contract LibAuthoriserInvariantsAssertKeysHoldNoRolesTest is Test {
    LibAuthoriserInvariantsHarness internal harness;

    function setUp() external {
        harness = new LibAuthoriserInvariantsHarness();
    }

    function newAuthoriser(address admin) internal returns (StoxOffchainAssetReceiptVaultAuthorizerV1) {
        LibStoxConfigFork.bindAuthoriserAdmin(vm, admin);
        StoxOffchainAssetReceiptVaultAuthorizerV1 authoriser = StoxOffchainAssetReceiptVaultAuthorizerV1(
            Clones.clone(address(new StoxOffchainAssetReceiptVaultAuthorizerV1()))
        );
        authoriser.initialize(LibAuthoriserClone.cloneData());
        return authoriser;
    }

    function keys() internal pure returns (address[2] memory) {
        return [LibAuthoriserInvariants.DEPLOY_HOT_KEY, LibProdDeployV4.BEACON_INITIAL_OWNER];
    }

    function testHotKeyIsNotTheRetiredKey() external pure {
        assertNotEq(LibAuthoriserInvariants.DEPLOY_HOT_KEY, LibProdDeployV4.BEACON_INITIAL_OWNER);
    }

    function testFuzzPassesWhenNeitherKeyHoldsARole(address admin) external {
        vm.assume(admin != address(0) && admin != keys()[0] && admin != keys()[1]);
        harness.callAssertKeysHoldNoRoles(address(newAuthoriser(admin)));
    }

    /// Every role of the fourteen, on either key, is refused by name.
    function testFuzzRefusesAnyRoleOnEitherKey(uint256 roleIndex, bool retired) external {
        address admin = address(0xAD);
        StoxOffchainAssetReceiptVaultAuthorizerV1 authoriser = newAuthoriser(admin);
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedEuGrants(admin, admin, admin);
        bytes32 role = grants[bound(roleIndex, 0, 13)].role;
        address key = keys()[retired ? 1 : 0];
        vm.prank(admin);
        authoriser.grantRole(role, key);
        vm.expectRevert(abi.encodeWithSelector(DeployKeyHoldsRole.selector, address(authoriser), role, key));
        harness.callAssertKeysHoldNoRoles(address(authoriser));
    }

    function testFuzzRefusesDefaultAdminOnEitherKey(bool retired) external {
        StoxOffchainAssetReceiptVaultAuthorizerV1 authoriser = newAuthoriser(address(0xAD));
        address key = keys()[retired ? 1 : 0];
        vm.mockCall(address(authoriser), abi.encodeCall(IAccessControl.hasRole, (bytes32(0), key)), abi.encode(true));
        vm.expectRevert(abi.encodeWithSelector(DeployKeyHoldsRole.selector, address(authoriser), bytes32(0), key));
        harness.callAssertKeysHoldNoRoles(address(authoriser));
    }

    /// A key bound as the admin holds the first `_ADMIN` checked.
    function testRefusesTheHotKeyBoundAsAdmin() external {
        StoxOffchainAssetReceiptVaultAuthorizerV1 authoriser = newAuthoriser(LibAuthoriserInvariants.DEPLOY_HOT_KEY);
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployKeyHoldsRole.selector,
                address(authoriser),
                keccak256("DEPOSIT_ADMIN"),
                LibAuthoriserInvariants.DEPLOY_HOT_KEY
            )
        );
        harness.callAssertKeysHoldNoRoles(address(authoriser));
    }

    function testPassesOnTheLiveBaseAuthoriser() external {
        vm.createSelectFork("base");
        harness = new LibAuthoriserInvariantsHarness();
        harness.callAssertKeysHoldNoRoles(LibAuthoriserInvariants.STOX_PROD_AUTHORISER);
    }
}

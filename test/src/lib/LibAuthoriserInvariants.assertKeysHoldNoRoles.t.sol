// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {DeployKeyHoldsRole, LibAuthoriserInvariants} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {RoleGrant} from "../../../src/lib/RoleGrant.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {StoxAuthorizerInitTest} from "../../lib/StoxAuthorizerInitTest.sol";
import {LibAuthoriserInvariantsHarness} from "./LibAuthoriserInvariantsHarness.sol";

contract LibAuthoriserInvariantsAssertKeysHoldNoRolesTest is StoxAuthorizerInitTest {
    address internal constant ADMIN = address(0xAD);

    LibAuthoriserInvariantsHarness internal harness;

    function setUp() external {
        harness = new LibAuthoriserInvariantsHarness();
    }

    function initialized(address admin) internal returns (StoxOffchainAssetReceiptVaultAuthorizerV1) {
        StoxOffchainAssetReceiptVaultAuthorizerV1 authoriser = newAuthorizer();
        authoriser.initialize(LibTestDeploy.authorizerData(vm, admin));
        return authoriser;
    }

    function refusesEachEuRole(address key) internal {
        StoxOffchainAssetReceiptVaultAuthorizerV1 authoriser = initialized(ADMIN);
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedEuGrants(ADMIN, ADMIN, ADMIN);
        for (uint256 i = 0; i < grants.length; i++) {
            uint256 snapshot = vm.snapshotState();
            vm.prank(ADMIN);
            authoriser.grantRole(grants[i].role, key);
            vm.expectRevert(
                abi.encodeWithSelector(DeployKeyHoldsRole.selector, address(authoriser), grants[i].role, key)
            );
            harness.callAssertKeysHoldNoRoles(address(authoriser));
            vm.revertToState(snapshot);
        }
    }

    function refusesDefaultAdmin(address key) internal {
        StoxOffchainAssetReceiptVaultAuthorizerV1 authoriser = initialized(ADMIN);
        vm.mockCall(address(authoriser), abi.encodeCall(IAccessControl.hasRole, (bytes32(0), key)), abi.encode(true));
        vm.expectRevert(abi.encodeWithSelector(DeployKeyHoldsRole.selector, address(authoriser), bytes32(0), key));
        harness.callAssertKeysHoldNoRoles(address(authoriser));
    }

    function refusesKeyBoundAsAdmin(address key) internal {
        StoxOffchainAssetReceiptVaultAuthorizerV1 authoriser = initialized(key);
        vm.expectRevert(
            abi.encodeWithSelector(DeployKeyHoldsRole.selector, address(authoriser), keccak256("DEPOSIT_ADMIN"), key)
        );
        harness.callAssertKeysHoldNoRoles(address(authoriser));
    }

    /// @notice The hot key and the retired key are distinct addresses.
    function testHotKeyIsNotTheRetiredKey() external pure {
        assertNotEq(LibAuthoriserInvariants.DEPLOY_HOT_KEY, LibProdDeployV4.BEACON_INITIAL_OWNER);
    }

    /// @notice An authoriser whose admin is neither key passes.
    function testFuzzPassesWhenNeitherKeyHoldsARole(address admin) external {
        vm.assume(
            admin != address(0) && admin != LibAuthoriserInvariants.DEPLOY_HOT_KEY
                && admin != LibProdDeployV4.BEACON_INITIAL_OWNER
        );
        harness.callAssertKeysHoldNoRoles(address(initialized(admin)));
    }

    /// @notice Every `expectedEuGrants` role on the hot key is refused by name.
    function testRefusesEachEuRoleOnTheHotKey() external {
        refusesEachEuRole(LibAuthoriserInvariants.DEPLOY_HOT_KEY);
    }

    /// @notice Every `expectedEuGrants` role on the retired key is refused by name.
    function testRefusesEachEuRoleOnTheRetiredKey() external {
        refusesEachEuRole(LibProdDeployV4.BEACON_INITIAL_OWNER);
    }

    /// @notice `DEFAULT_ADMIN_ROLE` on the hot key is refused.
    function testRefusesDefaultAdminOnTheHotKey() external {
        refusesDefaultAdmin(LibAuthoriserInvariants.DEPLOY_HOT_KEY);
    }

    /// @notice `DEFAULT_ADMIN_ROLE` on the retired key is refused.
    function testRefusesDefaultAdminOnTheRetiredKey() external {
        refusesDefaultAdmin(LibProdDeployV4.BEACON_INITIAL_OWNER);
    }

    /// @notice The hot key bound as initial admin is refused on the first `_ADMIN` checked.
    function testRefusesTheHotKeyBoundAsAdmin() external {
        refusesKeyBoundAsAdmin(LibAuthoriserInvariants.DEPLOY_HOT_KEY);
    }

    /// @notice The retired key bound as initial admin is refused on the first `_ADMIN` checked.
    function testRefusesTheRetiredKeyBoundAsAdmin() external {
        refusesKeyBoundAsAdmin(LibProdDeployV4.BEACON_INITIAL_OWNER);
    }
}

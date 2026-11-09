// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {ICLONEABLE_V2_SUCCESS} from "rain-factory-0.2.11/src/interface/ICloneableV2.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibTestDeploy} from "../../../lib/LibTestDeploy.sol";
import {StoxAuthorizerInitTest} from "../../../lib/StoxAuthorizerInitTest.sol";

contract StoxOffchainAssetReceiptVaultAuthorizerV1InitialRolesTest is StoxAuthorizerInitTest {
    function initialized(address admin) internal returns (StoxOffchainAssetReceiptVaultAuthorizerV1, Vm.Log[] memory) {
        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer = newAuthorizer();
        bytes memory data = LibTestDeploy.authorizerData(vm, admin);
        vm.recordLogs();
        assertEq(authorizer.initialize(data), ICLONEABLE_V2_SUCCESS, "result");
        return (authorizer, vm.getRecordedLogs());
    }

    function testBoundAdminHoldsEveryAdminRoleOnly(address admin) external {
        vm.assume(admin != address(0) && admin != address(this) && admin != LibRegistryAuthority.ROOT_AUTHORITY);
        (StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer,) = initialized(admin);
        assertHoldsEveryAdminRoleOnly(authorizer, admin);
        assertHoldsNoRole(authorizer, address(this));
        assertHoldsNoRole(authorizer, LibRegistryAuthority.ROOT_AUTHORITY);
    }

    function testInitializeGrantsNothingButTheAdminRolesToTheBoundAdmin(address admin) external {
        vm.assume(admin != address(0));
        (StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer, Vm.Log[] memory logs) = initialized(admin);
        bytes32[7] memory admins = adminRoles();
        bool[7] memory granted;
        uint256 grants = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(authorizer) || logs[i].topics[0] != IAccessControl.RoleGranted.selector) {
                continue;
            }
            assertEq(logs[i].topics[2], bytes32(uint256(uint160(admin))), "account");
            bool known = false;
            for (uint256 j = 0; j < admins.length; j++) {
                if (logs[i].topics[1] == admins[j]) {
                    assertFalse(granted[j], "granted twice");
                    granted[j] = true;
                    known = true;
                }
            }
            assertTrue(known, "unexpected role");
            grants++;
        }
        assertEq(grants, admins.length, "grant count");
    }

    function testInitializeWiresEachRoleToItsSelfAdministeredAdmin() external {
        (StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer, Vm.Log[] memory logs) =
            initialized(address(uint160(uint256(keccak256("ADMIN")))));
        bytes32[7] memory admins = adminRoles();
        bytes32[7] memory governed = governedRoles();
        for (uint256 i = 0; i < admins.length; i++) {
            assertEq(authorizer.getRoleAdmin(governed[i]), admins[i], "governed role admin");
            assertEq(authorizer.getRoleAdmin(admins[i]), admins[i], "admin role admin");
        }
        uint256 changes = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(authorizer) && logs[i].topics[0] == IAccessControl.RoleAdminChanged.selector)
            {
                changes++;
            }
        }
        assertEq(changes, admins.length + governed.length, "role admin changes");
    }
}

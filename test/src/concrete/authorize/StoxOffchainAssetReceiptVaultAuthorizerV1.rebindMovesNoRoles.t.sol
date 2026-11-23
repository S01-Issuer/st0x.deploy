// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibTestDeploy} from "../../../lib/LibTestDeploy.sol";
import {StoxAuthorizerInitTest} from "../../../lib/StoxAuthorizerInitTest.sol";

contract StoxOffchainAssetReceiptVaultAuthorizerV1RebindMovesNoRolesTest is StoxAuthorizerInitTest {
    function testRebindAfterInitializeMovesNoRoles(address admin, address newAdmin) external {
        vm.assume(admin != address(0) && newAdmin != address(0) && newAdmin != admin);
        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer = newAuthorizer();
        authorizer.initialize(LibTestDeploy.authorizerData(vm, admin));

        LibTestDeploy.bind(
            vm,
            LibRegistryAuthority.ROOT_AUTHORITY,
            LibTestDeploy.AUTHORIZER_INITIAL_ADMIN_NAME,
            "address",
            abi.encode(newAdmin)
        );

        assertHoldsEveryAdminRoleOnly(authorizer, admin);
        assertHoldsNoRole(authorizer, newAdmin);
    }
}

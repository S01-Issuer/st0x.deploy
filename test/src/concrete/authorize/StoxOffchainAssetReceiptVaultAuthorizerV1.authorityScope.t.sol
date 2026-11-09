// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibTestDeploy} from "../../../lib/LibTestDeploy.sol";
import {StoxAuthorizerInitTest} from "../../../lib/StoxAuthorizerInitTest.sol";

contract StoxOffchainAssetReceiptVaultAuthorizerV1AuthorityScopeTest is StoxAuthorizerInitTest {
    address constant ADMIN = address(uint160(uint256(keccak256("ADMIN"))));
    address constant OTHER_AUTHORITY = address(uint160(uint256(keccak256("OTHER_AUTHORITY"))));
    address constant OTHER_ADMIN = address(uint160(uint256(keccak256("OTHER_ADMIN"))));
    bytes32 constant NAME = LibTestDeploy.AUTHORIZER_INITIAL_ADMIN_NAME;

    function testBindingOnlyUnderAnotherAuthorityIsNotRegistered() external {
        LibTestDeploy.etchConfigRegistry(vm);
        LibTestDeploy.bind(vm, OTHER_AUTHORITY, NAME, "address", abi.encode(OTHER_ADMIN));
        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer = newAuthorizer();
        vm.expectRevert(
            abi.encodeWithSelector(IConfigRegistryV5.NameNotRegistered.selector, LibRegistryAuthority.ROOT_AUTHORITY, NAME)
        );
        authorizer.initialize(LibTestDeploy.authorizerConfig(LibRegistryAuthority.ROOT_AUTHORITY, NAME));
    }

    function testAdminIsTheNamedAuthoritysBinding() external {
        bytes memory data = LibTestDeploy.authorizerData(vm, ADMIN);
        LibTestDeploy.bind(vm, OTHER_AUTHORITY, NAME, "address", abi.encode(OTHER_ADMIN));
        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer = newAuthorizer();
        authorizer.initialize(data);
        assertHoldsEveryAdminRoleOnly(authorizer, ADMIN);
        assertHoldsNoRole(authorizer, OTHER_ADMIN);
    }
}

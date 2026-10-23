// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Clones} from "@openzeppelin-contracts-5.7.0/proxy/Clones.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable-5.7.0/proxy/utils/Initializable.sol";
import {IConfigRegistryV3} from "rain-deploy-0.1.21/src/interface/IConfigRegistryV3.sol";
import {ICLONEABLE_V2_SUCCESS} from "rain-factory-0.2.4/src/interface/ICloneableV2.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibAuthoriserClone} from "../../../../src/lib/LibAuthoriserClone.sol";
import {LibAuthoriserInvariants} from "../../../../src/lib/LibAuthoriserInvariants.sol";
import {LibStoxConfig} from "../../../../src/lib/LibStoxConfig.sol";
import {LibStoxConfigFork} from "../../../../src/lib/LibStoxConfigFork.sol";
import {RoleGrant} from "../../../../src/lib/RoleGrant.sol";

contract StoxOffchainAssetReceiptVaultAuthorizerV1Test is Test {
    /// Constructor disables initializers on the implementation.
    function testConstructorDisablesInitializers() external {
        StoxOffchainAssetReceiptVaultAuthorizerV1 impl = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(LibAuthoriserClone.cloneData());
    }

    /// The bound admin holds every `_ADMIN` role, and nobody else
    /// bound before it does.
    function testFuzzInitializeGrantsEveryAdminToTheBoundAdmin(address previous, address admin) external {
        vm.assume(admin != address(0) && previous != admin);
        LibStoxConfigFork.bindAuthoriserAdmin(vm, previous);
        LibStoxConfigFork.bindAuthoriserAdmin(vm, admin);
        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer = StoxOffchainAssetReceiptVaultAuthorizerV1(
            Clones.clone(address(new StoxOffchainAssetReceiptVaultAuthorizerV1()))
        );

        assertEq(authorizer.initialize(LibAuthoriserClone.cloneData()), ICLONEABLE_V2_SUCCESS);

        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(address(0), admin);
        for (uint256 i = 0; i < LibAuthoriserInvariants.ADMIN_ROLE_COUNT; i++) {
            assertTrue(authorizer.hasRole(grants[i].role, admin));
            assertFalse(authorizer.hasRole(grants[i].role, previous));
        }
    }

    /// An unbound admin refuses initialization.
    function testInitializeUnboundReverts() external {
        LibStoxConfigFork.etchConfigRegistry(vm);
        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer = StoxOffchainAssetReceiptVaultAuthorizerV1(
            Clones.clone(address(new StoxOffchainAssetReceiptVaultAuthorizerV1()))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV3.NameNotRegistered.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.AUTHORISER_ADMIN
            )
        );
        authorizer.initialize(LibAuthoriserClone.cloneData());
    }
}

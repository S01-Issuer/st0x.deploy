// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.30/src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibConfigRegistryDeploy.sol";

import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibStoxConfigFork} from "../../../src/lib/LibStoxConfigFork.sol";
import {LibStoxConfigHarness} from "./LibStoxConfigHarness.sol";

contract LibStoxConfigTest is Test {
    LibStoxConfigHarness internal harness;

    function setUp() external {
        harness = new LibStoxConfigHarness();
        LibStoxConfigFork.etchConfigRegistry(vm);
    }

    function expectUnbound() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME
            )
        );
    }

    function testAuthoriserInitialAdminName() external pure {
        assertEq(LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME, keccak256("st0x.authoriser-initial-admin.v1"));
    }

    function testFuzzAuthoriserInitialAdminFollowsBinding(address first, address second) external {
        LibStoxConfigFork.bindAuthoriserInitialAdmin(vm, first);
        assertEq(harness.authoriserInitialAdmin(), first);
        LibStoxConfigFork.bindAuthoriserInitialAdmin(vm, second);
        assertEq(harness.authoriserInitialAdmin(), second);
    }

    function testAuthoriserInitialAdminUnboundReverts() external {
        expectUnbound();
        harness.authoriserInitialAdmin();
    }

    function testFuzzAuthoriserInitialAdminIgnoresOtherAuthority(address authority, address admin) external {
        vm.assume(authority != LibStoxConfig.ROOT_AUTHORITY);
        vm.prank(authority);
        IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .registerV5(authority, LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME, "address", abi.encode(admin), "");
        expectUnbound();
        harness.authoriserInitialAdmin();
    }

    function testFuzzAuthoriserInitialAdminIgnoresOtherName(bytes32 name, address admin) external {
        vm.assume(name != LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME);
        LibStoxConfigFork.bind(vm, name, "address", abi.encode(admin));
        expectUnbound();
        harness.authoriserInitialAdmin();
    }

    function testFuzzAuthoriserInitialAdminRefusesAnotherValueType(address admin) external {
        LibStoxConfigFork.bind(vm, LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME, "uint256", abi.encode(admin));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.ValueTypeMismatch.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME,
                keccak256("address"),
                keccak256("uint256")
            )
        );
        harness.authoriserInitialAdmin();
    }
}

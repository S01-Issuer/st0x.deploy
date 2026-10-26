// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IConfigRegistryV3} from "rain-deploy-0.1.22/src/interface/IConfigRegistryV3.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.22/src/lib/LibConfigRegistryDeploy.sol";

import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibStoxConfigFork} from "../../../src/lib/LibStoxConfigFork.sol";
import {LibStoxConfigHarness} from "./LibStoxConfigHarness.sol";

contract LibStoxConfigTest is Test {
    LibStoxConfigHarness internal harness;

    function setUp() external {
        harness = new LibStoxConfigHarness();
        LibStoxConfigFork.etchConfigRegistry(vm);
    }

    function testFuzzBeaconOwnerFollowsBinding(address first, address second) external {
        LibStoxConfigFork.bindBeaconOwner(vm, first);
        assertEq(harness.beaconOwner(), first);
        LibStoxConfigFork.bindBeaconOwner(vm, second);
        assertEq(harness.beaconOwner(), second);
    }

    function testBeaconOwnerUnboundReverts() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV3.NameNotRegistered.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.BEACON_OWNER_NAME
            )
        );
        harness.beaconOwner();
    }

    function testFuzzBeaconOwnerIgnoresOtherAuthority(address authority, address owner) external {
        vm.assume(authority != LibStoxConfig.ROOT_AUTHORITY);
        vm.prank(authority);
        IConfigRegistryV3(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .registerV3(authority, LibStoxConfig.BEACON_OWNER_NAME, abi.encode(owner));
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV3.NameNotRegistered.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.BEACON_OWNER_NAME
            )
        );
        harness.beaconOwner();
    }

    function testFuzzBeaconOwnerIgnoresOtherName(bytes32 name, address owner) external {
        vm.assume(name != LibStoxConfig.BEACON_OWNER_NAME);
        vm.prank(LibStoxConfig.ROOT_AUTHORITY);
        IConfigRegistryV3(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .registerV3(LibStoxConfig.ROOT_AUTHORITY, name, abi.encode(owner));
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV3.NameNotRegistered.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.BEACON_OWNER_NAME
            )
        );
        harness.beaconOwner();
    }
}

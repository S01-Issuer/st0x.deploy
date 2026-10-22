// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IConfigRegistryV3} from "rain-deploy-0.1.21/src/interface/IConfigRegistryV3.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.21/src/lib/LibConfigRegistryDeploy.sol";

import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibStoxConfigFork} from "../../../src/lib/LibStoxConfigFork.sol";
import {LibStoxConfigHarness} from "./LibStoxConfigHarness.sol";

contract LibStoxConfigTest is Test {
    LibStoxConfigHarness internal harness;

    function setUp() external {
        harness = new LibStoxConfigHarness();
        LibStoxConfigFork.etchConfigRegistry(vm);
    }

    function testRootAuthority() external pure {
        assertEq(LibStoxConfig.ROOT_AUTHORITY, address(0x0b300013CD54a8F1aC40981f80FaaA18b8Cc1E4c));
    }

    function testBeaconOwnerName() external pure {
        assertEq(LibStoxConfig.BEACON_OWNER, keccak256("st0x.beacon-owner.v1"));
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
                IConfigRegistryV3.NameNotRegistered.selector, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.BEACON_OWNER
            )
        );
        harness.beaconOwner();
    }

    function testFuzzBeaconOwnerIgnoresOtherAuthority(address authority, address owner) external {
        vm.assume(authority != LibStoxConfig.ROOT_AUTHORITY);
        vm.prank(authority);
        IConfigRegistryV3(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .registerV3(authority, LibStoxConfig.BEACON_OWNER, abi.encode(owner));
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV3.NameNotRegistered.selector, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.BEACON_OWNER
            )
        );
        harness.beaconOwner();
    }

    function testFuzzBeaconOwnerIgnoresOtherName(bytes32 name, address owner) external {
        vm.assume(name != LibStoxConfig.BEACON_OWNER);
        vm.prank(LibStoxConfig.ROOT_AUTHORITY);
        IConfigRegistryV3(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .registerV3(LibStoxConfig.ROOT_AUTHORITY, name, abi.encode(owner));
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV3.NameNotRegistered.selector, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.BEACON_OWNER
            )
        );
        harness.beaconOwner();
    }
}

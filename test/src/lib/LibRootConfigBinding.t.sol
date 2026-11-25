// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.38/src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.38/src/lib/LibConfigRegistryDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.38/src/lib/LibRegistryAuthority.sol";

import {LibRootConfigBinding, RootNameBound} from "../../../src/lib/LibRootConfigBinding.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

/// @title LibRootConfigBindingTest
/// @notice `assertUnbound` passes a name the root has not bound, refuses one it has, ignores another authority's
/// binding, and refuses a registry off the pinned code.
contract LibRootConfigBindingTest is Test {
    function setUp() external {
        LibTestDeploy.etchConfigRegistry(vm);
    }

    function externalAssertUnbound(bytes32 name) external view {
        LibRootConfigBinding.assertUnbound(name);
    }

    function testFuzzAssertUnboundPassesAnUnboundName(bytes32 name) external view {
        this.externalAssertUnbound(name);
    }

    function testFuzzAssertUnboundRefusesARootBinding(bytes32 name, address value) external {
        LibTestDeploy.bind(vm, LibRegistryAuthority.ROOT_AUTHORITY, name, "address", abi.encode(value));
        vm.expectRevert(abi.encodeWithSelector(RootNameBound.selector, name, block.timestamp));
        this.externalAssertUnbound(name);
    }

    function testFuzzAssertUnboundIgnoresAnotherAuthority(address authority, bytes32 name, address value) external {
        vm.assume(authority != LibRegistryAuthority.ROOT_AUTHORITY);
        assumeNotForgeAddress(authority);
        LibTestDeploy.bind(vm, authority, name, "address", abi.encode(value));
        this.externalAssertUnbound(name);
    }

    function testAssertUnboundRefusesAnotherRegistry() external {
        vm.etch(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS, hex"00");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedConfigRegistryCodeHash.selector,
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(hex"00")
            )
        );
        this.externalAssertUnbound(bytes32(0));
    }
}

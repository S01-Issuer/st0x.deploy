// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibConfigRegistryDeploy.sol";

import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {LibStoxConfigHarness} from "./LibStoxConfigHarness.sol";

contract LibStoxConfigTest is Test {
    LibStoxConfigHarness internal harness;

    function setUp() external {
        harness = new LibStoxConfigHarness();
        LibTestDeploy.etchConfigRegistry(vm);
    }

    function testFuzzGovernanceTimelockFollowsBinding(address first, address second) external {
        LibTestDeploy.bind(
            vm, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.GOVERNANCE_TIMELOCK_NAME, "address", abi.encode(first)
        );
        assertEq(harness.governanceTimelock(), first);
        LibTestDeploy.bind(
            vm, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.GOVERNANCE_TIMELOCK_NAME, "address", abi.encode(second)
        );
        assertEq(harness.governanceTimelock(), second);
    }

    function testGovernanceTimelockUnboundReverts() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.GOVERNANCE_TIMELOCK_NAME
            )
        );
        harness.governanceTimelock();
    }

    function testFuzzGovernanceTimelockIgnoresOtherAuthority(address authority, address owner) external {
        vm.assume(authority != LibStoxConfig.ROOT_AUTHORITY);
        vm.prank(authority);
        IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .registerV5(authority, LibStoxConfig.GOVERNANCE_TIMELOCK_NAME, "address", abi.encode(owner), "");
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.GOVERNANCE_TIMELOCK_NAME
            )
        );
        harness.governanceTimelock();
    }

    function testFuzzGovernanceTimelockIgnoresOtherName(bytes32 name, address owner) external {
        vm.assume(name != LibStoxConfig.GOVERNANCE_TIMELOCK_NAME);
        vm.prank(LibStoxConfig.ROOT_AUTHORITY);
        IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .registerV5(LibStoxConfig.ROOT_AUTHORITY, name, "address", abi.encode(owner), "");
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.GOVERNANCE_TIMELOCK_NAME
            )
        );
        harness.governanceTimelock();
    }
}

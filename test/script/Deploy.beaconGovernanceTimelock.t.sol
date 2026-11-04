// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {GovernanceTimelockMismatch} from "../../script/Deploy.sol";
import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibTestDeploy} from "../lib/LibTestDeploy.sol";
import {DeployPreDeployCheckHarness} from "./DeployPreDeployCheckHarness.sol";

contract DeployBeaconGovernanceTimelockTest is Test {
    DeployPreDeployCheckHarness internal harness;

    function setUp() external {
        harness = new DeployPreDeployCheckHarness();
        LibTestDeploy.etchConfigRegistry(vm);
    }

    function bindGovernanceTimelock(address timelock) internal {
        LibTestDeploy.bind(
            vm, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.GOVERNANCE_TIMELOCK_NAME, "address", abi.encode(timelock)
        );
    }

    function testBeaconsRefuseUnboundGovernanceTimelock() external {
        DeploySuite[] memory beacons = harness.beaconSuites();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            for (uint256 j = 0; j < beacons.length; j++) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IConfigRegistryV5.NameNotRegistered.selector,
                        LibStoxConfig.ROOT_AUTHORITY,
                        LibStoxConfig.GOVERNANCE_TIMELOCK_NAME
                    )
                );
                harness.exposedPreDeployCheck(beacons[j], networks[i]);
            }
        }
    }

    function testBeaconsRefuseOtherBoundGovernanceTimelock(address bound) external {
        vm.assume(bound != LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK);
        DeploySuite[] memory beacons = harness.beaconSuites();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        bindGovernanceTimelock(bound);
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            for (uint256 j = 0; j < beacons.length; j++) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        GovernanceTimelockMismatch.selector, bound, LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK
                    )
                );
                harness.exposedPreDeployCheck(beacons[j], networks[i]);
            }
        }
    }

    function testBeaconsAcceptPinnedGovernanceTimelock() external {
        DeploySuite[] memory beacons = harness.beaconSuites();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        bindGovernanceTimelock(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK);
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            for (uint256 j = 0; j < beacons.length; j++) {
                harness.exposedPreDeployCheck(beacons[j], networks[i]);
            }
        }
    }
}

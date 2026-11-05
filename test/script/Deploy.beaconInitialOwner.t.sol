// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {BeaconInitialOwnerMismatch, GovernanceTimelockNotDeployed} from "../../script/Deploy.sol";
import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibTestDeploy} from "../lib/LibTestDeploy.sol";
import {DeployPreDeployCheckHarness} from "./DeployPreDeployCheckHarness.sol";

contract DeployBeaconInitialOwnerTest is Test {
    DeployPreDeployCheckHarness internal harness;

    function setUp() external {
        harness = new DeployPreDeployCheckHarness();
        LibTestDeploy.etchConfigRegistry(vm);
        vm.etch(
            LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK,
            LibProdDeployV4.STOX_GOVERNANCE_TIMELOCK_RUNTIME_CODE_CANDIDATE
        );
    }

    function bindBeaconInitialOwner(address owner) internal {
        LibTestDeploy.bind(
            vm, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.BEACON_INITIAL_OWNER_NAME, "address", abi.encode(owner)
        );
    }

    function testBeaconsRefuseUnboundBeaconInitialOwner() external {
        DeploySuite[] memory beacons = harness.beaconSuites();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            for (uint256 j = 0; j < beacons.length; j++) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IConfigRegistryV5.NameNotRegistered.selector,
                        LibStoxConfig.ROOT_AUTHORITY,
                        LibStoxConfig.BEACON_INITIAL_OWNER_NAME
                    )
                );
                harness.exposedPreDeployCheck(beacons[j], networks[i]);
            }
        }
    }

    function testBeaconsRefuseOtherBoundBeaconInitialOwner(address bound) external {
        // The binding refusal must come before the timelock check, so the
        // timelock is missing here too.
        vm.etch(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, "");
        vm.assume(bound != LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK);
        DeploySuite[] memory beacons = harness.beaconSuites();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        bindBeaconInitialOwner(bound);
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            for (uint256 j = 0; j < beacons.length; j++) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        BeaconInitialOwnerMismatch.selector, bound, LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK
                    )
                );
                harness.exposedPreDeployCheck(beacons[j], networks[i]);
            }
        }
    }

    function testBeaconsAcceptPinnedBeaconInitialOwner() external {
        DeploySuite[] memory beacons = harness.beaconSuites();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        bindBeaconInitialOwner(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK);
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            for (uint256 j = 0; j < beacons.length; j++) {
                harness.exposedPreDeployCheck(beacons[j], networks[i]);
            }
        }
    }

    /// The beacons are owned by the governance timelock, and no beacon suite depends on it, so with the binding right
    /// but the timelock missing its pinned code on the chain the beacons are refused.
    function testBeaconsRefuseAnUndeployedGovernanceTimelock() external {
        DeploySuite[] memory beacons = harness.beaconSuites();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        bindBeaconInitialOwner(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK);
        vm.etch(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, "");
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            for (uint256 j = 0; j < beacons.length; j++) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        GovernanceTimelockNotDeployed.selector,
                        LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK,
                        LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK_CODEHASH,
                        bytes32(0)
                    )
                );
                harness.exposedPreDeployCheck(beacons[j], networks[i]);
            }
        }
    }

    /// Any other code at the governance timelock's address is refused, with its hash.
    function testBeaconsRefuseAGovernanceTimelockWithOtherCode(bytes memory code) external {
        vm.assume(code.length > 0 && code[0] != 0xef);
        vm.assume(keccak256(code) != LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK_CODEHASH);
        DeploySuite[] memory beacons = harness.beaconSuites();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        bindBeaconInitialOwner(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK);
        vm.etch(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, code);
        vm.chainId(networks[0].chainId);
        vm.expectRevert(
            abi.encodeWithSelector(
                GovernanceTimelockNotDeployed.selector,
                LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK,
                LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK_CODEHASH,
                keccak256(code)
            )
        );
        harness.exposedPreDeployCheck(beacons[0], networks[0]);
    }

    /// The binding check runs first: with the timelock missing too, an unbound owner is what the operator sees.
    function testBeaconsReportTheBindingBeforeTheTimelock() external {
        DeploySuite[] memory beacons = harness.beaconSuites();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        vm.etch(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, "");
        vm.chainId(networks[0].chainId);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.BEACON_INITIAL_OWNER_NAME
            )
        );
        harness.exposedPreDeployCheck(beacons[0], networks[0]);
    }
}

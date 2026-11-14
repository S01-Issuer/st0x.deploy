// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {LibTimelockController} from "rain-deploy-0.1.30/src/lib/LibTimelockController.sol";
import {BeaconInitialOwnerMismatch} from "../../script/Deploy.sol";
import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTestBeaconInitialOwnerBind} from "../lib/LibTestBeaconInitialOwnerBind.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibTestDeploy} from "../lib/LibTestDeploy.sol";
import {DeployPreDeployCheckHarness} from "./DeployPreDeployCheckHarness.sol";

contract DeployBeaconInitialOwnerTest is Test {
    DeployPreDeployCheckHarness internal harness;

    function setUp() external {
        harness = new DeployPreDeployCheckHarness();
        LibTestDeploy.etchConfigRegistry(vm);
    }

    /// Deploys the governance timelock with `proposer` as its proposer.
    function deployTimelock(address proposer) internal {
        LibTestBeaconInitialOwnerBind.deployTimelock(vm, proposer);
    }

    function bindBeaconInitialOwner(address owner) internal {
        LibTestDeploy.bind(
            vm,
            LibRegistryAuthority.ROOT_AUTHORITY,
            LibStoxConfig.BEACON_INITIAL_OWNER_NAME,
            "address",
            abi.encode(owner)
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
                        LibRegistryAuthority.ROOT_AUTHORITY,
                        LibStoxConfig.BEACON_INITIAL_OWNER_NAME
                    )
                );
                harness.exposedPreDeployCheck(beacons[j], networks[i]);
            }
        }
    }

    /// The timelock is not deployed, so the binding refusal comes first.
    function testBeaconsRefuseOtherBoundBeaconInitialOwner(address bound) external {
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

    /// With the pinned binding and the timelock deployed with the chain's Safe as proposer, every beacon passes.
    function testBeaconsAcceptPinnedBeaconInitialOwner() external {
        DeploySuite[] memory beacons = harness.beaconSuites();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        bindBeaconInitialOwner(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK);
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 snapshot = vm.snapshotState();
            vm.chainId(networks[i].chainId);
            deployTimelock(LibSafeInvariants.safeForChainId(networks[i].chainId));
            for (uint256 j = 0; j < beacons.length; j++) {
                harness.exposedPreDeployCheck(beacons[j], networks[i]);
            }
            vm.revertToState(snapshot);
        }
    }

    /// With the binding right but no timelock at its address, the beacons are refused.
    function testBeaconsRefuseAnUndeployedGovernanceTimelock() external {
        DeploySuite[] memory beacons = harness.beaconSuites();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        bindBeaconInitialOwner(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK);
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            for (uint256 j = 0; j < beacons.length; j++) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        LibTimelockController.TimelockNotDeployed.selector,
                        LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK
                    )
                );
                harness.exposedPreDeployCheck(beacons[j], networks[i]);
            }
        }
    }

    /// Other code at the governance timelock's address is refused, with its hash.
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
                LibTimelockController.TimelockCodehashMismatch.selector,
                LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK,
                LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK_CODEHASH,
                keccak256(code)
            )
        );
        harness.exposedPreDeployCheck(beacons[0], networks[0]);
    }

    /// A timelock with the pinned code but another proposer than the chain's Safe is refused: anyone can deploy it
    /// with any proposer bound at construction.
    function testBeaconsRefuseAGovernanceTimelockWithAnotherProposer(address proposer) external {
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        address safe = LibSafeInvariants.safeForChainId(networks[0].chainId);
        vm.assume(proposer != safe && proposer != address(0));
        DeploySuite[] memory beacons = harness.beaconSuites();
        bindBeaconInitialOwner(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK);
        vm.chainId(networks[0].chainId);
        deployTimelock(proposer);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockMissingRole.selector,
                LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK,
                LibTimelockInvariants.TIMELOCK_PROPOSER_ROLE,
                safe
            )
        );
        harness.exposedPreDeployCheck(beacons[0], networks[0]);
    }

    /// The binding check runs first: with the timelock missing too, an unbound owner is what the operator sees.
    function testBeaconsReportTheBindingBeforeTheTimelock() external {
        DeploySuite[] memory beacons = harness.beaconSuites();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        vm.chainId(networks[0].chainId);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector,
                LibRegistryAuthority.ROOT_AUTHORITY,
                LibStoxConfig.BEACON_INITIAL_OWNER_NAME
            )
        );
        harness.exposedPreDeployCheck(beacons[0], networks[0]);
    }
}

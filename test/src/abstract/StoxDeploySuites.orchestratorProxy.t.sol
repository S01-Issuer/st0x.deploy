// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployDeclaration, DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";

import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {ST0xOrchestrator} from "../../../src/concrete/ST0xOrchestrator.sol";
import {LibOrchestratorInvariants} from "../../../src/lib/LibOrchestratorInvariants.sol";
import {LibProdOrchestratorTarget} from "../../../src/lib/LibProdOrchestratorTarget.sol";
import {LibStoxConfig, ZeroOrchestratorInitialAdmin} from "../../../src/lib/LibStoxConfig.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {LibTestOrchestratorDeploy} from "../../lib/LibTestOrchestratorDeploy.sol";

contract StoxDeploySuitesOrchestratorProxyTest is Test, StoxDeploySuites {
    address internal constant BEACON_OWNER = address(uint160(uint256(keccak256("BEACON_OWNER"))));

    function proxySuite() internal view returns (DeploySuite memory) {
        (DeploySuite memory suite, bool found) = candidateOf(declaration(), ORCHESTRATOR_PROXY);
        assertTrue(found, ORCHESTRATOR_PROXY);
        return suite;
    }

    function networks() internal view returns (SupportedNetwork[] memory) {
        SupportedNetwork[] memory nets = LibRainDeploy.declaredNetworkConfigs(proxySuite().networks);
        assertTrue(nets.length > 0, "networks");
        return nets;
    }

    function deployInstance() external returns (address) {
        LibRainDeploy.etchZoltuFactory(vm);
        LibTestOrchestratorDeploy.deployBeacon();
        return LibTestOrchestratorDeploy.deployInstance(vm, makeAddr("deployer"));
    }

    function testProxySuiteDeploysTheProductionTarget() external view {
        (, bytes memory target) = abi.decode(proxySuite().mechanismData, (bytes32, bytes));
        assertEq(target, abi.encode(LibProdOrchestratorTarget.orchestratorTarget()));
    }

    function testProxySuiteLandsAtTheInstanceOnEveryNetwork() external {
        DeployDeclaration memory declared = declaration();
        DeploySuite memory suite = proxySuite();
        SupportedNetwork[] memory nets = networks();
        address instance = LibOrchestratorInvariants.mintCapsInstance();
        for (uint256 i = 0; i < nets.length; i++) {
            assertEq(deployedAddress(declared, suite, nets[i].chainId), instance, nets[i].name);
        }
        address[] memory deployed = deployLocally(declared, vm, suite);
        assertEq(deployed.length, nets.length, "deployed");
        for (uint256 i = 0; i < deployed.length; i++) {
            assertEq(deployed[i], instance, nets[i].name);
        }
    }

    function testFuzzProxySuiteSeatsTheBoundInitialAdminOnEveryNetwork(address admin) external {
        vm.assume(admin != address(0));
        DeploySuite memory suite = proxySuite();
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            uint256 preDeploy = vm.snapshotState();
            vm.chainId(nets[i].chainId);
            LibTestDeploy.bindBeaconInitialOwner(vm, BEACON_OWNER);
            LibTestDeploy.bindOrchestratorInitialAdmin(vm, admin);
            ST0xOrchestrator instance = ST0xOrchestrator(payable(this.deployInstance()));
            assertEq(address(instance), suite.storedDeployedAddress, nets[i].name);
            assertEq(address(instance).code, suite.storedRuntimeCode, nets[i].name);
            assertEq(address(instance).codehash, suite.storedBytecodeHash, nets[i].name);
            assertTrue(instance.hasRole(instance.DEFAULT_ADMIN_ROLE(), admin), "DEFAULT_ADMIN_ROLE");
            assertTrue(instance.hasRole(instance.MINT_ADMIN_ROLE(), admin), "MINT_ADMIN_ROLE");
            assertTrue(instance.hasRole(instance.BURN_ADMIN_ROLE(), admin), "BURN_ADMIN_ROLE");
            assertTrue(instance.hasRole(instance.EMERGENCY_ADMIN_ROLE(), admin), "EMERGENCY_ADMIN_ROLE");
            vm.revertToState(preDeploy);
        }
    }

    function testProxySuiteRefusesWhereTheInitialAdminIsUnbound() external {
        LibTestDeploy.bindBeaconInitialOwner(vm, BEACON_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME
            )
        );
        this.deployInstance();
    }

    function testProxySuiteRefusesWhereTheInitialAdminIsBoundToZero() external {
        LibTestDeploy.bindBeaconInitialOwner(vm, BEACON_OWNER);
        LibTestDeploy.bindOrchestratorInitialAdmin(vm, address(0));
        vm.expectRevert(abi.encodeWithSelector(ZeroOrchestratorInitialAdmin.selector));
        this.deployInstance();
    }
}

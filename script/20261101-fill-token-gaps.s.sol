// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {DeployDependency, LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_V7_ADDRESS,
    RUNTIME_CODE as CLONE_FACTORY_V7_RUNTIME_CODE
} from "rain-factory-deploy-0.2.4/src/generated/0_2_4/CloneFactory.sol";
import {
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS,
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.29/src/generated/0_1_29/ConfigRegistry.sol";
import {
    LibRainDeployRegistryBeaconProxy,
    RegistryBeaconProxyTarget
} from "rain-factory-0.2.9/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {StoxDeploySuites} from "../src/abstract/StoxDeploySuites.sol";
import {LibStoxTokenProxy} from "../src/generated/LibStoxTokenProxy.sol";
import {LibStoxVaultBeacon} from "../src/generated/LibStoxVaultBeacon.sol";

contract FillTokenGaps is StoxDeploySuites, Script {
    function run() external {
        string[] memory names = networkNames();
        SupportedNetwork[] memory networks = LibRainDeploy.declaredNetworkConfigs(names);
        DeployDependency[] memory dependencies = tokenDependencies();
        bytes32 expectedCodeHash = keccak256(LibStoxTokenProxy.RUNTIME_CODE);
        RegistryBeaconProxyTarget[] memory targets = tokenTargets();
        for (uint256 i = 0; i < targets.length; i++) {
            address proxy = LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(targets[i]);
            LibRainDeploy.deployStepToNetworks(
                vm,
                networks,
                msg.sender,
                LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployStep,
                LibRainDeploy.everyNetwork(networks.length, abi.encode(targets[i]), proxy, proxy),
                expectedCodeHash,
                dependencies
            );
        }
    }

    function check() external {
        string[] memory names = networkNames();
        SupportedNetwork[] memory networks = LibRainDeploy.declaredNetworkConfigs(names);
        DeployDependency[] memory dependencies = tokenDependencies();
        bytes32 expectedCodeHash = keccak256(LibStoxTokenProxy.RUNTIME_CODE);
        RegistryBeaconProxyTarget[] memory targets = tokenTargets();
        uint256[] memory forkIds = LibRainDeploy.createForks(vm, names);
        for (uint256 n = 0; n < networks.length; n++) {
            vm.selectFork(forkIds[n]);
            LibRainDeploy.checkNetworkChainId(networks[n]);
            LibRainDeploy.checkDeclaredDependencies(networks[n].name, dependencies);
            for (uint256 i = 0; i < targets.length; i++) {
                LibRainDeploy.checkDeployedCode(
                    networks[n].name,
                    LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(targets[i]),
                    expectedCodeHash
                );
            }
        }
    }

    function networkNames() internal view returns (string[] memory) {
        string[] memory names = new string[](1);
        names[0] = vm.envString("NETWORK");
        return names;
    }

    function tokenDependencies() internal pure returns (DeployDependency[] memory) {
        DeployDependency[] memory dependencies = new DeployDependency[](3);
        dependencies[0] =
            DeployDependency({deployedAddress: CLONE_FACTORY_V7_ADDRESS, runtimeCode: CLONE_FACTORY_V7_RUNTIME_CODE});
        dependencies[1] =
            DeployDependency({deployedAddress: CONFIG_REGISTRY_ADDRESS, runtimeCode: CONFIG_REGISTRY_RUNTIME_CODE});
        dependencies[2] =
            DeployDependency({deployedAddress: vaultBeacon(), runtimeCode: LibStoxVaultBeacon.RUNTIME_CODE});
        return dependencies;
    }
}

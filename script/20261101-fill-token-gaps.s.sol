// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {DeployDependency, LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {
    LibRainDeployRegistryBeaconProxy,
    RegistryBeaconProxyTarget
} from "rain-factory-0.2.9/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibProdTokenTargets} from "../src/lib/LibProdTokenTargets.sol";
import {LibStoxTokenProxy} from "../src/generated/LibStoxTokenProxy.sol";

contract FillTokenGaps is Script, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.notAMigration();
    }

    function run() external {
        string[] memory names = networkNames();
        SupportedNetwork[] memory networks = LibRainDeploy.declaredNetworkConfigs(names);
        DeployDependency[] memory dependencies = LibProdTokenTargets.tokenDependencies();
        bytes32 expectedCodeHash = keccak256(LibStoxTokenProxy.RUNTIME_CODE);
        RegistryBeaconProxyTarget[] memory targets = LibProdTokenTargets.tokenTargets();
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
        DeployDependency[] memory dependencies = LibProdTokenTargets.tokenDependencies();
        bytes32 expectedCodeHash = keccak256(LibStoxTokenProxy.RUNTIME_CODE);
        RegistryBeaconProxyTarget[] memory targets = LibProdTokenTargets.tokenTargets();
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
}

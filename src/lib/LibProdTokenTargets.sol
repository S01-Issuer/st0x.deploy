// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {DeployDependency} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {
    LibRainDeployRegistryBeaconProxy,
    RegistryBeaconProxyTarget
} from "rain-factory-0.2.10/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_V8_ADDRESS,
    RUNTIME_CODE as CLONE_FACTORY_V8_RUNTIME_CODE
} from "rain-factory-deploy-0.2.6/src/generated/0_2_5/CloneFactory.sol";
import {
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS,
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.30/src/generated/0_1_29/ConfigRegistry.sol";
import {
    OffchainAssetReceiptVaultConfigV3,
    OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG
} from "rain-vats-0.2.18/src/interface/IOffchainAssetReceiptVaultV1.sol";
import {LibProdDeployV4 as V4} from "../generated/LibProdDeployV4.sol";
import {LibStoxTokenProxy} from "../generated/LibStoxTokenProxy.sol";
import {LibStoxConfig} from "./LibStoxConfig.sol";
import {Region, TokenConfig} from "./LibProdTokenConfig.sol";

library LibProdTokenTargets {
    function tokenTargets(TokenConfig[] memory configs) internal pure returns (RegistryBeaconProxyTarget[] memory) {
        RegistryBeaconProxyTarget[] memory targets = new RegistryBeaconProxyTarget[](configs.length);
        address beacon = vaultBeacon();
        for (uint256 i = 0; i < configs.length; i++) {
            targets[i] = RegistryBeaconProxyTarget({
                factory: CLONE_FACTORY_V8_ADDRESS,
                registry: CONFIG_REGISTRY_ADDRESS,
                authority: LibRegistryAuthority.ROOT_AUTHORITY,
                beaconName: LibStoxConfig.VAULT_BEACON_NAME,
                beacon: beacon,
                data: tokenData(configs[i]),
                salt: keccak256(bytes(configs[i].underlying))
            });
        }
        return targets;
    }

    function tokenData(TokenConfig memory config) internal pure returns (bytes memory) {
        return abi.encode(
            OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG,
            OffchainAssetReceiptVaultConfigV3({
                name: config.name,
                symbol: config.symbol,
                authority: LibRegistryAuthority.ROOT_AUTHORITY,
                rbacName: config.region == Region.US ? LibStoxConfig.RBAC_US_NAME : LibStoxConfig.RBAC_EU_NAME,
                receiptBeaconName: LibStoxConfig.RECEIPT_BEACON_NAME,
                metadata: ""
            })
        );
    }

    function vaultBeacon() internal pure returns (address) {
        return V4.STOX_RECEIPT_VAULT_BEACON_CANDIDATE;
    }

    function tokenDependencies() internal pure returns (DeployDependency[] memory) {
        DeployDependency[] memory dependencies = new DeployDependency[](3);
        dependencies[0] =
            DeployDependency({deployedAddress: CLONE_FACTORY_V8_ADDRESS, runtimeCode: CLONE_FACTORY_V8_RUNTIME_CODE});
        dependencies[1] =
            DeployDependency({deployedAddress: CONFIG_REGISTRY_ADDRESS, runtimeCode: CONFIG_REGISTRY_RUNTIME_CODE});
        dependencies[2] = DeployDependency({
            deployedAddress: vaultBeacon(), runtimeCode: V4.STOX_RECEIPT_VAULT_BEACON_RUNTIME_CODE_CANDIDATE
        });
        return dependencies;
    }

    function wrapperTargets(TokenConfig[] memory configs) internal pure returns (RegistryBeaconProxyTarget[] memory) {
        RegistryBeaconProxyTarget[] memory targets = tokenTargets(configs);
        for (uint256 i = 0; i < targets.length; i++) {
            address token = LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(targets[i]);
            targets[i].beaconName = LibStoxConfig.WRAPPER_BEACON_NAME;
            targets[i].beacon = wrapperBeacon();
            targets[i].data = abi.encode(token);
        }
        return targets;
    }

    function wrapperBeacon() internal pure returns (address) {
        return V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CANDIDATE;
    }

    function wrapperDependencies(address token) internal pure returns (DeployDependency[] memory) {
        DeployDependency[] memory dependencies = new DeployDependency[](4);
        dependencies[0] =
            DeployDependency({deployedAddress: CLONE_FACTORY_V8_ADDRESS, runtimeCode: CLONE_FACTORY_V8_RUNTIME_CODE});
        dependencies[1] =
            DeployDependency({deployedAddress: CONFIG_REGISTRY_ADDRESS, runtimeCode: CONFIG_REGISTRY_RUNTIME_CODE});
        dependencies[2] = DeployDependency({
            deployedAddress: wrapperBeacon(), runtimeCode: V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_RUNTIME_CODE_CANDIDATE
        });
        dependencies[3] = DeployDependency({deployedAddress: token, runtimeCode: LibStoxTokenProxy.RUNTIME_CODE});
        return dependencies;
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {DeployDependency} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.38/src/lib/LibRegistryAuthority.sol";
import {
    LibRainDeployRegistryBeaconProxy,
    RegistryBeaconProxyParams
} from "rain-factory-0.2.18/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_V8_ADDRESS,
    RUNTIME_CODE as CLONE_FACTORY_V8_RUNTIME_CODE
} from "rain-factory-deploy-0.2.14/src/generated/0_2_5/CloneFactory.sol";
import {
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS,
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.38/src/generated/0_1_29/ConfigRegistry.sol";
import {LibProdDeployV4 as V4} from "../generated/LibProdDeployV4.sol";
import {LibStoxTokenProxy} from "../generated/LibStoxTokenProxy.sol";
import {LibStoxConfig} from "./LibStoxConfig.sol";
import {StoxTokenConfigV1, STOX_TOKEN_CONFIG_V1_TAG, AssetIdKind} from "../interface/IStoxTokenConfigV1.sol";
import {Region, TokenConfig} from "./LibProdTokenConfig.sol";

library LibProdTokenParams {
    function tokenParams(TokenConfig[] memory configs) internal pure returns (RegistryBeaconProxyParams[] memory) {
        RegistryBeaconProxyParams[] memory params = new RegistryBeaconProxyParams[](configs.length);
        for (uint256 i = 0; i < configs.length; i++) {
            params[i] = tokenParam(configs[i]);
        }
        return params;
    }

    function tokenParam(TokenConfig memory config) internal pure returns (RegistryBeaconProxyParams memory) {
        return RegistryBeaconProxyParams({
            factory: CLONE_FACTORY_V8_ADDRESS,
            registry: CONFIG_REGISTRY_ADDRESS,
            authority: LibRegistryAuthority.ROOT_AUTHORITY,
            beaconName: LibStoxConfig.VAULT_BEACON_NAME,
            beacon: vaultBeacon(),
            data: tokenData(config),
            // The clone factory's effective salt already hashes `data`.
            salt: bytes32(0)
        });
    }

    /// @notice The address the token suite deploys `config`'s receipt vault
    /// to. It commits to the `StoxTokenConfigV1` init data, so a vault at it
    /// was initialized from the row's listing facts.
    function tokenAddress(TokenConfig memory config) internal pure returns (address) {
        return LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(tokenParam(config));
    }

    function tokenData(TokenConfig memory config) internal pure returns (bytes memory) {
        return abi.encode(
            STOX_TOKEN_CONFIG_V1_TAG,
            StoxTokenConfigV1({
                assetId: config.assetId,
                assetIdKind: AssetIdKind.ISIN,
                listingTicker: config.listingTicker,
                listingName: config.listingName,
                region: config.region,
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
        DeployDependency[] memory dependencies = new DeployDependency[](4);
        dependencies[0] =
            DeployDependency({deployedAddress: CLONE_FACTORY_V8_ADDRESS, runtimeCode: CLONE_FACTORY_V8_RUNTIME_CODE});
        dependencies[1] =
            DeployDependency({deployedAddress: CONFIG_REGISTRY_ADDRESS, runtimeCode: CONFIG_REGISTRY_RUNTIME_CODE});
        dependencies[2] = DeployDependency({
            deployedAddress: vaultBeacon(), runtimeCode: V4.STOX_RECEIPT_VAULT_BEACON_RUNTIME_CODE_CANDIDATE
        });
        dependencies[3] = DeployDependency({
            deployedAddress: V4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE,
            runtimeCode: V4.STOX_CORPORATE_ACTIONS_FACET_RUNTIME_CODE_CANDIDATE
        });
        return dependencies;
    }

    function wrapperParams(TokenConfig[] memory configs) internal pure returns (RegistryBeaconProxyParams[] memory) {
        RegistryBeaconProxyParams[] memory params = tokenParams(configs);
        for (uint256 i = 0; i < params.length; i++) {
            address token = LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(params[i]);
            params[i].beaconName = LibStoxConfig.WRAPPER_BEACON_NAME;
            params[i].beacon = wrapperBeacon();
            params[i].data = abi.encode(token);
        }
        return params;
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

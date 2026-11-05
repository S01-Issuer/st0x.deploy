// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {DeployDependency} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {
    LibRainDeployRegistryBeaconProxy,
    RegistryBeaconProxyParams
} from "rain-factory-0.2.11/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_V8_ADDRESS,
    RUNTIME_CODE as CLONE_FACTORY_V8_RUNTIME_CODE
} from "rain-factory-deploy-0.2.8/src/generated/0_2_5/CloneFactory.sol";
import {
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS,
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.30/src/generated/0_1_29/ConfigRegistry.sol";
import {
    OffchainAssetReceiptVaultConfigV3,
    OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG
} from "rain-vats-0.2.20/src/interface/IOffchainAssetReceiptVaultV1.sol";
import {LibProdDeployV4 as V4} from "../generated/LibProdDeployV4.sol";
import {LibStoxTokenProxy} from "../generated/LibStoxTokenProxy.sol";
import {LibStoxConfig} from "./LibStoxConfig.sol";
import {Region, TokenConfig} from "./LibProdTokenConfig.sol";
import {LibAssetId} from "./LibAssetId.sol";

/// @title LibProdTokenParams
/// @notice The V8 registry beacon proxy each V6 token row deploys as: unnamed, with the row's asset id as metadata and
/// its hash as salt, so its address depends only on the asset id, the region, the authority and the beacon names.
library LibProdTokenParams {
    /// @param configs The rows; each needs a non-empty `assetId`, or its deploy reverts.
    /// @return One set of params per row, in the same order.
    function tokenParams(TokenConfig[] memory configs) internal pure returns (RegistryBeaconProxyParams[] memory) {
        RegistryBeaconProxyParams[] memory params = new RegistryBeaconProxyParams[](configs.length);
        for (uint256 i = 0; i < configs.length; i++) {
            params[i] = tokenParam(configs[i]);
        }
        return params;
    }

    /// @param config The row.
    /// @return The row's params, salted by its asset id.
    function tokenParam(TokenConfig memory config) internal pure returns (RegistryBeaconProxyParams memory) {
        return proxyParams(tokenData(config), keccak256(bytes(config.assetId)));
    }

    /// @param data The init data.
    /// @param salt The salt.
    /// @return A registry beacon proxy over the root authority's vault beacon; its runtime code ignores `data` and `salt`.
    function proxyParams(bytes memory data, bytes32 salt) internal pure returns (RegistryBeaconProxyParams memory) {
        return RegistryBeaconProxyParams({
            factory: CLONE_FACTORY_V8_ADDRESS,
            registry: CONFIG_REGISTRY_ADDRESS,
            authority: LibRegistryAuthority.ROOT_AUTHORITY,
            beaconName: LibStoxConfig.VAULT_BEACON_NAME,
            beacon: vaultBeacon(),
            data: data,
            salt: salt
        });
    }

    /// @param config The row.
    /// @return The canonical V3 config with an empty name and symbol and the row's asset id as metadata.
    function tokenData(TokenConfig memory config) internal pure returns (bytes memory) {
        return abi.encode(
            OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG,
            OffchainAssetReceiptVaultConfigV3({
                name: "",
                symbol: "",
                authority: LibRegistryAuthority.ROOT_AUTHORITY,
                rbacName: config.region == Region.US ? LibStoxConfig.RBAC_US_NAME : LibStoxConfig.RBAC_EU_NAME,
                receiptBeaconName: LibStoxConfig.RECEIPT_BEACON_NAME,
                metadata: LibAssetId.encodeMetadata(config.assetId)
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

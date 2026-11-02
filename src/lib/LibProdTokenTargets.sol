// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {DeployDependency} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {RegistryBeaconProxyTarget} from "rain-factory-0.2.9/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_V8_ADDRESS,
    RUNTIME_CODE as CLONE_FACTORY_V8_RUNTIME_CODE
} from "rain-factory-deploy-0.2.5/src/generated/0_2_5/CloneFactory.sol";
import {
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS,
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.29/src/generated/0_1_29/ConfigRegistry.sol";
import {
    OffchainAssetReceiptVaultConfigV3,
    OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG
} from "rain-vats-0.2.16/src/interface/IOffchainAssetReceiptVaultV1.sol";
import {LibProdDeployV4 as V4} from "../generated/LibProdDeployV4.sol";
import {LibStoxVaultBeacon} from "../generated/LibStoxVaultBeacon.sol";
import {LibStoxConfig} from "./LibStoxConfig.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "./LibProdTokenConfig.sol";

library LibProdTokenTargets {
    function tokenTargets() internal pure returns (RegistryBeaconProxyTarget[] memory) {
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        RegistryBeaconProxyTarget[] memory targets = new RegistryBeaconProxyTarget[](configs.length);
        address beacon = vaultBeacon();
        for (uint256 i = 0; i < configs.length; i++) {
            targets[i] = RegistryBeaconProxyTarget({
                factory: CLONE_FACTORY_V8_ADDRESS,
                registry: CONFIG_REGISTRY_ADDRESS,
                authority: LibStoxConfig.ROOT_AUTHORITY,
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
                authority: LibStoxConfig.ROOT_AUTHORITY,
                rbacName: config.region == Region.US ? LibStoxConfig.RBAC_US_NAME : LibStoxConfig.RBAC_EU_NAME,
                receiptBeaconName: LibStoxConfig.RECEIPT_BEACON_NAME,
                metadata: ""
            })
        );
    }

    /// The beacon-set deployer creates the receipt beacon then the vault
    /// beacon in its constructor, so the vault beacon is its nonce-2 CREATE.
    function vaultBeacon() internal pure returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xd6),
                            bytes1(0x94),
                            V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1,
                            bytes1(0x02)
                        )
                    )
                )
            )
        );
    }

    function tokenDependencies() internal pure returns (DeployDependency[] memory) {
        DeployDependency[] memory dependencies = new DeployDependency[](3);
        dependencies[0] =
            DeployDependency({deployedAddress: CLONE_FACTORY_V8_ADDRESS, runtimeCode: CLONE_FACTORY_V8_RUNTIME_CODE});
        dependencies[1] =
            DeployDependency({deployedAddress: CONFIG_REGISTRY_ADDRESS, runtimeCode: CONFIG_REGISTRY_RUNTIME_CODE});
        dependencies[2] =
            DeployDependency({deployedAddress: vaultBeacon(), runtimeCode: LibStoxVaultBeacon.RUNTIME_CODE});
        return dependencies;
    }
}

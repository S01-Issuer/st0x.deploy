// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {DeployDependency} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
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
import {LibProdDeployV4 as V4} from "../generated/LibProdDeployV4.sol";
import {LibStoxTokenProxy} from "../generated/LibStoxTokenProxy.sol";
import {Region, TokenConfig} from "./LibProdTokenConfig.sol";
import {LibProdTokenTargets} from "./LibProdTokenTargets.sol";
import {LibStoxConfig} from "./LibStoxConfig.sol";

/// @title LibStoxTestTokens
/// @notice One test token per region, each a registry beacon proxy over the
/// bound vault beacon, with a wrapper that is a registry beacon proxy over the
/// bound wrapper beacon. Neither address commits to the chain or the beacon, so
/// each lands at the same address on every chain. Each row has a synthetic
/// asset id that cannot collide with an ISIN, and both the token and the
/// wrapper are salted by it, so neither address moves when the name, symbol
/// or ticker changes.
library LibStoxTestTokens {
    function testTokenConfigs() internal pure returns (TokenConfig[] memory) {
        TokenConfig[] memory configs = new TokenConfig[](2);
        configs[0] = TokenConfig({
            underlying: "USTEST",
            name: "US Test ST0x",
            symbol: "tUSTEST",
            region: Region.US,
            underlyingName: "US Test",
            assetId: "ST0XTESTUS"
        });
        configs[1] = TokenConfig({
            underlying: "EUTEST",
            name: "EU Test ST0x",
            symbol: "tEUTEST",
            region: Region.EU,
            underlyingName: "EU Test",
            assetId: "ST0XTESTEU"
        });
        return configs;
    }

    function tokenAddress(TokenConfig memory config) internal pure returns (address) {
        return
            LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(LibProdTokenTargets.tokenTarget(config));
    }

    function wrapperBeacon() internal pure returns (address) {
        return V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CANDIDATE;
    }

    function wrapperTarget(TokenConfig memory config) internal pure returns (RegistryBeaconProxyTarget memory) {
        return RegistryBeaconProxyTarget({
            factory: CLONE_FACTORY_V8_ADDRESS,
            registry: CONFIG_REGISTRY_ADDRESS,
            authority: LibStoxConfig.ROOT_AUTHORITY,
            beaconName: LibStoxConfig.WRAPPER_BEACON_NAME,
            beacon: wrapperBeacon(),
            data: abi.encode(tokenAddress(config)),
            salt: keccak256(bytes(config.assetId))
        });
    }

    function wrapperDependencies(TokenConfig memory config) internal pure returns (DeployDependency[] memory) {
        DeployDependency[] memory dependencies = new DeployDependency[](4);
        dependencies[0] =
            DeployDependency({deployedAddress: CLONE_FACTORY_V8_ADDRESS, runtimeCode: CLONE_FACTORY_V8_RUNTIME_CODE});
        dependencies[1] =
            DeployDependency({deployedAddress: CONFIG_REGISTRY_ADDRESS, runtimeCode: CONFIG_REGISTRY_RUNTIME_CODE});
        dependencies[2] = DeployDependency({
            deployedAddress: wrapperBeacon(), runtimeCode: V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_RUNTIME_CODE_CANDIDATE
        });
        dependencies[3] =
            DeployDependency({deployedAddress: tokenAddress(config), runtimeCode: LibStoxTokenProxy.RUNTIME_CODE});
        return dependencies;
    }
}

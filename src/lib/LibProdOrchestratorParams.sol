// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {RegistryBeaconProxyParams} from "rain-factory-0.2.11/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_V8_ADDRESS
} from "rain-factory-deploy-0.2.8/src/generated/0_2_5/CloneFactory.sol";
import {DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS} from "rain-deploy-0.1.30/src/generated/0_1_29/ConfigRegistry.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {LibProdDeployV4 as V4} from "../generated/LibProdDeployV4.sol";
import {LibStoxConfig} from "./LibStoxConfig.sol";

library LibProdOrchestratorParams {
    string constant ORCHESTRATOR = "stox-orchestrator";

    function orchestratorParams() internal pure returns (RegistryBeaconProxyParams memory) {
        return RegistryBeaconProxyParams({
            factory: CLONE_FACTORY_V8_ADDRESS,
            registry: CONFIG_REGISTRY_ADDRESS,
            authority: LibRegistryAuthority.ROOT_AUTHORITY,
            beaconName: LibStoxConfig.ORCHESTRATOR_BEACON_NAME,
            beacon: V4.ST0X_ORCHESTRATOR_BEACON_CANDIDATE,
            data: "",
            salt: keccak256(bytes(ORCHESTRATOR))
        });
    }
}

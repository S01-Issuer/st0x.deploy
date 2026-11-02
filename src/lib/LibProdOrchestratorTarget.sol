// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {RegistryBeaconProxyTarget} from "rain-factory-0.2.9/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {DEPLOYED_ADDRESS as CLONE_FACTORY_V7_ADDRESS} from "rain-factory-deploy-0.2.5/src/generated/0_2_5/CloneFactory.sol";
import {DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS} from "rain-deploy-0.1.29/src/generated/0_1_29/ConfigRegistry.sol";
import {LibProdDeployV4 as V4} from "../generated/LibProdDeployV4.sol";
import {LibStoxConfig} from "./LibStoxConfig.sol";

library LibProdOrchestratorTarget {
    string constant ORCHESTRATOR = "stox-orchestrator";

    function orchestratorTarget() internal pure returns (RegistryBeaconProxyTarget memory) {
        return RegistryBeaconProxyTarget({
            factory: CLONE_FACTORY_V7_ADDRESS,
            registry: CONFIG_REGISTRY_ADDRESS,
            authority: LibStoxConfig.ROOT_AUTHORITY,
            beaconName: LibStoxConfig.ORCHESTRATOR_BEACON_NAME,
            beacon: V4.ST0X_ORCHESTRATOR_BEACON_V2_CANDIDATE,
            data: "",
            salt: keccak256(bytes(ORCHESTRATOR))
        });
    }
}

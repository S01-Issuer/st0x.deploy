// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {
    LibRainDeployRegistryBeaconProxy,
    RegistryBeaconProxyTarget
} from "rain-factory-0.2.10/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {
    RUNTIME_CODE as CLONE_FACTORY_RUNTIME_CODE
} from "rain-factory-deploy-0.2.6/src/generated/0_2_5/CloneFactory.sol";

import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibProdOrchestratorTarget} from "../../src/lib/LibProdOrchestratorTarget.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibTestDeploy} from "./LibTestDeploy.sol";

/// @title LibTestOrchestratorDeploy
/// @notice The orchestrator as production deploys it: the candidate
/// `ST0xOrchestrator` and `ST0xOrchestratorBeacon` Zoltu-deployed, the root
/// authority binding `LibStoxConfig.ORCHESTRATOR_BEACON_NAME` to the beacon,
/// and the instance the pinned clone factory deploys as the registry beacon
/// proxy of `LibProdOrchestratorTarget.orchestratorTarget()`. The beacon
/// initial owner and the orchestrator initial admin MUST be bound first: the
/// beacon's owner is resolved at construction and the instance's admin at
/// `initialize`.
library LibTestOrchestratorDeploy {
    /// Zoltu-deploys the candidate orchestrator and its beacon, refusing
    /// either off its pinned address.
    function deployBeacon() internal returns (address) {
        address implementation = LibRainDeploy.deployZoltu(LibProdDeployV4.ST0X_ORCHESTRATOR_CREATION_CODE_CANDIDATE);
        require(implementation == LibProdDeployV4.ST0X_ORCHESTRATOR_CANDIDATE, "ST0xOrchestrator address mismatch");
        address beacon = LibRainDeploy.deployZoltu(LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_CREATION_CODE_CANDIDATE);
        require(beacon == LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_CANDIDATE, "ST0xOrchestratorBeacon address mismatch");
        return beacon;
    }

    /// The root authority binds the beacon name to the deployed beacon, then
    /// `deployer` runs the production deploy step of the orchestrator target.
    function deployInstance(Vm vm, address deployer) internal returns (address) {
        RegistryBeaconProxyTarget memory target = LibProdOrchestratorTarget.orchestratorTarget();
        vm.etch(target.factory, CLONE_FACTORY_RUNTIME_CODE);
        LibTestDeploy.bind(
            vm,
            LibRegistryAuthority.ROOT_AUTHORITY,
            LibStoxConfig.ORCHESTRATOR_BEACON_NAME,
            "address",
            abi.encode(target.beacon)
        );
        return LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployStep(vm, "base", deployer, abi.encode(target));
    }

    /// The beacon, then the instance.
    function deployAll(Vm vm, address deployer) internal returns (address) {
        LibRainDeploy.etchZoltuFactory(vm);
        deployBeacon();
        return deployInstance(vm, deployer);
    }
}

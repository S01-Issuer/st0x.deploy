// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.37/src/lib/LibConfigRegistry.sol";
import {LibRainDeploy} from "rain-deploy-0.1.37/src/lib/LibRainDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.37/src/lib/LibRegistryAuthority.sol";

import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibTestBeaconInitialOwnerBind} from "./LibTestBeaconInitialOwnerBind.sol";
import {LibTestConfigRegistryDelegates} from "./LibTestConfigRegistryDelegates.sol";
import {LibTestDeploy} from "./LibTestDeploy.sol";
import {LibTestOrchestratorDeploy} from "./LibTestOrchestratorDeploy.sol";

/// @title LibTestOrchestratorConfigBind
/// @notice The orchestrator config bind's ConfigRegistry state on a fork.
library LibTestOrchestratorConfigBind {
    /// @notice The root approves `safe` unscoped, as on chain.
    function approveSafe(Vm vm, address safe) internal {
        LibTestConfigRegistryDelegates.approveUnscoped(vm, safe);
    }

    /// @notice Deploys the candidate orchestrator beacon, owned by the bound
    /// beacon initial owner.
    function deployBeacon(Vm vm) internal {
        LibRainDeploy.etchZoltuFactory(vm);
        LibTestOrchestratorDeploy.deployBeacon();
    }

    /// @notice Deploys the governance timelock with `safe` as its proposer,
    /// binds it as the beacon initial owner, then deploys the candidate
    /// orchestrator beacon owned by it.
    function deployTargets(Vm vm, address safe) internal {
        address timelock = LibTestBeaconInitialOwnerBind.deployTimelock(vm, safe);
        LibTestDeploy.bind(
            vm,
            LibRegistryAuthority.ROOT_AUTHORITY,
            LibStoxConfig.BEACON_INITIAL_OWNER_NAME,
            "address",
            abi.encode(timelock)
        );
        deployBeacon(vm);
    }

    /// @notice The bound orchestrator beacon.
    function boundBeacon() internal view returns (address) {
        (bytes memory value,) = LibConfigRegistry.resolve(
            LibRegistryAuthority.ROOT_AUTHORITY, LibStoxConfig.ORCHESTRATOR_BEACON_NAME, keccak256("address")
        );
        return abi.decode(value, (address));
    }
}

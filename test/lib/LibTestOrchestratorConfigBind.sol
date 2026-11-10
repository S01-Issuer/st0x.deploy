// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.30/src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibConfigRegistryDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {LibSafeFork} from "rain-deploy-0.1.30/src/lib/LibSafeFork.sol";

import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {BindOrchestratorConfigHarness} from "../script/BindOrchestratorConfigHarness.sol";

/// @title LibTestOrchestratorConfigBind
/// @notice The orchestrator config bind's ConfigRegistry state on a fork, and
/// the bind landed as the Safe would.
library LibTestOrchestratorConfigBind {
    /// @notice The root approves `safe` to bind `name`.
    function approve(Vm vm, bytes32 name, address safe) internal {
        vm.prank(LibRegistryAuthority.ROOT_AUTHORITY);
        IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS).approveV5(name, safe);
    }

    /// @notice The root approves `safe` to bind the orchestrator beacon and
    /// initial admin.
    function approveSafe(Vm vm, address safe) internal {
        approve(vm, LibStoxConfig.ORCHESTRATOR_BEACON_NAME, safe);
        approve(vm, LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME, safe);
    }

    /// @notice The bound orchestrator beacon.
    function boundBeacon() internal view returns (address) {
        (bytes memory value,) = LibConfigRegistry.resolve(
            LibRegistryAuthority.ROOT_AUTHORITY, LibStoxConfig.ORCHESTRATOR_BEACON_NAME, keccak256("address")
        );
        return abi.decode(value, (address));
    }

    /// @notice Approves `safe` and executes the bind bundle from it.
    function execute(Vm vm, address safe, string memory artifactTag) internal {
        approveSafe(vm, safe);
        BindOrchestratorConfigHarness bind = new BindOrchestratorConfigHarness(artifactTag);
        bind.callPreflight();
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), bind.callAuthorBundle());
    }
}

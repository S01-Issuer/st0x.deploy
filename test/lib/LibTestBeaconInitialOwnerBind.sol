// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibConfigRegistryDeploy.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {LibSafeFork} from "rain-deploy-0.1.30/src/lib/LibSafeFork.sol";

import {StoxGovernanceTimelock} from "../../src/concrete/StoxGovernanceTimelock.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {BindBeaconInitialOwnerHarness} from "../script/BindBeaconInitialOwnerHarness.sol";

/// @title LibTestBeaconInitialOwnerBind
/// @notice The beacon-initial-owner bind's ConfigRegistry state on a fork,
/// and the bind landed as the Safe would.
library LibTestBeaconInitialOwnerBind {
    /// @notice Deploys the governance timelock with `safe` as its proposer.
    /// @return The deployed timelock.
    function deployTimelock(Vm vm, address safe) internal returns (address) {
        vm.prank(LibRegistryAuthority.ROOT_AUTHORITY);
        IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .registerV5(
                LibRegistryAuthority.ROOT_AUTHORITY,
                LibStoxConfig.TIMELOCK_INITIAL_PROPOSER_NAME,
                "address",
                abi.encode(safe),
                ""
            );
        return LibRainDeploy.etchAndDeployZoltu(vm, type(StoxGovernanceTimelock).creationCode);
    }

    /// @notice The root approves `safe` to bind the beacon initial owner.
    function approveSafe(Vm vm, address safe) internal {
        vm.prank(LibRegistryAuthority.ROOT_AUTHORITY);
        IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .approveV5(LibStoxConfig.BEACON_INITIAL_OWNER_NAME, safe);
    }

    /// @notice Deploys the timelock, approves `safe` and executes the bind
    /// bundle from it.
    function execute(Vm vm, address safe, string memory artifactTag) internal {
        deployTimelock(vm, safe);
        approveSafe(vm, safe);
        BindBeaconInitialOwnerHarness bind = new BindBeaconInitialOwnerHarness(artifactTag);
        bind.callPreflight();
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), bind.callAuthorBundle());
    }
}

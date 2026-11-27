// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.41/src/interface/IConfigRegistryV5.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.41/src/lib/LibConfigRegistryDeploy.sol";
import {LibRainDeploy} from "rain-deploy-0.1.41/src/lib/LibRainDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.41/src/lib/LibRegistryAuthority.sol";
import {LibSafeFork} from "rain-deploy-0.1.41/src/lib/LibSafeFork.sol";

import {StoxGovernanceTimelock} from "../../src/concrete/StoxGovernanceTimelock.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {BindBeaconInitialOwnerHarness} from "../script/BindBeaconInitialOwnerHarness.sol";
import {CreateZerogTokensHarness} from "../script/CreateZerogTokensHarness.sol";
import {ExecuteZerogOrchestratorRolesHarness} from "../script/ExecuteZerogOrchestratorRolesHarness.sol";
import {ScheduleZerogOrchestratorRolesHarness} from "../script/ScheduleZerogOrchestratorRolesHarness.sol";
import {LibTestConfigRegistryDelegates} from "./LibTestConfigRegistryDelegates.sol";

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

    /// @notice The root approves `safe` unscoped, as on chain.
    function approveSafe(Vm vm, address safe) internal {
        LibTestConfigRegistryDelegates.approveUnscoped(vm, safe);
    }

    /// @notice Executes from `safe`, on a chain other than 0G with the line at
    /// the backfill, the 0G token creation's bundle: its record alone.
    function executeZerogTokensRecord(Vm vm, address safe, string memory artifactTag) internal {
        CreateZerogTokensHarness creation = new CreateZerogTokensHarness(artifactTag);
        creation.callPreflight();
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), creation.callAuthorBundle());
        creation.callAssertPostState();
    }

    /// @notice Executes from `safe`, on a chain other than 0G with the line at
    /// the 0G token creation, the 0G orchestrator roles' two bundles: the
    /// schedule's record alone, then the execution's, the bind's onto.
    function executeZerogOrchestratorRolesRecords(Vm vm, address safe, string memory artifactTag) internal {
        ScheduleZerogOrchestratorRolesHarness schedule = new ScheduleZerogOrchestratorRolesHarness(artifactTag);
        schedule.callPreflight();
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), schedule.callAuthorBundle());
        schedule.callAssertPostState();
        ExecuteZerogOrchestratorRolesHarness execution = new ExecuteZerogOrchestratorRolesHarness(artifactTag);
        execution.callPreflight();
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), execution.callAuthorBundle());
        execution.callAssertPostState();
    }

    /// @notice Deploys the timelock, approves `safe` and executes from it,
    /// with the line at the backfill, the 0G token creation's record, the 0G
    /// orchestrator roles' records and then the bind bundle.
    function execute(Vm vm, address safe, string memory artifactTag) internal {
        deployTimelock(vm, safe);
        approveSafe(vm, safe);
        executeZerogTokensRecord(vm, safe, artifactTag);
        executeZerogOrchestratorRolesRecords(vm, safe, artifactTag);
        BindBeaconInitialOwnerHarness bind = new BindBeaconInitialOwnerHarness(artifactTag);
        bind.callPreflight();
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), bind.callAuthorBundle());
    }
}

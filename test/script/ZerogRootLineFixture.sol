// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IConfigRegistryV5} from "rain-deploy-0.1.38/src/interface/IConfigRegistryV5.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.38/src/lib/LibConfigRegistryDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.38/src/lib/LibRegistryAuthority.sol";
import {LibSafeFork} from "rain-deploy-0.1.38/src/lib/LibSafeFork.sol";
import {BYTECODE_HASH as CONFIG_REGISTRY_CODEHASH} from "rain-deploy-0.1.38/src/generated/candidate/ConfigRegistry.sol";

import {ExecuteUnderlyingNaming} from "../../script/20261021-execute-underlying-naming.s.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {IRecordScriptHooks} from "../lib/RootLineRecordScriptTest.sol";
import {BindBeaconInitialOwnerHarness} from "./BindBeaconInitialOwnerHarness.sol";
import {BindOrchestratorConfigHarness} from "./BindOrchestratorConfigHarness.sol";
import {ExecuteRevokeServiceSignerDepositWithdrawHarness} from "./ExecuteRevokeServiceSignerDepositWithdrawHarness.sol";
import {ExecuteUnderlyingNamingHarness} from "./ExecuteUnderlyingNamingHarness.sol";
import {ExecuteZerogOrchestratorRolesHarness} from "./ExecuteZerogOrchestratorRolesHarness.sol";
import {HandSafeOwnedBaseVaultsToTimelockHarness} from "./HandSafeOwnedBaseVaultsToTimelockHarness.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {QsepSetFleetAuthoriserHarness} from "./QsepSetFleetAuthoriserHarness.sol";
import {
    ScheduleRevokeServiceSignerDepositWithdrawHarness
} from "./ScheduleRevokeServiceSignerDepositWithdrawHarness.sol";
import {ScheduleUnderlyingNamingBeaconsHarness} from "./ScheduleUnderlyingNamingBeaconsHarness.sol";
import {ScheduleUnderlyingNamingRenameHarness} from "./ScheduleUnderlyingNamingRenameHarness.sol";
import {UnderlyingNamingRolloutFixture} from "./UnderlyingNamingRolloutFixture.sol";
import {ZerogOrchestratorRolesFixture} from "./ZerogOrchestratorRolesFixture.sol";

/// @title ZerogRootLineFixture
/// @notice Live 0G at the token creation's record, then the root line walked past it: the 0G orchestrator roles
/// scheduled as the signers will, executed after the delay and recorded, then each later migration through its own 0G
/// bundle. The underlying naming schedules both batches onto the planted implementations, a roleless key executes them
/// after the delay, and the Safe records the execution; every other later migration's 0G bundle is the record alone.
abstract contract ZerogRootLineFixture is ZerogOrchestratorRolesFixture, UnderlyingNamingRolloutFixture {
    IConfigRegistryV5 internal constant CONFIG_REGISTRY =
        IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);

    /// @notice The migrations after the 0G token creation, in line order.
    function zerogLine() internal pure returns (bytes32[12] memory) {
        return [
            LibStoxMigrations.SCHEDULE_ZEROG_ORCHESTRATOR_ROLES,
            LibStoxMigrations.EXECUTE_ZEROG_ORCHESTRATOR_ROLES,
            LibStoxMigrations.BIND_BEACON_INITIAL_OWNER,
            LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK,
            LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK,
            LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS,
            LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME,
            LibStoxMigrations.EXECUTE_UNDERLYING_NAMING,
            LibStoxMigrations.SCHEDULE_REVOKE_SERVICE_SIGNER,
            LibStoxMigrations.EXECUTE_REVOKE_SERVICE_SIGNER,
            LibStoxMigrations.QSEP_SET_FLEET_AUTHORISER,
            LibStoxMigrations.BIND_ORCHESTRATOR_CONFIG
        ];
    }

    /// @notice From a line at or past the token creation, lands each migration after its head through `target`.
    function landZerogLineThrough(bytes32 target) internal {
        bytes32[12] memory line = zerogLine();
        bytes32 onto = LibStoxMigrations.CREATE_ZEROG_TOKENS;
        for (uint256 i = 0; i < line.length; i++) {
            if (LibStoxMigrations.applied(line[i]) == 0) landZerogMigration(line[i], onto);
            if (line[i] == target) {
                assertEq(LibStoxMigrations.head(), target, "line at the target");
                return;
            }
            onto = line[i];
        }
        revert("target is not on 0G's line after the token creation");
    }

    /// @notice From a line at or past the token creation, lands each migration after its head up to the one before
    /// `next`.
    function landZerogLineBefore(bytes32 next) internal {
        bytes32[12] memory line = zerogLine();
        if (line[0] == next) return;
        for (uint256 i = 1; i < line.length; i++) {
            if (line[i] == next) {
                landZerogLineThrough(line[i - 1]);
                return;
            }
        }
        revert("next is not on 0G's line after the token creation");
    }

    /// @notice Lands `migration` onto `onto` on 0G: the orchestrator roles as the signers and a stranger land them, the
    /// underlying naming as the Safe and a roleless key land it, and any other migration's 0G bundle.
    function landZerogMigration(bytes32 migration, bytes32 onto) internal {
        assertEq(LibStoxMigrations.head(), onto, "line at the onto");
        if (migration == LibStoxMigrations.SCHEDULE_ZEROG_ORCHESTRATOR_ROLES) {
            scheduleAsSigners();
        } else if (migration == LibStoxMigrations.EXECUTE_ZEROG_ORCHESTRATOR_ROLES) {
            executeAfterTheDelay();
            runRecordOnly(IRecordScriptHooks(address(new ExecuteZerogOrchestratorRolesHarness("zerog-line"))));
        } else if (migration == LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS) {
            plantImplementations();
            runBundle(IRecordScriptHooks(address(new ScheduleUnderlyingNamingBeaconsHarness("zerog-line"))));
        } else if (migration == LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME) {
            runBundle(IRecordScriptHooks(address(new ScheduleUnderlyingNamingRenameHarness("zerog-line"))));
        } else if (migration == LibStoxMigrations.EXECUTE_UNDERLYING_NAMING) {
            // forge-lint: disable-next-line(block-timestamp)
            vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
            ExecuteUnderlyingNaming executor = new ExecuteUnderlyingNaming();
            executor.execute();
            executor.execute();
            runRecordOnly(IRecordScriptHooks(address(new ExecuteUnderlyingNamingHarness("zerog-line"))));
        } else if (migration == LibStoxMigrations.BIND_BEACON_INITIAL_OWNER) {
            runRecordOnly(IRecordScriptHooks(address(new BindBeaconInitialOwnerHarness("zerog-line"))));
        } else if (migration == LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) {
            runRecordOnly(IRecordScriptHooks(address(new OrchestratorAdminToTimelockHarness("zerog-line"))));
        } else if (migration == LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK) {
            runRecordOnly(IRecordScriptHooks(address(new HandSafeOwnedBaseVaultsToTimelockHarness("zerog-line"))));
        } else if (migration == LibStoxMigrations.SCHEDULE_REVOKE_SERVICE_SIGNER) {
            runRecordOnly(
                IRecordScriptHooks(address(new ScheduleRevokeServiceSignerDepositWithdrawHarness("zerog-line")))
            );
        } else if (migration == LibStoxMigrations.EXECUTE_REVOKE_SERVICE_SIGNER) {
            runRecordOnly(
                IRecordScriptHooks(address(new ExecuteRevokeServiceSignerDepositWithdrawHarness("zerog-line")))
            );
        } else if (migration == LibStoxMigrations.QSEP_SET_FLEET_AUTHORISER) {
            runRecordOnly(IRecordScriptHooks(address(new QsepSetFleetAuthoriserHarness("zerog-line"))));
        } else if (migration == LibStoxMigrations.BIND_ORCHESTRATOR_CONFIG) {
            runRecordOnly(IRecordScriptHooks(address(new BindOrchestratorConfigHarness("zerog-line"))));
        } else {
            revert("no 0G landing for the migration");
        }
        assertEq(LibStoxMigrations.head(), migration, "migration heads the line");
    }

    /// @notice Pre-flight, the bundle through the 0G Safe, then the post-state, after checking the 0G bundle is the
    /// record alone.
    function runRecordOnly(IRecordScriptHooks script) internal {
        assertEq(script.callAuthorBundle().length, 1, "0G bundle is the record alone");
        runBundle(script);
    }

    /// @notice Pre-flight, the bundle through the 0G Safe, then the post-state.
    function runBundle(IRecordScriptHooks script) internal {
        script.callPreflight();
        LibSafeFork.executeBundle(vm, zerogSafe(), script.callAuthorBundle());
        script.callAssertPostState();
    }

    /// @notice The root binds `name` to `value` on 0G, as it could at any moment.
    function bindAsRoot(bytes32 name, address value) internal {
        vm.prank(LibRegistryAuthority.ROOT_AUTHORITY);
        CONFIG_REGISTRY.registerV5(LibRegistryAuthority.ROOT_AUTHORITY, name, "address", abi.encode(value), "");
    }

    /// @notice Whether `name` is bound under the root authority in the ConfigRegistry.
    function rootBound(bytes32 name) internal view returns (bool) {
        assertEq(address(CONFIG_REGISTRY).codehash, CONFIG_REGISTRY_CODEHASH, "ConfigRegistry present");
        // slither-disable-next-line low-level-calls
        (bool ok,) = address(CONFIG_REGISTRY)
            .staticcall(abi.encodeCall(IConfigRegistryV5.getV5, (LibRegistryAuthority.ROOT_AUTHORITY, name)));
        return ok;
    }
}

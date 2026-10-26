// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.22/src/lib/LibMigrationRegistryDeploy.sol";
import {
    RUNTIME_CODE as MIGRATION_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.22/src/generated/candidate/MigrationRegistry.sol";
import {LibRainDeploy} from "rain-deploy-0.1.22/src/lib/LibRainDeploy.sol";
import {LibSafe} from "rain-deploy-0.1.22/src/lib/LibSafe.sol";
import {LibSafeFork} from "rain-deploy-0.1.22/src/lib/LibSafeFork.sol";

import {EmergencyNotGranted} from "../../script/20261006-grant-orchestrator-emergency.s.sol";
import {GrantOrchestratorEmergencyHarness} from "./GrantOrchestratorEmergencyHarness.sol";
import {ST0xOrchestrator} from "../../src/concrete/ST0xOrchestrator.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {IST0xOrchestratorV1} from "../../src/interface/deprecated/IST0xOrchestratorV1.sol";
import {
    LibOrchestratorInvariants,
    OrchestratorVaultLogicUnexpected,
    ST0xOrchestratorBeaconSetDeployerLike
} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @title GrantOrchestratorEmergencyTest
/// @notice The grant's preflight and post-state without a fork: a local Base
/// with the pinned registry, a v1.4.1 Safe in the token-owner policy, the
/// pinned timelock, the 0.1.30 orchestrator beacon set owned by the timelock
/// and an orchestrator the Safe administers.
contract GrantOrchestratorEmergencyTest is Test {
    ST0xOrchestrator internal constant ORCHESTRATOR =
        ST0xOrchestrator(payable(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE));

    GrantOrchestratorEmergencyHarness internal script;
    Safe internal safe;

    function setUp() external {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        (uint256 executedAt,) = LibStoxMigrations.governanceTimelockExecution(block.chainid);
        vm.warp(executedAt + 1 days);

        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, MIGRATION_REGISTRY_RUNTIME_CODE);
        vm.etch(LibSafe.SAFE_V1_4_1_L2_SINGLETON, LibSafe.SAFE_V1_4_1_L2_SINGLETON_RUNTIME_CODE);
        vm.etch(
            LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER,
            LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER_RUNTIME_CODE
        );
        vm.etch(LibSafe.SAFE_V1_4_1_MULTI_SEND_CALL_ONLY, LibSafe.SAFE_V1_4_1_MULTI_SEND_CALL_ONLY_RUNTIME_CODE);

        safe = Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
        vm.etch(address(safe), LibSafe.SAFE_V1_4_1_PROXY_RUNTIME_CODE);
        vm.store(address(safe), bytes32(0), bytes32(uint256(uint160(LibSafe.SAFE_V1_4_1_L2_SINGLETON))));
        safe.setup(
            LibSafeInvariants.expectedOwners(),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD,
            address(0),
            "",
            LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER,
            address(0),
            0,
            payable(address(0))
        );

        LibRainDeploy.etchZoltuFactory(vm);
        address timelock = LibRainDeploy.deployZoltu(LibTimelockInvariants.timelockInitCode(address(safe)));
        LibRainDeploy.deployZoltu(LibProdDeployV4.ST0X_ORCHESTRATOR_CREATION_CODE_0_1_30);
        address setDeployer =
            LibRainDeploy.deployZoltu(LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CREATION_CODE_0_1_30);
        Ownable beacon = Ownable(address(ST0xOrchestratorBeaconSetDeployerLike(setDeployer).iOrchestratorBeacon()));
        vm.prank(beacon.owner());
        beacon.transferOwnership(timelock);

        vm.etch(address(ORCHESTRATOR), address(new ST0xOrchestrator()).code);
        ORCHESTRATOR.initialize(address(safe));
        vm.mockCall(
            address(ORCHESTRATOR), abi.encodeCall(IST0xOrchestratorV1.vaultLogicIsExpected, ()), abi.encode(true)
        );

        script = new GrantOrchestratorEmergencyHarness();
    }

    function executeGrant() internal {
        LibSafeFork.executeBundle(vm, safe, script.callAuthorBundle());
    }

    function failVaultLogicLock() internal {
        vm.mockCall(
            address(ORCHESTRATOR), abi.encodeCall(IST0xOrchestratorV1.vaultLogicIsExpected, ()), abi.encode(false)
        );
    }

    function testPreflightAcceptsTheChainBeforeTheGrant() external view {
        script.callPreflight();
    }

    function testPreflightRefusesOrchestratorWithFailingVaultLogicLock() external {
        failVaultLogicLock();
        vm.expectRevert(abi.encodeWithSelector(OrchestratorVaultLogicUnexpected.selector, address(ORCHESTRATOR)));
        script.callPreflight();
    }

    function testPostStateAcceptsTheExecutedGrant() external {
        executeGrant();
        assertTrue(ORCHESTRATOR.hasRole(ORCHESTRATOR.EMERGENCY_ROLE(), address(safe)));
        script.callAssertPostState();
    }

    function testPostStateRefusesSafeWithoutEmergency() external {
        executeGrant();
        bytes32 emergency = ORCHESTRATOR.EMERGENCY_ROLE();
        vm.prank(address(safe));
        ORCHESTRATOR.revokeRole(emergency, address(safe));
        vm.expectRevert(abi.encodeWithSelector(EmergencyNotGranted.selector));
        script.callAssertPostState();
    }

    function testPostStateRefusesOrchestratorWithFailingVaultLogicLock() external {
        executeGrant();
        failVaultLogicLock();
        vm.expectRevert(abi.encodeWithSelector(OrchestratorVaultLogicUnexpected.selector, address(ORCHESTRATOR)));
        script.callAssertPostState();
    }
}

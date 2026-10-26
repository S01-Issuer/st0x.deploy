// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.22/src/lib/LibMigrationRegistryDeploy.sol";
import {
    RUNTIME_CODE as MIGRATION_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.22/src/generated/candidate/MigrationRegistry.sol";
import {LibSafe} from "rain-deploy-0.1.22/src/lib/LibSafe.sol";
import {LibSafeFork} from "rain-deploy-0.1.22/src/lib/LibSafeFork.sol";

import {EmergencyNotGranted} from "../../script/20261006-grant-orchestrator-emergency.s.sol";
import {GrantOrchestratorEmergencyHarness} from "./GrantOrchestratorEmergencyHarness.sol";
import {ST0xOrchestrator} from "../../src/concrete/ST0xOrchestrator.sol";
import {IST0xOrchestratorV1} from "../../src/interface/deprecated/IST0xOrchestratorV1.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";

/// @title GrantOrchestratorEmergencyTest
/// @notice The grant's post-state without a fork: a local Base with the pinned
/// registry, a v1.4.1 Safe in the token-owner policy and an orchestrator the
/// Safe administers, with the bundle executed through the Safe.
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

        vm.etch(address(ORCHESTRATOR), address(new ST0xOrchestrator()).code);
        ORCHESTRATOR.initialize(address(safe));
        vm.mockCall(
            address(ORCHESTRATOR), abi.encodeCall(IST0xOrchestratorV1.vaultLogicIsExpected, ()), abi.encode(true)
        );

        script = new GrantOrchestratorEmergencyHarness();
        LibSafeFork.executeBundle(vm, safe, script.callAuthorBundle());
    }

    function testPostStateAcceptsTheExecutedGrant() external view {
        assertTrue(ORCHESTRATOR.hasRole(ORCHESTRATOR.EMERGENCY_ROLE(), address(safe)));
        script.callAssertPostState();
    }

    function testPostStateRefusesSafeWithoutEmergency() external {
        bytes32 emergency = ORCHESTRATOR.EMERGENCY_ROLE();
        vm.prank(address(safe));
        ORCHESTRATOR.revokeRole(emergency, address(safe));
        vm.expectRevert(abi.encodeWithSelector(EmergencyNotGranted.selector));
        script.callAssertPostState();
    }
}

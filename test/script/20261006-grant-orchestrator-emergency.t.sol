// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {LibSafeFork} from "rain-deploy-0.1.25/src/lib/LibSafeFork.sol";

import {
    EmergencyNotGranted,
    grantOrchestratorEmergencyDeclaration
} from "../../script/20261006-grant-orchestrator-emergency.s.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.25/src/lib/LibMigrationRegistry.sol";
import {SafeTx} from "rain-deploy-0.1.25/src/lib/LibSafeTx.sol";
import {LibStoxMigrations, RecordMismatch, SafeNotApprovedWriter} from "../../src/lib/LibStoxMigrations.sol";
import {LibMigrationLineFork} from "../lib/LibMigrationLineFork.sol";
import {GrantOrchestratorEmergencyHarness} from "./GrantOrchestratorEmergencyHarness.sol";
import {LocalBaseOrchestratorFixture} from "./LocalBaseOrchestratorFixture.sol";
import {IST0xOrchestratorV1} from "../../src/interface/deprecated/IST0xOrchestratorV1.sol";
import {OrchestratorVaultLogicUnexpected} from "../../src/lib/LibOrchestratorInvariants.sol";

/// @title GrantOrchestratorEmergencyTest
/// @notice The grant's preflight and post-state on a local Base, with the
/// bundle executed through the Safe.
contract GrantOrchestratorEmergencyTest is LocalBaseOrchestratorFixture {
    GrantOrchestratorEmergencyHarness internal script;

    function setUp() external {
        buildLocalBase();
        script = new GrantOrchestratorEmergencyHarness("test");
        LibMigrationLineFork.approve(vm, address(safe));
        assertFalse(LibMigrationLineFork.recordOnto(vm, grantOrchestratorEmergencyDeclaration()));
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

    function testBundleIsTheGrantThenTheRecord() external view {
        SafeTx[] memory txs = script.callAuthorBundle();
        assertEq(txs.length, 2);
        assertEq(txs[0].to, address(ORCHESTRATOR));
        (address registry, bytes memory data) = LibStoxMigrations.recordCall(grantOrchestratorEmergencyDeclaration());
        assertEq(txs[1].to, registry);
        assertEq(txs[1].data, data);
    }

    function testBundleRecordsOnlyWhereEmergencyIsHeld() external {
        bytes32 emergency = ORCHESTRATOR.EMERGENCY_ROLE();
        vm.prank(address(safe));
        ORCHESTRATOR.grantRole(emergency, address(safe));
        SafeTx[] memory txs = script.callAuthorBundle();
        assertEq(txs.length, 1);
        LibSafeFork.executeBundle(vm, safe, txs);
        script.callAssertPostState();
        assertEq(LibStoxMigrations.head(), grantOrchestratorEmergencyDeclaration().id);
    }

    function testPreflightRefusesAnUnapprovedSafe() external {
        vm.prank(LibStoxMigrations.WRITER);
        LibMigrationRegistry.revokeV3(LibStoxMigrations.NAMESPACE, address(safe));
        vm.expectRevert(abi.encodeWithSelector(SafeNotApprovedWriter.selector, address(safe)));
        script.callPreflight();
    }

    function testPostStateRefusesAGrantWithoutTheRecord() external {
        bytes32 emergency = ORCHESTRATOR.EMERGENCY_ROLE();
        vm.prank(address(safe));
        ORCHESTRATOR.grantRole(emergency, address(safe));
        vm.expectRevert(
            abi.encodeWithSelector(
                RecordMismatch.selector, grantOrchestratorEmergencyDeclaration().id, block.timestamp, uint256(0)
            )
        );
        script.callAssertPostState();
    }
}

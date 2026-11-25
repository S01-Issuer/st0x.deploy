// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.38/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.38/src/lib/LibSafeFork.sol";

import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {IRecordScriptHooks, RootLineRecordScriptTest} from "../lib/RootLineRecordScriptTest.sol";
import {ExecuteZerogOrchestratorRolesHarness} from "./ExecuteZerogOrchestratorRolesHarness.sol";
import {ScheduleZerogOrchestratorRolesHarness} from "./ScheduleZerogOrchestratorRolesHarness.sol";
import {ZerogOrchestratorRolesFixture} from "./ZerogOrchestratorRolesFixture.sol";

/// @title ExecuteZerogOrchestratorRolesOffZerogRootLineTest
/// @notice Off 0G the bundle is the record alone, right after the schedule's record alone, with nothing scheduled or
/// executed. Live 0G stands in for HyperEVM, as in the schedule's off-0G test.
contract ExecuteZerogOrchestratorRolesOffZerogRootLineTest is ZerogOrchestratorRolesFixture, RootLineRecordScriptTest {
    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new ExecuteZerogOrchestratorRolesHarness("off-zerog-root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.EXECUTE_ZEROG_ORCHESTRATOR_ROLES;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.SCHEDULE_ZEROG_ORCHESTRATOR_ROLES;
    }

    function landBeforeOnto() internal override {
        forkZerogAtTheTokenRecord();
        vm.chainId(LibSafeInvariants.HYPEREVM_CHAIN_ID);
    }

    /// @dev The schedule's record-only bundle.
    function landOnto() internal override {
        ScheduleZerogOrchestratorRolesHarness schedule = new ScheduleZerogOrchestratorRolesHarness("off-zerog-onto");
        schedule.callPreflight();
        LibSafeFork.executeBundle(vm, zerogSafe(), schedule.callAuthorBundle());
        schedule.callAssertPostState();
    }

    function testBundleIsTheRecordAlone() external view {
        SafeTx[] memory txs = sScript.callAuthorBundle();
        assertEq(txs.length, 1, "bundle length");
    }
}

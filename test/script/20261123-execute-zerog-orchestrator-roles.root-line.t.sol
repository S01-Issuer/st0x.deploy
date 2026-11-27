// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.43/src/lib/LibSafeTx.sol";

import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {IRecordScriptHooks, RootLineRecordScriptTest} from "../lib/RootLineRecordScriptTest.sol";
import {ExecuteZerogOrchestratorRolesHarness} from "./ExecuteZerogOrchestratorRolesHarness.sol";
import {ZerogOrchestratorRolesFixture} from "./ZerogOrchestratorRolesFixture.sol";

/// @title ExecuteZerogOrchestratorRolesRootLineTest
/// @notice The execution's record on live 0G, onto the schedule's record, once the batch has executed.
contract ExecuteZerogOrchestratorRolesRootLineTest is ZerogOrchestratorRolesFixture, RootLineRecordScriptTest {
    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new ExecuteZerogOrchestratorRolesHarness("root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.EXECUTE_ZEROG_ORCHESTRATOR_ROLES;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.SCHEDULE_ZEROG_ORCHESTRATOR_ROLES;
    }

    function landBeforeOnto() internal override {
        forkZerogAtTheTokenRecord();
    }

    /// @dev The schedule as the signers land it, then the batch executed after the delay.
    function landOnto() internal override {
        scheduleAsSigners();
        executeAfterTheDelay();
    }

    function testBundleIsTheRecordAlone() external view {
        SafeTx[] memory txs = sScript.callAuthorBundle();
        assertEq(txs.length, 1, "bundle length");
    }
}

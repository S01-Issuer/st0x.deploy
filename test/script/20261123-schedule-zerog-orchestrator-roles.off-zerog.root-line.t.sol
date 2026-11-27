// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.43/src/lib/LibSafeTx.sol";

import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {IRecordScriptHooks, RootLineRecordScriptTest} from "../lib/RootLineRecordScriptTest.sol";
import {ScheduleZerogOrchestratorRolesHarness} from "./ScheduleZerogOrchestratorRolesHarness.sol";
import {ZerogOrchestratorRolesFixture} from "./ZerogOrchestratorRolesFixture.sol";

/// @title ScheduleZerogOrchestratorRolesOffZerogRootLineTest
/// @notice Off 0G the bundle is the record alone, right after the token creation. Live 0G stands in for HyperEVM: its
/// Safe and timelock are at HyperEVM's pinned addresses, so under HyperEVM's chain id the script reads them through the
/// shared pins.
contract ScheduleZerogOrchestratorRolesOffZerogRootLineTest is ZerogOrchestratorRolesFixture, RootLineRecordScriptTest {
    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new ScheduleZerogOrchestratorRolesHarness("off-zerog-root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.SCHEDULE_ZEROG_ORCHESTRATOR_ROLES;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.CREATE_ZEROG_TOKENS;
    }

    function landBeforeOnto() internal override {
        forkZerogBeforeTheTokenRecord();
        vm.chainId(LibSafeInvariants.HYPEREVM_CHAIN_ID);
    }

    function landOnto() internal override {
        LibTestRootLine.write(
            vm, safeAddress(), LibStoxMigrations.CREATE_ZEROG_TOKENS, LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5
        );
    }

    function testBundleIsTheRecordAlone() external view {
        SafeTx[] memory txs = sScript.callAuthorBundle();
        assertEq(txs.length, 1, "bundle length");
    }
}

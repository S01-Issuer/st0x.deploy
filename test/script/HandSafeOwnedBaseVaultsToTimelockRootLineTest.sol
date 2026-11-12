// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {OwnerManager} from "safe-global-safe-smart-account-1.4.1-3/contracts/base/OwnerManager.sol";
import {LibSafe} from "rain-deploy-0.1.30/src/lib/LibSafe.sol";
import {LibSafeFork} from "rain-deploy-0.1.30/src/lib/LibSafeFork.sol";

import {BackfillMigrationRegistryV5Harness} from "./BackfillMigrationRegistryV5Harness.sol";
import {HandSafeOwnedBaseVaultsToTimelockHarness} from "./HandSafeOwnedBaseVaultsToTimelockHarness.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {LibTestBeaconInitialOwnerBind} from "../lib/LibTestBeaconInitialOwnerBind.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";
import {IRecordScriptHooks, RootLineRecordScriptTest} from "../lib/RootLineRecordScriptTest.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";

/// @title HandSafeOwnedBaseVaultsToTimelockRootLineTest
/// @notice The hand-over on `network()` at its pinned pre-backfill block, onto
/// the executed V5 backfill, beacon-initial-owner bind and orchestrator admin
/// move bundles.
abstract contract HandSafeOwnedBaseVaultsToTimelockRootLineTest is RootLineRecordScriptTest {
    function network() internal pure virtual returns (string memory);

    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new HandSafeOwnedBaseVaultsToTimelockHarness("root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK;
    }

    function landBeforeOnto() internal override {
        LibTestPreBackfillFork.select(vm, network());
        LibSafeFork.executeBundle(
            vm, Safe(payable(safeAddress())), new BackfillMigrationRegistryV5Harness("root-line").callAuthorBundle()
        );
        LibTestBeaconInitialOwnerBind.execute(vm, safeAddress(), "root-line");
    }

    function landOnto() internal override {
        LibSafeFork.executeBundle(
            vm, Safe(payable(safeAddress())), new OrchestratorAdminToTimelockHarness("root-line").callAuthorBundle()
        );
    }

    function testPreflightRefusesASafeOffPolicy() external {
        vm.mockCall(safeAddress(), abi.encodeCall(OwnerManager.getThreshold, ()), abi.encode(uint256(1)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeThresholdMismatch.selector,
                safeAddress(),
                LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD,
                1
            )
        );
        sScript.callPreflight();
    }
}

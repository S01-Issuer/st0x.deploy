// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/OwnableUpgradeable.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.30/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.30/src/lib/LibSafeTxBuilderJson.sol";
import {SafeBundleScript} from "rain-deploy-0.1.30/src/abstract/SafeBundleScript.sol";

import {ExecuteUnderlyingNaming} from "../../script/20261021-execute-underlying-naming.s.sol";
import {
    scheduleUnderlyingNamingBeaconsDeclaration
} from "../../script/20261021-schedule-underlying-naming-beacons.s.sol";
import {ScheduleUnderlyingNamingBeaconsHarness} from "./ScheduleUnderlyingNamingBeaconsHarness.sol";
import {ScheduleUnderlyingNamingRenameHarness} from "./ScheduleUnderlyingNamingRenameHarness.sol";
import {BackfillMigrationRegistryV5Harness} from "./BackfillMigrationRegistryV5Harness.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {LibTestBeaconInitialOwnerBind} from "../lib/LibTestBeaconInitialOwnerBind.sol";
import {LibTestOrchestratorConfigBind} from "../lib/LibTestOrchestratorConfigBind.sol";
import {IOwnable} from "../../src/interface/IOwnable.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {TokenInstance, ReceiptVaultOwnerMismatch} from "../../src/lib/LibTokenInvariants.sol";
import {LibUnderlyingNamingRollout} from "../../src/lib/LibUnderlyingNamingRollout.sol";

/// @title UnderlyingNamingRolloutFixture
/// @notice Brings a forked deployment network through the underlying-naming
/// rollout's steps as the Safe and the executing key would.
abstract contract UnderlyingNamingRolloutFixture is Test {
    /// @notice Lands, as the Safe would, the root-line records before the
    /// beacon schedule: the V5 backfill, the orchestrator config bind, the
    /// beacon-initial-owner bind, then the orchestrator admin move.
    function advanceRootLineToBeaconSchedule() internal {
        Safe safe = Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
        BackfillMigrationRegistryV5Harness backfill = new BackfillMigrationRegistryV5Harness("underlying-naming");
        backfill.callPreflight();
        LibSafeFork.executeBundle(vm, safe, backfill.callAuthorBundle());
        LibTestOrchestratorConfigBind.execute(vm, address(safe), "underlying-naming");
        LibTestBeaconInitialOwnerBind.execute(vm, address(safe), "underlying-naming");
        OrchestratorAdminToTimelockHarness adminMove = new OrchestratorAdminToTimelockHarness("underlying-naming");
        adminMove.callPreflight();
        LibSafeFork.executeBundle(vm, safe, adminMove.callAuthorBundle());
        assertEq(LibStoxMigrations.head(), scheduleUnderlyingNamingBeaconsDeclaration().onto, "line at the beacon onto");
    }

    /// @notice `run()` authors and proves the bundle on a snapshot, `verify`
    /// holds the artifact to the live re-derivation, and the artifact is then
    /// executed by the owners as the Safe UI would.
    function authorVerifyExecute(address script, string memory artifactPath) internal {
        uint256 preRun = vm.snapshotState();
        SafeBundleScript(script).run();
        vm.revertToState(preRun);
        SafeBundleScript(script).verify(artifactPath);
        (, address artifactSafe, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, vm.readFile(artifactPath));
        assertEq(artifactSafe, LibSafeInvariants.safeForChainId(block.chainid), "artifact Safe");
        uint256 gasBefore = gasleft();
        LibSafeFork.executeBundle(vm, Safe(payable(artifactSafe)), txs);
        console2.log("Safe bundle execution gas (upper bound, includes signing):", gasBefore - gasleft());
    }

    /// @notice Executes `txs[0 .. count)` from the chain's Safe.
    function executePrefix(SafeTx[] memory txs, uint256 count) internal {
        SafeTx[] memory prefix = new SafeTx[](count);
        for (uint256 txIndex = 0; txIndex < count; txIndex++) {
            prefix[txIndex] = txs[txIndex];
        }
        LibSafeFork.executeBundle(vm, Safe(payable(LibSafeInvariants.safeForChainId(block.chainid))), prefix);
    }

    /// @notice Plants the three implementations at their pinned addresses,
    /// running their constructors there (the facet's `_SELF`).
    function plantImplementations() internal {
        deployCodeTo(
            "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet", LibUnderlyingNamingRollout.FACET
        );
        deployCodeTo(
            "src/concrete/StoxReceiptVault.sol:StoxReceiptVault",
            LibUnderlyingNamingRollout.RECEIPT_VAULT_IMPLEMENTATION
        );
        deployCodeTo(
            "src/concrete/StoxWrappedTokenVault.sol:StoxWrappedTokenVault",
            LibUnderlyingNamingRollout.WRAPPED_TOKEN_VAULT_IMPLEMENTATION
        );
    }

    /// @notice Every production vault must be owned by the timelock before
    /// the rename batch can be authored. Where one is not, the rename
    /// pre-flight refuses, and the pending ownership handover is applied on the
    /// fork so the rest of the rollout can be exercised.
    function completeOwnershipHandover(uint256 chainId, ScheduleUnderlyingNamingRenameHarness rename) internal {
        address timelock = LibTimelockInvariants.timelockForChainId(chainId);
        TokenInstance[] memory chainTokens = LibUnderlyingNamingRollout.tokens(chainId);
        bool refused = false;
        for (uint256 tokenIndex = 0; tokenIndex < chainTokens.length; tokenIndex++) {
            address owner = IOwnable(chainTokens[tokenIndex].receiptVault).owner();
            if (owner == timelock) continue;
            if (!refused) {
                vm.expectPartialRevert(ReceiptVaultOwnerMismatch.selector);
                rename.callPreflight();
                refused = true;
            }
            console2.log("PREREQUISITE: vault not owned by the timelock, handed over on the fork");
            console2.log(chainTokens[tokenIndex].receiptVault);
            vm.prank(owner);
            OwnableUpgradeable(chainTokens[tokenIndex].receiptVault).transferOwnership(timelock);
        }
    }

    /// @notice Brings the forked chain to the point where the rename can be
    /// authored: the beacon batch registered and every vault owned by the
    /// timelock.
    function prepareRename(ScheduleUnderlyingNamingRenameHarness rename) internal {
        advanceRootLineToBeaconSchedule();
        landBeaconScheduleAndHandOver(rename);
    }

    /// @notice From the line at the beacon onto: plants the implementations,
    /// lands the beacon bundle and hands every vault to the timelock.
    function landBeaconScheduleAndHandOver(ScheduleUnderlyingNamingRenameHarness rename) internal {
        plantImplementations();
        ScheduleUnderlyingNamingBeaconsHarness beacons = new ScheduleUnderlyingNamingBeaconsHarness("prepare");
        LibSafeFork.executeBundle(
            vm, Safe(payable(LibSafeInvariants.safeForChainId(block.chainid))), beacons.callAuthorBundle()
        );
        completeOwnershipHandover(block.chainid, rename);
    }

    /// @notice Runs the rollout on the fork through to the executed rename
    /// batch.
    function executeRollout(ScheduleUnderlyingNamingRenameHarness rename) internal {
        prepareRename(rename);
        LibSafeFork.executeBundle(
            vm, Safe(payable(LibSafeInvariants.safeForChainId(block.chainid))), rename.callAuthorBundle()
        );
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        ExecuteUnderlyingNaming executor = new ExecuteUnderlyingNaming();
        executor.execute();
        executor.execute();
    }
}

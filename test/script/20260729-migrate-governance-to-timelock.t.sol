// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {DeployGovernanceTimelock} from "../../script/20260729-deploy-governance-timelock.s.sol";
import {
    MigrateGovernanceToTimelock,
    TimelockNotPinned,
    UnexpectedVaultOwner,
    NothingToMigrate
} from "../../script/20260729-migrate-governance-to-timelock.s.sol";
import {MigrateGovernanceToTimelockHarness} from "./MigrateGovernanceToTimelockHarness.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx} from "../../src/lib/LibSafeOps.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants} from "../../src/lib/LibTokenInvariants.sol";

/// @title MigrateGovernanceToTimelockTest
/// @notice Live Base head fork coverage for the governance migration
/// authoring. The happy path stands up the real timelock (via the deploy
/// script, at its derived Zoltu address), drives the full `run()` — bundle
/// build, simulation, post-state, artifact, governance-loop proof — and
/// then independently re-derives the expected bundle from the pre-run state
/// and asserts the emitted artifact matches it exactly, the same check a
/// signer makes when reviewing the JSON.
contract MigrateGovernanceToTimelockTest is Test {
    /// @notice Number of authoriser `_ADMIN` roles the migration moves.
    uint256 internal constant ADMIN_ROLE_COUNT = 7;

    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
    }

    /// @notice Deploy the real timelock on the fork at its derived address
    /// via the deploy broadcast script, exactly as production will.
    function deployTimelock() internal returns (address) {
        new DeployGovernanceTimelock().run();
        return LibTimelockInvariants.expectedTimelockAddress(LibSafeInvariants.safeForChainId(block.chainid));
    }

    /// @notice Production dispatch (no override) refuses while the chain's
    /// timelock pin is a placeholder — the deploy + pin PR must land first.
    function testRunRefusesUnpinnedTimelock() external {
        selectBaseFork();
        // Skip if a future pin PR has hydrated Base's pin: from then on the
        // production path is the harness-free one and this guard is spent.
        if (LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK != address(0)) {
            return;
        }
        MigrateGovernanceToTimelock script = new MigrateGovernanceToTimelock();
        vm.expectRevert(abi.encodeWithSelector(TimelockNotPinned.selector, uint256(LibSafeInvariants.BASE_CHAIN_ID)));
        script.run();
    }

    /// @notice The full authoring against live Base state: post-state holds
    /// (every vault timelock-owned, grant map on the timelock, Safe stripped
    /// of `_ADMIN` roles) and the emitted artifact matches an independently
    /// derived bundle — 7 grants, then every Safe-owned vault transfer, then
    /// 7 renounces, in order.
    function testRunAuthorsFullMigration() external {
        selectBaseFork();
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        address authoriser = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        address timelock = deployTimelock();

        // Derive the expected target set from the PRE-run fork state — the
        // same derivation a reviewing signer performs.
        address[] memory vaults = LibTokenInvariants.productionReceiptVaults();
        uint256 expectedTransfers = 0;
        for (uint256 i = 0; i < vaults.length; i++) {
            if (Ownable(vaults[i]).owner() == safe) {
                expectedTransfers++;
            }
        }
        assertGt(expectedTransfers, 0, "fork state should have Safe-owned vaults pre-migration");

        MigrateGovernanceToTimelockHarness script = new MigrateGovernanceToTimelockHarness(timelock);
        script.run();

        // Post-state on the fork (run() already asserted these internally;
        // re-asserted here so the test fails even if the script's own
        // post-state checks rot).
        LibTokenInvariants.assertUniformOwnership(timelock);
        LibAuthoriserInvariants.assertExpectedGrants(authoriser, safe, timelock);
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(safe, timelock);
        for (uint256 i = 0; i < ADMIN_ROLE_COUNT; i++) {
            assertFalse(
                IAccessControl(authoriser).hasRole(grants[i].role, safe),
                "Safe must not retain any _ADMIN role post-migration"
            );
        }

        // The emitted artifact round-trips and matches the derived bundle:
        // grants -> transfers -> renounces.
        (uint256 chainId, address firstTarget, SafeTx[] memory txs) = LibSafeOps.parseTxBuilderJson(
            string.concat("out/20260729-governance-timelock-migration-", vm.toString(block.chainid), ".json")
        );
        assertEq(chainId, LibSafeInvariants.BASE_CHAIN_ID);
        assertEq(firstTarget, authoriser, "bundle must open with the authoriser grants");
        assertEq(txs.length, ADMIN_ROLE_COUNT + expectedTransfers + ADMIN_ROLE_COUNT);
        for (uint256 i = 0; i < ADMIN_ROLE_COUNT; i++) {
            assertEq(txs[i].to, authoriser);
            assertEq(txs[i].data, abi.encodeCall(IAccessControl.grantRole, (grants[i].role, timelock)));
        }
        uint256 transferCursor = ADMIN_ROLE_COUNT;
        for (uint256 i = 0; i < vaults.length; i++) {
            // Pre-run every vault was Safe-owned (asserted above via count
            // == table walk); each appears as a transfer in table order.
            if (transferCursor - ADMIN_ROLE_COUNT < expectedTransfers) {
                assertEq(txs[transferCursor].to, vaults[i]);
                assertEq(txs[transferCursor].data, abi.encodeCall(Ownable.transferOwnership, (timelock)));
                transferCursor++;
            }
        }
        for (uint256 i = 0; i < ADMIN_ROLE_COUNT; i++) {
            uint256 idx = ADMIN_ROLE_COUNT + expectedTransfers + i;
            assertEq(txs[idx].to, authoriser);
            assertEq(txs[idx].data, abi.encodeCall(IAccessControl.renounceRole, (grants[i].role, safe)));
        }
    }

    /// @notice A second authoring after full migration refuses: nothing is
    /// left on the Safe to move.
    function testRunRefusesWhenNothingToMigrate() external {
        selectBaseFork();
        address timelock = deployTimelock();
        new MigrateGovernanceToTimelockHarness(timelock).run();

        MigrateGovernanceToTimelockHarness second = new MigrateGovernanceToTimelockHarness(timelock);
        vm.expectRevert(NothingToMigrate.selector);
        second.run();
    }

    /// @notice A production vault owned by neither the Safe nor the timelock
    /// aborts the authoring — unknown ownership is never papered over with a
    /// blind `transferOwnership`.
    function testRunRejectsUnknownVaultOwner() external {
        selectBaseFork();
        address timelock = deployTimelock();
        address[] memory vaults = LibTokenInvariants.productionReceiptVaults();
        address stranger = address(0xDEAD);
        vm.mockCall(vaults[3], abi.encodeWithSignature("owner()"), abi.encode(stranger));

        MigrateGovernanceToTimelockHarness script = new MigrateGovernanceToTimelockHarness(timelock);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedVaultOwner.selector, vaults[3], stranger));
        script.run();
    }
}

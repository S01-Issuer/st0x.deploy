// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {DeployGovernanceTimelockHarness} from "./DeployGovernanceTimelockHarness.sol";
import {
    MigrateGovernanceToTimelock,
    TimelockNotPinned,
    UnexpectedVaultOwner,
    UnexpectedBeaconOwner,
    NothingToMigrate
} from "../../script/20260729-migrate-governance-to-timelock.s.sol";
import {MigrateGovernanceToTimelockHarness} from "./MigrateGovernanceToTimelockHarness.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibSafeOps, SafeTx} from "../../src/lib/LibSafeOps.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../../src/lib/LibTokenInvariants.sol";

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

    /// @notice The active fork's production authoriser clone, so the
    /// post-state and artifact assertions run against whichever chain the
    /// test selected rather than assuming Base.
    function _activeChainAuthoriser() internal view returns (address) {
        if (block.chainid == LibSafeInvariants.BASE_CHAIN_ID) {
            return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        }
        if (block.chainid == LibSafeInvariants.ETHEREUM_CHAIN_ID) {
            return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM;
        }
        if (block.chainid == LibSafeInvariants.HYPEREVM_CHAIN_ID) {
            return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM;
        }
        revert("unsupported chain in migration test");
    }

    /// @notice The active fork's production token table.
    function _activeChainTokens() internal view returns (TokenInstance[] memory) {
        if (block.chainid == LibSafeInvariants.BASE_CHAIN_ID) {
            return LibTokenInvariants.productionTokensBase();
        }
        if (block.chainid == LibSafeInvariants.ETHEREUM_CHAIN_ID) {
            return LibTokenInvariants.productionTokensEthereum();
        }
        if (block.chainid == LibSafeInvariants.HYPEREVM_CHAIN_ID) {
            return LibTokenInvariants.productionTokensHyperEvm();
        }
        revert("unsupported chain in migration test");
    }

    /// @notice The active fork's production receipt vaults, in table order.
    function _activeChainVaults() internal view returns (address[] memory vaults) {
        TokenInstance[] memory tokens = _activeChainTokens();
        vaults = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            vaults[i] = tokens[i].receiptVault;
        }
    }

    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
    }

    /// @notice Deploy the real timelock on the fork at its derived address
    /// via the deploy broadcast script, exactly as production will.
    function deployTimelock() internal returns (address) {
        // Deploy ONLY on the fork this test selected. The script's `run()`
        // iterates every network and leaves the last one selected, which would
        // silently move these assertions onto another chain.
        new DeployGovernanceTimelockHarness().callDeployOnActiveChain();
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
    /// (every vault AND every in-use beacon timelock-owned, grant map on the
    /// timelock, Safe stripped of `_ADMIN` roles) and the emitted artifact
    /// matches an independently derived bundle — 7 grants, then every
    /// Safe-owned vault transfer, then every Safe-owned beacon transfer,
    /// then 7 renounces, in order.
    function testRunAuthorsFullMigration() external {
        selectBaseFork();
        _assertAuthorsFullMigration(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
    }

    /// @notice The same full authoring against live HyperEVM state. HyperEVM
    /// carries 29 production tokens behind the same Safe / authoriser /
    /// beacon shape, so the chain-generic script must author there on
    /// identical terms — this is the assertion that proves HyperEVM is
    /// actually covered rather than merely reachable through the chain map.
    /// @dev Soft-skips while `HYPEREVM_RPC_URL` is unprovisioned in CI
    /// (RAI-1511); run locally with the RPC set before executing the
    /// HyperEVM bundle, since CI cannot prove this leg yet.
    function testRunAuthorsFullMigrationOnHyperevm() external {
        if (bytes(vm.envOr("HYPEREVM_RPC_URL", string(""))).length == 0) {
            emit log("PENDING: HYPEREVM_RPC_URL not available in this environment (RAI-1511)");
            return;
        }
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        _assertAuthorsFullMigration(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_HYPEREVM);
    }

    /// @notice Drive the full authoring on whichever fork is selected and
    /// assert both the post-state and that the emitted artifact matches an
    /// independently derived bundle. Shared so every chain is proven by the
    /// same assertions rather than a per-chain copy that could drift.
    /// @param safe The active chain's token-owner Safe.
    function _assertAuthorsFullMigration(address safe) internal {
        address timelock = deployTimelock();

        // Derive the expected target set from the PRE-run fork state — the
        // same derivation a reviewing signer performs.
        uint256 expectedTransfers = _safeOwnedVaultCount(safe);
        assertGt(expectedTransfers, 0, "fork state should have Safe-owned vaults pre-migration");
        uint256 expectedBeaconTransfers = _safeOwnedBeaconCount(safe);
        assertGt(expectedBeaconTransfers, 0, "fork state should have Safe-owned beacons pre-migration");
        address[3] memory implsBefore = _beaconImplementations();

        new MigrateGovernanceToTimelockHarness(timelock).run();

        _assertPostState(safe, timelock, implsBefore);
        _assertArtifactMatchesDerivedBundle(safe, timelock, expectedTransfers, expectedBeaconTransfers);
    }

    /// @notice Count the production receipt vaults still owned by `safe` on
    /// the active fork.
    /// @param safe The chain's token-owner Safe.
    /// @return count The Safe-owned vault count.
    function _safeOwnedVaultCount(address safe) internal view returns (uint256 count) {
        address[] memory vaults = _activeChainVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            if (Ownable(vaults[i]).owner() == safe) {
                count++;
            }
        }
    }

    /// @notice Count the in-use production beacons still owned by `safe` on
    /// the active fork.
    /// @param safe The chain's token-owner Safe.
    /// @return count The Safe-owned beacon count.
    function _safeOwnedBeaconCount(address safe) internal view returns (uint256 count) {
        address[3] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        for (uint256 i = 0; i < beacons.length; i++) {
            if (Ownable(beacons[i]).owner() == safe) {
                count++;
            }
        }
    }

    /// @notice The implementation each in-use beacon currently serves, in
    /// `prodBeaconsForChainId` order.
    /// @return impls The three current implementations.
    function _beaconImplementations() internal view returns (address[3] memory impls) {
        address[3] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        for (uint256 i = 0; i < beacons.length; i++) {
            impls[i] = IBeacon(beacons[i]).implementation();
        }
    }

    /// @notice Re-assert the migration post-state independently of the
    /// script's own internal checks, so this test fails even if those rot:
    /// every vault and beacon timelock-owned, beacon implementations
    /// untouched, grant map on the timelock, no `_ADMIN` copy left on the
    /// Safe.
    /// @dev Split from the test body because `via_ir` is off for this repo
    /// and the combined frame exceeds the legacy codegen's stack limit.
    /// @param safe The chain's token-owner Safe.
    /// @param timelock The chain's governance timelock.
    /// @param implsBefore Beacon implementations captured pre-run.
    function _assertPostState(address safe, address timelock, address[3] memory implsBefore) internal view {
        address authoriser = _activeChainAuthoriser();

        LibTokenInvariants.assertUniformOwnership(_activeChainTokens(), timelock);
        LibBeaconInvariants.assertProdBeaconsOwnedBy(block.chainid, timelock);

        address[3] memory implsAfter = _beaconImplementations();
        for (uint256 i = 0; i < implsAfter.length; i++) {
            assertEq(
                implsAfter[i],
                implsBefore[i],
                "migration must move beacon ownership without changing what the beacon serves"
            );
        }

        LibAuthoriserInvariants.assertExpectedGrants(authoriser, safe, timelock);
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(safe, timelock);
        for (uint256 i = 0; i < ADMIN_ROLE_COUNT; i++) {
            assertFalse(
                IAccessControl(authoriser).hasRole(grants[i].role, safe),
                "Safe must not retain any _ADMIN role post-migration"
            );
        }
    }

    /// @notice Parse the emitted Tx Builder JSON and assert it matches the
    /// bundle derived independently from the pre-run state: 7 grants, then
    /// the vault transfers in table order, then the beacon transfers in
    /// `prodBeaconsForChainId` order, then 7 renounces.
    /// @param safe The chain's token-owner Safe.
    /// @param timelock The chain's governance timelock.
    /// @param expectedTransfers The pre-run Safe-owned vault count.
    /// @param expectedBeaconTransfers The pre-run Safe-owned beacon count.
    function _assertArtifactMatchesDerivedBundle(
        address safe,
        address timelock,
        uint256 expectedTransfers,
        uint256 expectedBeaconTransfers
    ) internal {
        address authoriser = _activeChainAuthoriser();
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(safe, timelock);

        (uint256 chainId, address firstTarget, SafeTx[] memory txs) = LibSafeOps.parseTxBuilderJson(
            string.concat("out/20260729-governance-timelock-migration-", vm.toString(block.chainid), ".json")
        );
        assertEq(chainId, block.chainid, "artifact must be authored for the active chain");
        assertEq(firstTarget, authoriser, "bundle must open with the authoriser grants");
        assertEq(txs.length, ADMIN_ROLE_COUNT + expectedTransfers + expectedBeaconTransfers + ADMIN_ROLE_COUNT);

        for (uint256 i = 0; i < ADMIN_ROLE_COUNT; i++) {
            assertEq(txs[i].to, authoriser);
            assertEq(txs[i].data, abi.encodeCall(IAccessControl.grantRole, (grants[i].role, timelock)));
        }

        address[] memory vaults = _activeChainVaults();
        for (uint256 i = 0; i < expectedTransfers; i++) {
            // Pre-run every vault was Safe-owned (asserted via the count),
            // so each appears as a transfer in table order.
            assertEq(txs[ADMIN_ROLE_COUNT + i].to, vaults[i]);
            assertEq(txs[ADMIN_ROLE_COUNT + i].data, abi.encodeCall(Ownable.transferOwnership, (timelock)));
        }

        // Beacon transfers follow the vaults — the leg that closes the
        // upgrade-path bypass.
        address[3] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        for (uint256 i = 0; i < expectedBeaconTransfers; i++) {
            uint256 idx = ADMIN_ROLE_COUNT + expectedTransfers + i;
            assertEq(txs[idx].to, beacons[i]);
            assertEq(txs[idx].data, abi.encodeCall(Ownable.transferOwnership, (timelock)));
        }

        for (uint256 i = 0; i < ADMIN_ROLE_COUNT; i++) {
            uint256 idx = ADMIN_ROLE_COUNT + expectedTransfers + expectedBeaconTransfers + i;
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

    /// @notice A production beacon owned by neither the Safe nor the
    /// timelock aborts the authoring, on the same terms as an unknown vault
    /// owner. Beacons carry the upgrade authority for every production
    /// proxy, so an unrecognised owner must never be papered over.
    function testRunRejectsUnknownBeaconOwner() external {
        selectBaseFork();
        address timelock = deployTimelock();
        address[3] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        address stranger = address(0xDEAD);
        vm.mockCall(beacons[1], abi.encodeWithSignature("owner()"), abi.encode(stranger));

        MigrateGovernanceToTimelockHarness script = new MigrateGovernanceToTimelockHarness(timelock);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedBeaconOwner.selector, beacons[1], stranger));
        script.run();
    }
}

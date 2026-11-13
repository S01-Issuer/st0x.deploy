// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";

import {
    MigrateGovernanceToTimelock,
    UnexpectedVaultOwner,
    UnexpectedBeaconOwner,
    NothingToMigrate,
    GovernanceTimelockAlreadyApplied
} from "../../script/20260729-migrate-governance-to-timelock.s.sol";
import {MigrateGovernanceToTimelockHarness} from "./MigrateGovernanceToTimelockHarness.sol";
import {ExecuteTimelockOperations} from "../../script/20260813-execute-timelock-operations.s.sol";
import {MigrateMultisigThreshold} from "../../script/20260619-migrate-multisig-threshold.s.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";
import {LibTestTamperedArtifact} from "../lib/LibTestTamperedArtifact.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {OffchainAssetReceiptVault} from "rain-vats-0.2.20/src/abstract/OffchainAssetReceiptVault.sol";
import {IAuthorizeV1} from "rain-vats-0.2.20/src/interface/IAuthorizeV1.sol";

import {IAuthorisable} from "../../src/interface/IAuthorisable.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.30/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.30/src/lib/LibSafeTxBuilderJson.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../../src/lib/LibTokenInvariants.sol";

/// @title MigrateGovernanceToTimelockTest
/// @notice Fork coverage for the governance migration authoring, at each
/// chain's pinned pre-backfill block.
/// The migration has executed on every chain, so each fork is first rewound
/// to the pre-migration state with the timelock's own powers
/// (`rewindMigration`): the script stays re-dispatchable for audit, and its
/// authoring path stays proven against real production contracts. The happy path runs against the chain's pinned live
/// timelock, drives the full `run()` — bundle
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
        if (block.chainid == LibSafeInvariants.ROBINHOOD_CHAIN_ID) {
            return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ROBINHOOD;
        }
        if (block.chainid == LibSafeInvariants.BSC_CHAIN_ID) {
            return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_BSC;
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
        if (block.chainid == LibSafeInvariants.ROBINHOOD_CHAIN_ID) {
            return LibTokenInvariants.productionTokensRobinhood();
        }
        if (block.chainid == LibSafeInvariants.BSC_CHAIN_ID) {
            return LibTokenInvariants.productionTokensBsc();
        }
        if (block.chainid == LibSafeInvariants.ZEROG_CHAIN_ID) {
            return LibTokenInvariants.productionTokensZerog();
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
        selectRewoundFork(LibRainDeploy.BASE);
    }

    /// @notice Fork `network` at its pinned pre-backfill block, where the
    /// migration is not yet recorded, and rewind the executed migration.
    function selectRewoundFork(string memory network) internal {
        LibTestPreBackfillFork.select(vm, network);
        rewindMigration();
    }

    /// @notice Put the active fork back in the pre-migration state: every
    /// production vault and in-use beacon the timelock owns goes back to the
    /// Safe, and the seven authoriser `_ADMIN` roles move from the timelock
    /// back to the Safe. Uses only powers the timelock holds, so the rewound
    /// state is one the real contracts admit.
    function rewindMigration() internal {
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        IAccessControl authoriser = IAccessControl(_activeChainAuthoriser());

        vm.startPrank(timelock);
        TokenInstance[] memory tokens = _activeChainTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            if (Ownable(tokens[i].receiptVault).owner() == timelock) {
                Ownable(tokens[i].receiptVault).transferOwnership(safe);
            }
        }
        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        for (uint256 i = 0; i < beacons.length; i++) {
            if (Ownable(beacons[i]).owner() == timelock) {
                Ownable(beacons[i]).transferOwnership(safe);
            }
        }
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(safe, timelock);
        for (uint256 i = 0; i < ADMIN_ROLE_COUNT; i++) {
            authoriser.grantRole(grants[i].role, safe);
            authoriser.renounceRole(grants[i].role, timelock);
        }
        vm.stopPrank();
    }

    /// @notice The active fork's pinned timelock, live at its derived address and in its pinned state.
    function pinnedTimelock() internal view returns (address) {
        address safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        assertEq(
            timelock, LibTimelockInvariants.expectedTimelockAddress(safe), onChain("pin must be the derived timelock")
        );
        assertGt(timelock.code.length, 0, onChain("pinned timelock must be live"));
        LibTimelockInvariants.assertTimelockState(timelock, safe);
        return timelock;
    }

    /// @notice The full authoring against each deployment network's live
    /// state: post-state holds (every vault AND every in-use beacon
    /// timelock-owned, grant map on the timelock, Safe stripped of `_ADMIN`
    /// roles) and the emitted artifact matches an independently derived
    /// bundle — 7 grants, then every Safe-owned vault transfer, then every
    /// Safe-owned beacon transfer, then 7 renounces, in order.
    function testRunAuthorsFullMigrationOnEveryDeploymentNetwork() external {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            selectRewoundFork(networks[i]);
            _assertAuthorsFullMigration(LibSafeInvariants.safeForChainId(block.chainid));
        }
    }

    function onChain(string memory message) internal view returns (string memory) {
        return string.concat(vm.toString(block.chainid), ": ", message);
    }

    /// @notice Drive the full authoring on whichever fork is selected and
    /// assert both the post-state and that the emitted artifact matches an
    /// independently derived bundle. Shared so every chain is proven by the
    /// same assertions rather than a per-chain copy that could drift.
    /// @param safe The active chain's token-owner Safe.
    function _assertAuthorsFullMigration(address safe) internal {
        address timelock = pinnedTimelock();

        // Derive the expected target set from the PRE-run fork state — the
        // same derivation a reviewing signer performs.
        address[] memory vaultTargets = _safeOwnedVaults(safe);
        assertGt(vaultTargets.length, 0, onChain("fork state should have Safe-owned vaults pre-migration"));
        address[] memory beaconTargets = _safeOwnedBeacons(safe);
        assertGt(beaconTargets.length, 0, onChain("fork state should have Safe-owned beacons pre-migration"));
        address[4] memory implsBefore = _beaconImplementations();

        new MigrateGovernanceToTimelockHarness(timelock).run();

        _assertPostState(safe, timelock, implsBefore);
        _assertArtifactMatchesDerivedBundle(safe, timelock, vaultTargets, beaconTargets);
    }

    /// @notice The production receipt vaults still owned by `safe` on the
    /// active fork, in table order — the same subset, in the same order,
    /// that the script's selection rule emits as transfers. Captured as
    /// addresses (not a count) BEFORE the run, so the artifact assertion
    /// tracks the selection even on a fork where part of the table is
    /// already timelock-owned.
    /// @param safe The chain's token-owner Safe.
    /// @return targets The Safe-owned vaults, in table order.
    function _safeOwnedVaults(address safe) internal view returns (address[] memory targets) {
        address[] memory vaults = _activeChainVaults();
        address[] memory candidates = new address[](vaults.length);
        uint256 count = 0;
        for (uint256 i = 0; i < vaults.length; i++) {
            if (Ownable(vaults[i]).owner() == safe) {
                candidates[count] = vaults[i];
                count++;
            }
        }
        targets = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            targets[i] = candidates[i];
        }
    }

    /// @notice The in-use production beacons still owned by `safe` on the
    /// active fork, in `prodBeaconsForChainId` order — the beacon half of
    /// the pre-run selection capture, on the same terms as
    /// `_safeOwnedVaults`.
    /// @param safe The chain's token-owner Safe.
    /// @return targets The Safe-owned beacons, in pinned order.
    function _safeOwnedBeacons(address safe) internal view returns (address[] memory targets) {
        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        address[] memory candidates = new address[](beacons.length);
        uint256 count = 0;
        for (uint256 i = 0; i < beacons.length; i++) {
            if (Ownable(beacons[i]).owner() == safe) {
                candidates[count] = beacons[i];
                count++;
            }
        }
        targets = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            targets[i] = candidates[i];
        }
    }

    /// @notice The implementation each in-use beacon currently serves, in
    /// `prodBeaconsForChainId` order.
    /// @return impls The three current implementations.
    function _beaconImplementations() internal view returns (address[4] memory impls) {
        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
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
    function _assertPostState(address safe, address timelock, address[4] memory implsBefore) internal view {
        address authoriser = _activeChainAuthoriser();

        LibTokenInvariants.assertUniformOwnership(_activeChainTokens(), timelock);
        LibBeaconInvariants.assertProdBeaconsOwnedBy(block.chainid, timelock);

        address[4] memory implsAfter = _beaconImplementations();
        for (uint256 i = 0; i < implsAfter.length; i++) {
            assertEq(
                implsAfter[i],
                implsBefore[i],
                onChain("migration must move beacon ownership without changing what the beacon serves")
            );
        }

        LibAuthoriserInvariants.assertExpectedGrants(authoriser, safe, timelock);
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(safe, timelock);
        for (uint256 i = 0; i < ADMIN_ROLE_COUNT; i++) {
            assertFalse(
                IAccessControl(authoriser).hasRole(grants[i].role, safe),
                onChain("Safe must not retain any _ADMIN role post-migration")
            );
        }
    }

    /// @notice Parse the emitted Tx Builder JSON and assert it matches the
    /// bundle derived independently from the pre-run state: 7 grants, then
    /// the captured Safe-owned vault selection in table order, then the
    /// captured Safe-owned beacon selection in `prodBeaconsForChainId`
    /// order, then 7 renounces. The selections are the pre-run captures —
    /// the script skips surfaces already timelock-owned, so asserting
    /// against the captured subset (not a table prefix) tracks its
    /// selection rule on any fork state.
    /// @param safe The chain's token-owner Safe.
    /// @param timelock The chain's governance timelock.
    /// @param vaultTargets The pre-run Safe-owned vaults, in table order.
    /// @param beaconTargets The pre-run Safe-owned beacons, in pinned order.
    function _assertArtifactMatchesDerivedBundle(
        address safe,
        address timelock,
        address[] memory vaultTargets,
        address[] memory beaconTargets
    ) internal view {
        address authoriser = _activeChainAuthoriser();
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(safe, timelock);
        bytes memory transfer = abi.encodeCall(Ownable.transferOwnership, (timelock));

        (uint256 chainId, address artifactSafe, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(
            vm,
            vm.readFile(
                string.concat("out/20260729-governance-timelock-migration-", vm.toString(block.chainid), ".json")
            )
        );
        assertEq(chainId, block.chainid, onChain("artifact must be authored for the active chain"));
        assertEq(artifactSafe, safe, onChain("artifact must be authored for the chain's Safe"));
        assertEq(txs[0].to, authoriser, onChain("bundle must open with the authoriser grants"));
        assertEq(
            txs.length,
            ADMIN_ROLE_COUNT + vaultTargets.length + beaconTargets.length + ADMIN_ROLE_COUNT,
            onChain("bundle length")
        );

        for (uint256 i = 0; i < ADMIN_ROLE_COUNT; i++) {
            assertEq(txs[i].to, authoriser, onChain("grant target"));
            assertEq(
                txs[i].data,
                abi.encodeCall(IAccessControl.grantRole, (grants[i].role, timelock)),
                onChain("grant calldata")
            );
        }

        for (uint256 i = 0; i < vaultTargets.length; i++) {
            assertEq(txs[ADMIN_ROLE_COUNT + i].to, vaultTargets[i], onChain("vault transfer target"));
            assertEq(txs[ADMIN_ROLE_COUNT + i].data, transfer, onChain("vault transfer calldata"));
        }

        // Beacon transfers follow the vaults — the leg that closes the
        // upgrade-path bypass.
        for (uint256 i = 0; i < beaconTargets.length; i++) {
            uint256 idx = ADMIN_ROLE_COUNT + vaultTargets.length + i;
            assertEq(txs[idx].to, beaconTargets[i], onChain("beacon transfer target"));
            assertEq(txs[idx].data, transfer, onChain("beacon transfer calldata"));
        }

        for (uint256 i = 0; i < ADMIN_ROLE_COUNT; i++) {
            uint256 idx = ADMIN_ROLE_COUNT + vaultTargets.length + beaconTargets.length + i;
            assertEq(txs[idx].to, authoriser, onChain("renounce target"));
            assertEq(
                txs[idx].data,
                abi.encodeCall(IAccessControl.renounceRole, (grants[i].role, safe)),
                onChain("renounce calldata")
            );
        }
    }

    /// @notice A second authoring after full migration refuses: nothing is
    /// left on the Safe to move.
    function testRunRefusesWhenNothingToMigrate() external {
        selectBaseFork();
        address timelock = pinnedTimelock();
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
        address timelock = pinnedTimelock();
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
        address timelock = pinnedTimelock();
        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        address stranger = address(0xDEAD);
        vm.mockCall(beacons[1], abi.encodeWithSignature("owner()"), abi.encode(stranger));

        MigrateGovernanceToTimelockHarness script = new MigrateGovernanceToTimelockHarness(timelock);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedBeaconOwner.selector, beacons[1], stranger));
        script.run();
    }

    /// @notice The timelock is not a one-way door: every surface class the
    /// migration hands to it can be handed onward to a successor governance
    /// principal through the same schedule -> 48h -> execute loop, each leg
    /// driven through the Safe's threshold-gated `execTransaction` (the n+1
    /// walk, so undersigned attempts are proven rejected). Walks a vault
    /// ownership transfer, a beacon ownership transfer, an authoriser
    /// `_ADMIN` handover (grant to successor, then the timelock renounces
    /// its own copy), and a role change on the timelock itself (successor
    /// granted proposer through self-administration).
    function testGovernanceCanMigrateAwayToSuccessor() external {
        selectBaseFork();
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        address authoriser = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        address timelock = pinnedTimelock();
        new MigrateGovernanceToTimelockHarness(timelock).run();

        address successor = address(0x5000000000000000000000000000000000000001);
        address vault = _activeChainVaults()[0];
        address beacon = LibBeaconInvariants.prodBeaconsForChainId(block.chainid)[0];
        bytes32 adminRole = LibAuthoriserInvariants.expectedGrants(safe, timelock)[0].role;

        scheduleAndExecuteViaTimelock(safe, timelock, vault, abi.encodeCall(Ownable.transferOwnership, (successor)));
        scheduleAndExecuteViaTimelock(safe, timelock, beacon, abi.encodeCall(Ownable.transferOwnership, (successor)));
        scheduleAndExecuteViaTimelock(
            safe, timelock, authoriser, abi.encodeCall(IAccessControl.grantRole, (adminRole, successor))
        );
        scheduleAndExecuteViaTimelock(
            safe, timelock, authoriser, abi.encodeCall(IAccessControl.renounceRole, (adminRole, timelock))
        );
        scheduleAndExecuteViaTimelock(
            safe,
            timelock,
            timelock,
            abi.encodeCall(IAccessControl.grantRole, (LibTimelockInvariants.TIMELOCK_PROPOSER_ROLE, successor))
        );

        assertEq(Ownable(vault).owner(), successor, "vault ownership must be transferable onward");
        assertEq(Ownable(beacon).owner(), successor, "beacon ownership must be transferable onward");
        assertTrue(
            IAccessControl(authoriser).hasRole(adminRole, successor), "successor must hold the handed-over _ADMIN"
        );
        assertFalse(
            IAccessControl(authoriser).hasRole(adminRole, timelock), "timelock must be able to renounce its _ADMIN"
        );
        assertTrue(
            IAccessControl(timelock).hasRole(LibTimelockInvariants.TIMELOCK_PROPOSER_ROLE, successor),
            "self-administration must provision a successor proposer"
        );
    }

    /// @notice A beacon UPGRADE runs through the timelock: post-migration
    /// the only path to `upgradeTo` is schedule -> 48h -> execute through
    /// the Safe's threshold gate, proven literally with an idempotent
    /// `upgradeTo(currentImpl)` — the operation completes, the beacon still
    /// serves the same implementation, and no faster path exists (a direct
    /// Safe call must revert: the Safe no longer owns the beacon).
    function testBeaconUpgradeRunsThroughTimelock() external {
        selectBaseFork();
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        address timelock = pinnedTimelock();
        new MigrateGovernanceToTimelockHarness(timelock).run();

        address beacon = LibBeaconInvariants.prodBeaconsForChainId(block.chainid)[0];
        address impl = IBeacon(beacon).implementation();

        // The instant path is closed: the Safe is not the owner any more.
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, safe));
        vm.prank(safe);
        UpgradeableBeacon(beacon).upgradeTo(impl);

        // The sanctioned path works end-to-end.
        scheduleAndExecuteViaTimelock(safe, timelock, beacon, abi.encodeWithSignature("upgradeTo(address)", impl));
        assertEq(IBeacon(beacon).implementation(), impl, "idempotent upgrade must leave the implementation in place");
    }

    /// @notice `setAuthorizer` — the vault surface that rewires which
    /// contract gates every deposit, withdrawal and transfer — runs through
    /// the timelock, and only through it: post-migration a direct Safe call
    /// reverts `OwnableUnauthorizedAccount`, and the sanctioned schedule ->
    /// 48h -> execute path (each leg n+1 threshold-gated) completes, proven
    /// with an idempotent re-set of the current authoriser so the wiring is
    /// asserted unchanged.
    function testSetAuthorizerRunsThroughTimelock() external {
        selectBaseFork();
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        address authoriser = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        address timelock = pinnedTimelock();
        new MigrateGovernanceToTimelockHarness(timelock).run();

        address vault = _activeChainVaults()[0];

        // The instant path is closed: the Safe no longer owns the vault.
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, safe));
        vm.prank(safe);
        OffchainAssetReceiptVault(payable(vault)).setAuthorizer(IAuthorizeV1(authoriser));

        // The sanctioned path works end-to-end and leaves the wiring intact.
        scheduleAndExecuteViaTimelock(
            safe, timelock, vault, abi.encodeCall(OffchainAssetReceiptVault.setAuthorizer, (IAuthorizeV1(authoriser)))
        );
        assertEq(IAuthorisable(vault).authorizer(), authoriser, "idempotent re-set must leave the authoriser in place");
    }

    /// @notice The signer-side `verify(string)` accepts a freshly authored
    /// artifact against a fresh fork of the same live state, and rejects a
    /// tampered copy with the exact mismatching field. Authoring simulates
    /// the migration onto its own fork, so verification runs on a NEW fork
    /// — exactly the signer's vantage point: artifact in hand, live chain
    /// untouched.
    function testVerifyAcceptsAuthoredArtifactAndRejectsTamper() external {
        selectBaseFork();
        address timelock = pinnedTimelock();
        new MigrateGovernanceToTimelockHarness(timelock).run();
        string memory json = vm.readFile(
            string.concat("out/20260729-governance-timelock-migration-", vm.toString(block.chainid), ".json")
        );

        // Fresh fork: authoring mutated the previous fork's state; the live
        // chain a signer verifies against is untouched.
        selectBaseFork();
        assertEq(pinnedTimelock(), timelock, "derived timelock must be stable across forks");
        (,, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, json);
        txs[0].data = abi.encodeCall(IAccessControl.grantRole, (bytes32(uint256(1)), address(0xBAD)));
        string memory tampered =
            LibSafeTxBuilderJson.toJson(vm, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE, block.chainid, "tampered", txs);
        LibTestTamperedArtifact.assertVerifyRefusesTamper(
            vm,
            address(new MigrateGovernanceToTimelockHarness(timelock)),
            json,
            tampered,
            "20260729-governance-timelock"
        );
    }

    /// @notice One governance-loop leg: schedule the call on the timelock
    /// through the Safe's threshold-gated exec path, prove it pending but
    /// not ready inside the window, warp out the delay, execute the same
    /// way, and prove the operation Done. Salted by the payload so
    /// consecutive legs never collide.
    function scheduleAndExecuteViaTimelock(address safe, address timelock, address target, bytes memory data) internal {
        TimelockController controller = TimelockController(payable(timelock));
        bytes32 salt = keccak256(abi.encode("migrate-away-proof", target, data));
        bytes32 id = controller.hashOperation(target, 0, data, bytes32(0), salt);

        LibSafeFork.simulateNPlus1(
            vm,
            Safe(payable(safe)),
            timelock,
            abi.encodeCall(
                TimelockController.schedule,
                (target, 0, data, bytes32(0), salt, LibTimelockInvariants.TIMELOCK_MIN_DELAY)
            )
        );
        assertTrue(controller.isOperationPending(id), "leg must be pending after schedule");
        assertFalse(controller.isOperationReady(id), "leg must not be executable inside the delay");

        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        LibSafeFork.simulateNPlus1(
            vm,
            Safe(payable(safe)),
            timelock,
            abi.encodeCall(TimelockController.execute, (target, 0, data, bytes32(0), salt))
        );
        assertTrue(controller.isOperationDone(id), "leg must complete after the delay");
    }

    function chains() internal pure returns (uint256[5] memory) {
        return [
            LibSafeInvariants.BASE_CHAIN_ID,
            LibSafeInvariants.ETHEREUM_CHAIN_ID,
            LibSafeInvariants.HYPEREVM_CHAIN_ID,
            LibSafeInvariants.ROBINHOOD_CHAIN_ID,
            LibSafeInvariants.BSC_CHAIN_ID
        ];
    }

    function testHistoryAtExecutedAtLandsOnItsPredecessorRecord(uint256 index) external {
        uint256 chainId = chains()[bound(index, 0, 4)];
        MigrateGovernanceToTimelock migration = new MigrateGovernanceToTimelock();
        ScriptDeclaration memory declared = migration.declaration(chainId);
        uint256 executedAt = migration.executedAt(chainId);
        uint256 predecessorAt = chainId == LibSafeInvariants.BASE_CHAIN_ID
            ? new ExecuteTimelockOperations().executedAt(chainId)
            : new MigrateMultisigThreshold().executedAt(chainId);
        address writer = LibSafeInvariants.safeForChainId(chainId);
        LibTestRootLine.etchRegistry(vm);
        LibTestRootLine.approve(vm, writer);

        vm.warp(predecessorAt);
        LibTestRootLine.write(vm, writer, declared.onto, MIGRATION_HEAD_GENESIS);
        vm.warp(executedAt + 1 days);

        (address to, bytes memory data) = LibStoxMigrations.historyCall(declared, executedAt);
        vm.prank(writer);
        (bool ok,) = to.call(data);
        assertTrue(ok);

        assertEq(LibStoxMigrations.applied(LibStoxMigrations.GOVERNANCE_TIMELOCK), executedAt);
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.GOVERNANCE_TIMELOCK);
    }

    function testRunRefusesWhenAlreadyRecorded() external {
        address writer = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        LibTestRootLine.etchRegistry(vm);
        LibTestRootLine.approve(vm, writer);
        LibTestRootLine.write(vm, writer, LibStoxMigrations.GOVERNANCE_TIMELOCK, MIGRATION_HEAD_GENESIS);

        MigrateGovernanceToTimelock migration = new MigrateGovernanceToTimelock();
        vm.expectRevert(GovernanceTimelockAlreadyApplied.selector);
        migration.run();
    }
}

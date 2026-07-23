// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {
    LibBeaconInvariants,
    IOwnable,
    BeaconCodehashMismatch,
    BeaconNotDeployed,
    BeaconOwnerMismatch,
    BeaconImplementationMismatch,
    UnsupportedChainForProdBeacons
} from "../../../src/lib/LibBeaconInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibProdBeaconsBase} from "../../../src/lib/LibProdBeaconsBase.sol";
import {LibProdBeacons0_1_1} from "../../../src/lib/LibProdBeacons0_1_1.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibBeaconInvariantsHarness} from "./LibBeaconInvariantsHarness.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";

/// @title LibBeaconInvariantsTest
/// @notice Inverted fork tests that exercise each invariant in
/// `LibBeaconInvariants` by injecting drift via `vm.etch` / `vm.mockCall`
/// and asserting the matching typed error is raised. The positive
/// ("live state passes") cases live in the beacon-ownership migration's
/// happy-path test, so this file focuses on coverage of every error path.
/// @dev Uses an unpinned Base head fork (same precedent as
/// `LibSafeInvariants.t.sol`). Pinning would freeze the invariant
/// assertions against a stale snapshot and let new drift slip through
/// unnoticed.
contract LibBeaconInvariantsTest is Test {
    /// @notice External-call harness deployed fresh per test (via fork
    /// rebuild). Each test calls `selectBaseFork` before deploying the
    /// harness; the harness is recreated against the active fork.
    LibBeaconInvariantsHarness internal harness;

    /// @notice Selects the Base fork at chain head — deliberately
    /// unpinned. Live drift detector; see contract-level rationale.
    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
        harness = new LibBeaconInvariantsHarness();
    }

    /// @notice `assertBeaconInvariants` trips `BeaconCodehashMismatch` when
    /// the beacon's runtime codehash drifts from the pinned OZ
    /// `UpgradeableBeacon` bytecode. Simulated by `vm.etch`-ing a single
    /// `INVALID` opcode at the beacon address; `extcodehash` then returns the
    /// hash of `0xFE`, which differs from the pinned codehash. Uses the live
    /// receipt vault beacon as the victim.
    function testInvertedBeaconCodehashMismatch() external {
        selectBaseFork();
        address beacon = LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1;
        bytes memory mutatedCode = hex"FE";
        vm.etch(beacon, mutatedCode);
        bytes32 mutatedCodehash;
        assembly ("memory-safe") {
            mutatedCodehash := extcodehash(beacon)
        }
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconCodehashMismatch.selector,
                beacon,
                LibBeaconInvariants.UPGRADEABLE_BEACON_CODEHASH,
                mutatedCodehash
            )
        );
        harness.callAssertBeaconInvariants(
            beacon, LibProdDeployV1.BEACON_INITIAL_OWNER, LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION
        );
    }

    /// @notice `assertBeaconInvariants` trips `BeaconOwnerMismatch` when the
    /// beacon's `owner()` differs from the expected owner. Simulated by
    /// mocking `owner()` on the live receipt vault beacon to a rogue address.
    function testInvertedBeaconOwnerMismatch() external {
        selectBaseFork();
        address beacon = LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1;
        address rogueOwner = address(0xBADC0DE);
        vm.mockCall(beacon, abi.encodeWithSelector(IOwnable.owner.selector), abi.encode(rogueOwner));
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconOwnerMismatch.selector, beacon, LibProdDeployV1.BEACON_INITIAL_OWNER, rogueOwner
            )
        );
        harness.callAssertBeaconInvariants(
            beacon, LibProdDeployV1.BEACON_INITIAL_OWNER, LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION
        );
    }

    /// @notice `assertBeaconInvariants` trips `BeaconImplementationMismatch`
    /// when the beacon's `implementation()` differs from the expected
    /// implementation. Simulated by mocking `implementation()` on the live
    /// receipt vault beacon to a rogue address. The expected owner is the
    /// Safe — the live owner since the beacon-ownership migration executed
    /// (2026-07) — so the owner check passes and the revert is specifically
    /// the implementation gate.
    function testInvertedBeaconImplementationMismatch() external {
        selectBaseFork();
        address beacon = LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1;
        address rogueImpl = address(0xBADBEEF);
        vm.mockCall(beacon, abi.encodeWithSelector(IBeacon.implementation.selector), abi.encode(rogueImpl));
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconImplementationMismatch.selector,
                beacon,
                LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION,
                rogueImpl
            )
        );
        harness.callAssertBeaconInvariants(
            beacon, LibBeaconInvariants.PROD_BEACON_OWNER, LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION
        );
    }

    /// @notice Base's IN-USE beacons are the V1-generation addresses. The
    /// later 0.1.1-address beacons exist on Base but production never adopted
    /// them, so returning those would assert ownership of a deploy artifact
    /// nothing runs on while leaving the live beacons unpinned.
    function testProdBeaconsForChainIdBaseIsTheV1Generation() external {
        selectBaseFork();
        address[3] memory beacons = harness.callProdBeaconsForChainId(LibSafeInvariants.BASE_CHAIN_ID);
        assertEq(beacons[0], LibProdDeployV1.STOX_RECEIPT_BEACON_V1, "receipt beacon");
        assertEq(beacons[1], LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1, "receipt vault beacon");
        assertEq(beacons[2], LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1, "wrapped vault beacon");
    }

    /// @notice Ethereum bootstrapped at 0.1.1, so its in-use beacons are that
    /// generation — the two read live from the 0.1.1 beacon-set deployer plus
    /// the wrapped beacon's own pin. Pinned against the source lib so the
    /// chain-id dispatch cannot silently answer with Base's set.
    function testProdBeaconsForChainIdEthereumIsThe011Set() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        harness = new LibBeaconInvariantsHarness();
        address[3] memory beacons = harness.callProdBeaconsForChainId(LibSafeInvariants.ETHEREUM_CHAIN_ID);
        address[3] memory expected = LibProdBeacons0_1_1.beacons();
        assertEq(beacons[0], expected[0], "receipt beacon");
        assertEq(beacons[1], expected[1], "receipt vault beacon");
        assertEq(beacons[2], expected[2], "wrapped vault beacon");
        assertTrue(beacons[0] != LibProdDeployV1.STOX_RECEIPT_BEACON_V1, "answered with Base's set");
    }

    /// @notice A chain with no pinned in-use set reverts rather than falling
    /// back to another chain's beacons. A fallback would assert ownership of
    /// contracts that do not exist on the active chain, and `code.length == 0`
    /// would report that as a missing beacon rather than as an unsupported
    /// chain.
    function testProdBeaconsForChainIdRevertsForUnpinnedChain() external {
        selectBaseFork();
        uint256 arbitrum = 42161;
        vm.expectRevert(abi.encodeWithSelector(UnsupportedChainForProdBeacons.selector, arbitrum));
        harness.callProdBeaconsForChainId(arbitrum);
    }

    /// @notice `assertProdBeaconsOwnedByChainSafe` trips `BeaconOwnerMismatch`
    /// when an in-use beacon is held by anything other than the active chain's
    /// token-owner Safe. Whoever owns an in-use beacon can repoint every
    /// production vault proxy on the chain, so the rogue owner here stands in
    /// for the whole class of compromise this assert exists to catch.
    function testInvertedProdBeaconOwnerMismatch() external {
        selectBaseFork();
        address beacon = LibProdBeaconsBase.beacons()[1];
        address rogueOwner = address(0xBADC0DE);
        vm.mockCall(beacon, abi.encodeWithSelector(IOwnable.owner.selector), abi.encode(rogueOwner));
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconOwnerMismatch.selector,
                beacon,
                LibSafeInvariants.safeForChainId(LibSafeInvariants.BASE_CHAIN_ID),
                rogueOwner
            )
        );
        harness.callAssertProdBeaconsOwnedByChainSafe(LibSafeInvariants.BASE_CHAIN_ID);
    }

    /// @notice An in-use beacon with no code trips `BeaconNotDeployed` rather
    /// than reaching `owner()`. A staticcall to a codeless address succeeds
    /// returning nothing, so without this guard the failure would surface as a
    /// decode revert that names neither the beacon nor the reason.
    function testInvertedProdBeaconNotDeployed() external {
        selectBaseFork();
        address beacon = LibProdBeaconsBase.beacons()[0];
        vm.etch(beacon, "");
        vm.expectRevert(abi.encodeWithSelector(BeaconNotDeployed.selector, beacon));
        harness.callAssertProdBeaconsOwnedByChainSafe(LibSafeInvariants.BASE_CHAIN_ID);
    }
}

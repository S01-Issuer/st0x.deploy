// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {
    LibBeaconInvariants,
    IOwnable,
    BeaconCodehashMismatch,
    BeaconOwnerMismatch,
    BeaconImplementationMismatch
} from "../../../src/lib/LibBeaconInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
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
    /// receipt vault beacon to a rogue address.
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
            beacon, LibProdDeployV1.BEACON_INITIAL_OWNER, LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION
        );
    }
}

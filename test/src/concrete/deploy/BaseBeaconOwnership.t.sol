// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {LibBeaconInvariants} from "../../../../src/lib/LibBeaconInvariants.sol";
import {LibProdBeaconsBase} from "../../../../src/lib/LibProdBeaconsBase.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";

/// @title BaseBeaconOwnershipTest
/// @notice Base's leg of the per-chain beacon pin, completing the set
/// alongside `Ethereum`/`HyperEvm`/`Robinhood`/`BscBeaconOwnershipTest`.
/// Base was the one production chain with no `assertBeaconInvariants` caller:
/// `StoxProdV4Test.testProdDeployBaseV4` asserts Base's in-use beacons are
/// Safe-owned (via `assertProdBeaconsOwnedByChainSafe`) but says nothing about
/// where they POINT, and the 0.1.1-address beacons it does check the
/// implementations of are an unadopted Base deploy artifact. So the beacons
/// production tokens on Base actually run on had their implementation
/// unasserted on this chain, while every other chain pinned theirs.
/// @dev Unpinned Base head fork, matching the other per-chain files: the
/// point is drift detection against live state, which a pinned block would
/// freeze.
contract BaseBeaconOwnershipTest is Test {
    /// @notice Base's three in-use token beacons carry the OZ
    /// `UpgradeableBeacon` codehash, are owned by Base's token-owner Safe,
    /// and point at the implementations this repo pins.
    ///
    /// Base runs on the V1-generation beacon ADDRESSES (deployed at V1 and
    /// retained through every upgrade since) but on the SAME implementations
    /// as every other chain: the wrapped-token-vault beacon still serves the
    /// 0.1.1 impl, and the receipt + receipt-vault beacons were moved onto
    /// 0.1.30 by the fleet upgrade (20260825-upgrade-fleet-to-0-1-30). Each
    /// expectation is an explicit pin rather than a read-back of the beacon's
    /// own `implementation()`, so an unreviewed `upgradeTo` fails here.
    ///
    /// The orchestrator beacon is deliberately out of scope: its owner is
    /// asserted by `assertProdBeaconsOwnedByChainSafe` and its build is a
    /// different codehash generation, covered by `LibOrchestratorInvariants`.
    function testBaseBeaconsAreSafeOwnedAtTheirPinnedImpls() external {
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;

        vm.createSelectFork(LibRainDeploy.BASE);
        address[4] memory beacons = LibProdBeaconsBase.beacons();
        address[4] memory impls = LibProdBeaconsBase.implementations();
        LibBeaconInvariants.assertBeaconInvariants(
            beacons[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX],
            safe,
            impls[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX]
        );
        LibBeaconInvariants.assertBeaconInvariants(
            beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX], safe, LibProdDeployV4.STOX_RECEIPT_0_1_30
        );
        LibBeaconInvariants.assertBeaconInvariants(
            beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX], safe, LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30
        );
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibProdBeacons0_1_1} from "../../../../src/lib/LibProdBeacons0_1_1.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../../../../src/lib/LibTimelockInvariants.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {LibBeaconInvariants} from "../../../../src/lib/LibBeaconInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";

/// @title RobinhoodBeaconOwnershipTest
/// @notice The Robinhood Chain leg of the per-chain beacon pin: every production
/// beacon carries the OZ `UpgradeableBeacon` codehash, points at its pinned
/// implementation, and is owned by the chain's governance timelock.
/// @dev Unpinned head fork: the point is drift detection against live state.
contract RobinhoodBeaconOwnershipTest is Test {
    /// Every Robinhood Chain beacon is owned by the Robinhood Chain governance timelock,
    /// with the OZ beacon codehash and its pinned implementation unchanged.
    function testRobinhoodBeaconsAreTimelockOwned() external {
        address timelock = LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_ROBINHOOD;

        vm.createSelectFork(LibStoxDeployNetworks.ROBINHOOD);
        address[4] memory beacons = LibProdBeacons0_1_1.beacons();
        address[4] memory impls = LibProdBeacons0_1_1.implementations();
        // Every expected implementation is named as an explicit pin. The
        // wrapped-token-vault beacon serves the 0.1.1 impl its bootstrap
        // baked; the receipt + receipt-vault beacons were moved onto 0.1.30
        // by the fleet upgrade (20260825-upgrade-fleet-to-0-1-30), which has
        // landed on every chain. Reading the beacon's own
        // `implementation()` back as the expectation asserted only that the
        // beacon agrees with itself, which no upgrade can ever break.
        LibBeaconInvariants.assertBeaconInvariants(
            beacons[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX],
            timelock,
            impls[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX]
        );
        LibBeaconInvariants.assertBeaconInvariants(
            beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX], timelock, LibProdDeployV4.STOX_RECEIPT_0_1_30
        );
        LibBeaconInvariants.assertBeaconInvariants(
            beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX], timelock, LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30
        );
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibProdBeacons0_1_1} from "../../../../src/lib/LibProdBeacons0_1_1.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {LibBeaconInvariants} from "../../../../src/lib/LibBeaconInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";

/// @title BscBeaconOwnershipTest
/// @notice The forcing function for the BNB Smart Chain beacon-ownership
/// migration (`20260909-upgrade-and-migrate-token-beacons`), mirroring
/// `RobinhoodBeaconOwnershipTest`: every chain's production beacons must be
/// owned by that chain's token-owner Safe. RED from the moment the 0.1.1
/// impl suites land on BNB Smart Chain (beacons come up EOA-owned) until
/// the migration runs; green thereafter, catching later ownership drift.
///
/// @dev The invariant runs unconditionally: the BNB Smart Chain token-owner
/// Safe is pinned in `LibSafeInvariants`, and CI supplies `BSC_RPC_URL`
/// to the shared rainix test workflow from the `RPC_URL_BSC_FORK`
/// secret, so the fork always resolves.
contract BscBeaconOwnershipTest is Test {
    /// Every BNB Smart Chain beacon is owned by the BNB Smart Chain token-owner
    /// Safe (with
    /// the OZ beacon codehash + its pinned impl unchanged). RED until the
    /// migration transfers ownership from the deploy EOA to the Safe.
    function testBscBeaconsAreSafeOwned() external {
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_BSC;

        vm.createSelectFork(LibStoxDeployNetworks.BSC);
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

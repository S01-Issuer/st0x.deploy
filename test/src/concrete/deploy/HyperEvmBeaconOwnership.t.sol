// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibProdBeacons0_1_1} from "../../../../src/lib/LibProdBeacons0_1_1.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {LibMigrationInvariant} from "../../../../src/lib/LibMigrationInvariant.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {FLEET_UPGRADE_DEADLINE} from "../../../../script/20260825-upgrade-fleet-to-0-1-30.s.sol";
import {LibBeaconInvariants} from "../../../../src/lib/LibBeaconInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";

/// @title HyperEvmBeaconOwnershipTest
/// @notice The forcing function for the HyperEVM beacon-ownership migration
/// (`20260722-migrate-beacon-owners-hyperevm`), mirroring
/// `EthereumBeaconOwnershipTest`: every chain's production beacons must be
/// owned by that chain's token-owner Safe. RED from the moment the 0.1.1
/// impl suites land on HyperEVM (beacons come up EOA-owned) until the
/// migration runs; green thereafter, catching later ownership drift.
///
/// @dev The invariant runs unconditionally: the HyperEVM token-owner Safe is
/// pinned in `LibSafeInvariants`, and CI supplies `HYPEREVM_RPC_URL` to the
/// shared rainix test workflow from the `RPC_URL_HYPEREVM_FORK` secret, so the
/// fork always resolves.
contract HyperEvmBeaconOwnershipTest is Test {
    /// Every HyperEVM beacon is owned by the HyperEVM token-owner Safe (with
    /// the OZ beacon codehash + its pinned impl unchanged). RED until the
    /// migration transfers ownership from the deploy EOA to the Safe.
    function testHyperEvmBeaconsAreSafeOwned() external {
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_HYPEREVM;

        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        address[4] memory beacons = LibProdBeacons0_1_1.beacons();
        address[4] memory impls = LibProdBeacons0_1_1.implementations();
        // The wrapped-token-vault beacon (index 2) still serves its 0.1.1
        // impl; the receipt + receipt-vault beacons ride the fleet-upgrade
        // migration window (20260825-upgrade-fleet-to-0-1-30): 0.1.1 OR
        // 0.1.30 until the deadline, 0.1.30 only after.
        LibBeaconInvariants.assertBeaconInvariants(beacons[2], safe, impls[2]);
        LibBeaconInvariants.assertBeaconInvariants(beacons[0], safe, IBeacon(beacons[0]).implementation());
        LibBeaconInvariants.assertBeaconInvariants(beacons[1], safe, IBeacon(beacons[1]).implementation());
        LibMigrationInvariant.assertMigration(
            "in-use receipt beacon implementation()",
            IBeacon(beacons[0]).implementation(),
            LibProdDeployV4.STOX_RECEIPT_0_1_1,
            LibProdDeployV4.STOX_RECEIPT_0_1_30,
            FLEET_UPGRADE_DEADLINE
        );
        LibMigrationInvariant.assertMigration(
            "in-use receipt-vault beacon implementation()",
            IBeacon(beacons[1]).implementation(),
            LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1,
            LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30,
            FLEET_UPGRADE_DEADLINE
        );
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibProdBeacons0_1_1} from "../../../../src/lib/LibProdBeacons0_1_1.sol";
import {LibProdDeployV1} from "../../../../src/lib/LibProdDeployV1.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {LibMigrationInvariant} from "../../../../src/lib/LibMigrationInvariant.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {FLEET_UPGRADE_DEADLINE} from "../../../../script/20260825-upgrade-fleet-to-0-1-30.s.sol";
import {LibBeaconInvariants} from "../../../../src/lib/LibBeaconInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";

/// @title EthereumBeaconOwnershipTest
/// @notice The forcing function for the Ethereum beacon-ownership migration.
/// Ethereum's 3 production beacons are deployed but still owned by the deploy
/// EOA (`LibProdDeployV1.BEACON_INITIAL_OWNER`, rainlang.eth). ST0x requires
/// every chain's beacons to be owned by that chain's token-owner Safe (Base's
/// were migrated in #253); until the Ethereum migration
/// (`20260716-migrate-beacon-owners-ethereum`) runs, this invariant is RED by
/// design — that is exactly what forces the migration to happen. It goes green
/// the moment ownership lands on `STOX_TOKEN_OWNER_SAFE_ETHEREUM`, and stays
/// green in CI thereafter (catching any later ownership drift).
contract EthereumBeaconOwnershipTest is Test {
    /// Every Ethereum beacon is owned by the Ethereum token-owner Safe (with
    /// the OZ beacon codehash + its pinned impl unchanged). RED until the
    /// migration transfers ownership from the deploy EOA to the Safe.
    function testEthereumBeaconsAreSafeOwned() external {
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM;
        if (safe == address(0)) {
            emit log("PENDING: Ethereum token-owner Safe not yet pinned - beacon-owner invariant cannot run");
            return;
        }

        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
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

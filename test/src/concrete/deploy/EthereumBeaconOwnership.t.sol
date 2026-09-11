// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibProdBeacons0_1_1} from "../../../../src/lib/LibProdBeacons0_1_1.sol";
import {LibProdDeployV1} from "../../../../src/lib/LibProdDeployV1.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
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

        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
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

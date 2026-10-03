// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibProdBeacons0_1_1} from "../../../../src/lib/LibProdBeacons0_1_1.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {LibBeaconInvariants} from "../../../../src/lib/LibBeaconInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";

/// @title RobinhoodBeaconOwnershipTest
/// @notice Robinhood Chain's leg of the per-chain beacon pin.
/// @dev Forks Robinhood Chain head unconditionally; needs `ROBINHOOD_RPC_URL`.
contract RobinhoodBeaconOwnershipTest is Test {
    /// Every Robinhood Chain beacon is owned by the Robinhood Chain token-owner
    /// Safe, carries the OZ beacon codehash, and points at its pinned impl.
    function testRobinhoodBeaconsAreSafeOwned() external {
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ROBINHOOD;

        vm.createSelectFork(LibStoxDeployNetworks.ROBINHOOD);
        address[4] memory beacons = LibProdBeacons0_1_1.beacons();
        address[4] memory impls = LibProdBeacons0_1_1.implementations();
        // The wrapped-token-vault beacon serves the 0.1.1 impl; the receipt
        // and receipt-vault beacons serve 0.1.30. Every expectation
        // here is an explicit pin, named in this repo. Reading the beacon's
        // own `implementation()` back as the expectation would assert only
        // that the beacon agrees with itself, which no upgrade can break.
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

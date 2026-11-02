// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibProdBeacons0_1_1} from "../../../../src/lib/LibProdBeacons0_1_1.sol";
import {LibProdDeployV1} from "../../../../src/lib/LibProdDeployV1.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../../../../src/lib/LibTimelockInvariants.sol";
import {LibBeaconInvariants} from "../../../../src/lib/LibBeaconInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";

/// @title EthereumBeaconOwnershipTest
/// @notice The Ethereum leg of the per-chain beacon pin: every production
/// beacon carries the OZ `UpgradeableBeacon` codehash, points at its pinned
/// implementation, and is owned by the chain's governance timelock.
/// @dev Unpinned head fork: the point is drift detection against live state.
contract EthereumBeaconOwnershipTest is Test {
    /// Every Ethereum beacon is owned by the Ethereum governance timelock,
    /// with the OZ beacon codehash and its pinned implementation unchanged.
    function testEthereumBeaconsAreTimelockOwned() external {
        address timelock = LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_ETHEREUM;

        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        address[4] memory beacons = LibProdBeacons0_1_1.beacons();
        address[4] memory impls =
            LibBeaconInvariants.prodExpectedImplementationsForChainId(LibSafeInvariants.ETHEREUM_CHAIN_ID);
        LibBeaconInvariants.assertBeaconInvariants(
            beacons[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX],
            timelock,
            impls[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX]
        );
        LibBeaconInvariants.assertBeaconInvariants(
            beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX], timelock, impls[LibBeaconInvariants.RECEIPT_BEACON_INDEX]
        );
        LibBeaconInvariants.assertBeaconInvariants(
            beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX],
            timelock,
            impls[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX]
        );
    }
}

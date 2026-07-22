// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibProdBeacons0_1_1} from "../../../../src/lib/LibProdBeacons0_1_1.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
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
/// @dev Two loud PENDING gates while upstream state lands (RAI-1511): the
/// HyperEVM Safe pin, and the HyperEVM RPC env (the shared rainix test
/// workflow has no HyperEVM secret slot yet). Remove the env gate once CI
/// carries the secret.
contract HyperEvmBeaconOwnershipTest is Test {
    /// Every HyperEVM beacon is owned by the HyperEVM token-owner Safe (with
    /// the OZ beacon codehash + its pinned impl unchanged). RED until the
    /// migration transfers ownership from the deploy EOA to the Safe.
    function testHyperEvmBeaconsAreSafeOwned() external {
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_HYPEREVM;
        if (safe == address(0)) {
            emit log("PENDING: HyperEVM token-owner Safe not yet pinned - beacon-owner invariant cannot run (RAI-1511)");
            return;
        }
        if (bytes(vm.envOr("HYPEREVM_RPC_URL", string(""))).length == 0) {
            emit log("PENDING: HYPEREVM_RPC_URL not available in this environment (RAI-1511)");
            return;
        }

        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        address[3] memory beacons = LibProdBeacons0_1_1.beacons();
        address[3] memory impls = LibProdBeacons0_1_1.implementations();
        for (uint256 i = 0; i < beacons.length; i++) {
            LibBeaconInvariants.assertBeaconInvariants(beacons[i], safe, impls[i]);
        }
    }
}

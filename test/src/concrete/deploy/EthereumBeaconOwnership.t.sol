// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibProdBeaconsEthereum} from "../../../../src/lib/LibProdBeaconsEthereum.sol";
import {LibProdDeployV1} from "../../../../src/lib/LibProdDeployV1.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
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
        address[3] memory beacons = LibProdBeaconsEthereum.beacons();
        address[3] memory impls = LibProdBeaconsEthereum.implementations();
        for (uint256 i = 0; i < beacons.length; i++) {
            LibBeaconInvariants.assertBeaconInvariants(beacons[i], safe, impls[i]);
        }
    }
}

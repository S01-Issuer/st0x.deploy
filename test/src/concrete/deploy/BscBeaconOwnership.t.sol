// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";
import {LibBeaconInvariants} from "../../../../src/lib/LibBeaconInvariants.sol";

/// @title BscBeaconOwnershipTest
/// @notice The Bsc leg of the per-chain beacon pin.
/// @dev Unpinned head fork: the point is drift detection against live state.
contract BscBeaconOwnershipTest is Test {
    /// Every in-use Bsc beacon carries its build's codehash, is owned by the chain's governance timelock and
    /// serves its expected implementation.
    function testBscBeaconsAreTimelockOwned() external {
        vm.createSelectFork(LibStoxDeployNetworks.BSC);
        LibBeaconInvariants.assertProdBeaconsAtExpectedState(block.chainid);
    }
}

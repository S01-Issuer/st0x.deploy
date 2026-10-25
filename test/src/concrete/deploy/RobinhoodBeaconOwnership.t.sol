// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";
import {LibBeaconInvariants} from "../../../../src/lib/LibBeaconInvariants.sol";

/// @title RobinhoodBeaconOwnershipTest
/// @notice The Robinhood leg of the per-chain beacon pin.
/// @dev Unpinned head fork: the point is drift detection against live state.
contract RobinhoodBeaconOwnershipTest is Test {
    /// Every in-use Robinhood beacon carries its build's codehash, is owned by the chain's governance timelock and
    /// serves its expected implementation.
    function testRobinhoodBeaconsAreTimelockOwned() external {
        vm.createSelectFork(LibStoxDeployNetworks.ROBINHOOD);
        LibBeaconInvariants.assertProdBeaconsAtExpectedState(block.chainid);
    }
}

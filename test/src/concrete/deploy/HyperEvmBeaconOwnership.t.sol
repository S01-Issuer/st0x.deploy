// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";
import {LibBeaconInvariants} from "../../../../src/lib/LibBeaconInvariants.sol";

/// @title HyperEvmBeaconOwnershipTest
/// @notice The HyperEvm leg of the per-chain beacon pin.
/// @dev Unpinned head fork: the point is drift detection against live state.
contract HyperEvmBeaconOwnershipTest is Test {
    /// Every in-use HyperEvm beacon carries its build's codehash, is owned by the chain's governance timelock and
    /// serves its expected implementation.
    function testHyperEvmBeaconsAreTimelockOwned() external {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        LibBeaconInvariants.assertProdBeaconsAtExpectedState(block.chainid);
    }
}

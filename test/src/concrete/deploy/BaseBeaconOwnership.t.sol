// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.22/src/lib/LibRainDeploy.sol";
import {LibBeaconInvariants} from "../../../../src/lib/LibBeaconInvariants.sol";

/// @title BaseBeaconOwnershipTest
/// @notice The Base leg of the per-chain beacon pin.
/// @dev Unpinned head fork: the point is drift detection against live state.
contract BaseBeaconOwnershipTest is Test {
    /// Every in-use Base beacon carries its build's codehash, is owned by the chain's governance timelock and
    /// serves its expected implementation.
    function testBaseBeaconsAreTimelockOwnedAtTheirPinnedImpls() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        LibBeaconInvariants.assertProdBeaconsAtExpectedState(block.chainid);
    }
}

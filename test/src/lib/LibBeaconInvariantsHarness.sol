// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibBeaconInvariants} from "../../../src/lib/LibBeaconInvariants.sol";

/// @title LibBeaconInvariantsHarness
/// @notice External-call shim around the internal library so
/// `vm.expectRevert` can intercept the typed errors. `vm.expectRevert` only
/// catches reverts from external calls; library `internal` functions inline
/// and would fail the depth check otherwise.
contract LibBeaconInvariantsHarness {
    function callAssertBeaconInvariants(address beacon, address expectedOwner, address expectedImpl) external view {
        LibBeaconInvariants.assertBeaconInvariants(beacon, expectedOwner, expectedImpl);
    }
}

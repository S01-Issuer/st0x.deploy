// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {IGnosisSafe} from "../../../src/interface/IGnosisSafe.sol";

/// @title LibSafeInvariantsHarness
/// @notice External-call shim around the internal library so
/// `vm.expectRevert` can intercept the typed errors. `vm.expectRevert` only
/// catches reverts from external calls; library `internal` functions inline
/// and would fail the depth check otherwise.
contract LibSafeInvariantsHarness {
    function callAssertImmutableInvariants(IGnosisSafe safe) external view {
        LibSafeInvariants.assertImmutableInvariants(safe);
    }

    function callAssertOwnerSet(IGnosisSafe safe, address[] memory expected) external view {
        LibSafeInvariants.assertOwnerSet(safe, expected);
    }

    function callAssertThreshold(IGnosisSafe safe, uint256 expected) external view {
        LibSafeInvariants.assertThreshold(safe, expected);
    }

    function callAssertAll(IGnosisSafe safe, uint256 expectedThreshold, address[] memory expectedOwners) external view {
        LibSafeInvariants.assertAll(safe, expectedThreshold, expectedOwners);
    }

    function callAssertAllDefaults(IGnosisSafe safe) external view {
        LibSafeInvariants.assertAll(safe);
    }

    function callAssertBeaconInvariants(address beacon, address expectedOwner, address expectedImpl) external view {
        LibSafeInvariants.assertBeaconInvariants(beacon, expectedOwner, expectedImpl);
    }
}

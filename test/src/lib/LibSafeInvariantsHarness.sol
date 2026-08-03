// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibBeaconInvariants} from "../../../src/lib/LibBeaconInvariants.sol";
import {IGnosisSafe} from "../../../src/interface/IGnosisSafe.sol";

/// @title LibSafeInvariantsHarness
/// @notice External-call shim around the internal library so
/// `vm.expectRevert` can intercept the typed errors. `vm.expectRevert` only
/// catches reverts from external calls; library `internal` functions inline
/// and would fail the depth check otherwise.
contract LibSafeInvariantsHarness {
    /// @notice Resolve a chain's pinned token-owner Safe through an external
    /// call, so callers can `try`/`catch` the
    /// `UnsupportedChainForTokenOwnerSafe` revert and treat "is this chain
    /// governed yet?" as a question rather than a failure.
    function callSafeForChainId(uint256 chainId) external pure returns (address) {
        return LibSafeInvariants.safeForChainId(chainId);
    }

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
        LibBeaconInvariants.assertBeaconInvariants(beacon, expectedOwner, expectedImpl);
    }
}

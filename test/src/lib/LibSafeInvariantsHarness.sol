// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibBeaconInvariants} from "../../../src/lib/LibBeaconInvariants.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";

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

    function callAssertBeaconInvariants(address beacon, address expectedOwner, address expectedImpl) external view {
        LibBeaconInvariants.assertBeaconInvariants(beacon, expectedOwner, expectedImpl);
    }
}

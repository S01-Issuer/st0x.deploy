// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {LibClosureInvariants} from "../../../src/lib/LibClosureInvariants.sol";

/// @title LibClosureInvariantsHarness
/// @notice External-call shim around the internal library so
/// `vm.expectRevert` can intercept the typed errors. `vm.expectRevert` only
/// catches reverts from external calls; library `internal` functions inline
/// and would fail the depth check otherwise.
contract LibClosureInvariantsHarness {
    /// @notice `LibClosureInvariants.assertClosureContract`, externally
    /// callable.
    /// @param pinned The pinned closure address.
    /// @param codehash The pinned codehash.
    function callAssertClosureContract(address pinned, bytes32 codehash) external view {
        LibClosureInvariants.assertClosureContract(pinned, codehash);
    }
}

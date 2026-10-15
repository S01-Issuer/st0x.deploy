// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibTokenInvariants} from "../../../src/lib/LibTokenInvariants.sol";

/// @title LibTokenInvariantsHarness
/// @notice External-call shim around the internal library so
/// `vm.expectRevert` can intercept the typed errors. `vm.expectRevert` only
/// catches reverts from external calls; library `internal` functions inline
/// and would fail the depth check otherwise.
contract LibTokenInvariantsHarness {
    function callAssertUniformOwnership(address expectedOwner) external view {
        LibTokenInvariants.assertUniformOwnership(expectedOwner);
    }

    function callAssertUniformAuthoriser(address expected) external view {
        LibTokenInvariants.assertUniformAuthoriser(expected);
    }
}

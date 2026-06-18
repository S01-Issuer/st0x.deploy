// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibSafeOps} from "../../../src/lib/LibSafeOps.sol";

/// @notice External-call harness around `LibSafeOps.packApprovedHashSignatures`
/// so the pure-function's overflow `require` can be caught by
/// `vm.expectRevert`.
contract PackHarness {
    function callPack(address[] calldata sortedSigners, uint256 count) external pure returns (bytes memory) {
        return LibSafeOps.packApprovedHashSignatures(sortedSigners, count);
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibSafeOps} from "../../../src/lib/LibSafeOps.sol";
import {IGnosisSafe} from "../../../src/interface/IGnosisSafe.sol";

/// @notice External-call harness around `LibSafeOps.simulateNPlus1Reversal`
/// for cases where the helper itself is expected to revert (e.g. the
/// "not enough owners" require). `vm.expectRevert` needs the revert to
/// originate from a deeper call frame than the cheatcode call, which a
/// direct library invocation from the test does not produce.
contract NPlus1Harness {
    function callSimulateNPlus1Reversal(IGnosisSafe safe, uint256 oldThreshold, uint256 newThreshold) external {
        LibSafeOps.simulateNPlus1Reversal(safe, oldThreshold, newThreshold);
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibSafeOps} from "../../../src/lib/LibSafeOps.sol";

/// @notice External-call harness around `LibSafeOps.parseTxBuilderJson` so
/// `vm.expectRevert` can catch the typed error. `expectRevert` only sees
/// reverts that bubble from a lower call depth than the cheatcode itself,
/// and library-internal reverts inline.
contract ParseHarness {
    function callParse(string calldata jsonPath) external view {
        LibSafeOps.parseTxBuilderJson(jsonPath);
    }
}

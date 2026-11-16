// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {BuildExpectedState} from "../../script/BuildExpectedState.sol";

/// @title BuildExpectedStateHarness
/// @notice External shim so `vm.expectRevert` can intercept reverts from the script's internal emitters.
contract BuildExpectedStateHarness is BuildExpectedState {
    function callTokenMetadataJson(string memory row, uint256 i, string memory underlying) external {
        tokenMetadataJson(row, i, underlying);
    }
}

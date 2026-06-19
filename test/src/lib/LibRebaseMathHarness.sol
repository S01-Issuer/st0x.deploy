// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
import {LibRebaseMath} from "src/lib/LibRebaseMath.sol";

contract LibRebaseMathHarness {
    function applyMultiplier(uint256 balance, Float multiplier) external pure returns (uint256) {
        return LibRebaseMath.applyMultiplier(balance, multiplier);
    }
}

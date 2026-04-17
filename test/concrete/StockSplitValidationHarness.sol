// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float} from "rain.math.float/lib/LibDecimalFloat.sol";
import {LibStockSplit} from "../../src/lib/LibStockSplit.sol";
import {DecimalsMock} from "./DecimalsMock.sol";

/// @title StockSplitValidationHarness
/// @notice Test harness exposing `LibStockSplit.validateMultiplier` as an
/// external function. Implements `decimals()` so the TOFU singleton has
/// something to read when validation resolves `address(this)` decimals.
contract StockSplitValidationHarness is DecimalsMock {
    constructor(uint8 decimals_) DecimalsMock(decimals_) {}

    function validate(Float multiplier) external {
        LibStockSplit.validateMultiplier(multiplier);
    }
}

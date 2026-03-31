// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float} from "rain.math.float/lib/LibDecimalFloat.sol";

/// @dev The action type identifier for stock splits.
bytes32 constant ACTION_TYPE_STOCK_SPLIT = keccak256("STOCK_SPLIT");

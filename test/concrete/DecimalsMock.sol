// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title DecimalsMock
/// @notice Base test contract that exposes a constructor-configurable
/// `decimals()` so test harnesses can stand in for ERC20-ish callers when
/// the code under test reads decimals via `address(this)`.
abstract contract DecimalsMock {
    uint8 internal immutable _DECIMALS;

    constructor(uint8 decimals_) {
        _DECIMALS = decimals_;
    }

    function decimals() external view returns (uint8) {
        return _DECIMALS;
    }
}

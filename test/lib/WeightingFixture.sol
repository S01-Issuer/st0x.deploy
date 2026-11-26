// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

/// @title WeightingFixture
/// @notice The keys and binding values `script/BuildWeightingBindings.sol`
/// composes the `test/composed` weightings from, shared with the tests that
/// eval them.
abstract contract WeightingFixture {
    string internal constant DIR = "test/composed/";

    uint256 internal constant LEAD_KEY = 0x1EAD;
    uint256 internal constant OPERATOR_KEY_0 = 0x0A00;
    uint256 internal constant POOL_SIZE = 6;
    string internal constant MAX_DEVIATION = "0.01";
    int256 internal constant MAX_TIME_SPREAD = 600;
    int256 internal constant MIN_PRICE = 100;
    int256 internal constant MAX_PRICE = 1000;
    int256 internal constant MIN_PRICE_VARIANT = 1;
    string internal constant LEAD_SOURCE = "alpaca";
    string internal constant POOL_SOURCE_0 = "yahoo";
    string internal constant POOL_SOURCE_1 = "alpaca";
}

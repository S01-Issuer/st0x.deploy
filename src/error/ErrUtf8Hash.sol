// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev Thrown when a `utf8-hash` input is not an IntOrAString string.
/// @param index The position of the input.
/// @param value The input.
error NotAString(uint256 index, bytes32 value);

/// @dev Thrown when `utf8-hash` is given no inputs.
error Utf8HashNoInputs();

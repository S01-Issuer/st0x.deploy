// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @notice `underlying-symbol` read an empty `underlyingSymbol()`.
/// @param token The token read.
error UnderlyingSymbolEmpty(address token);

/// @notice `underlying-symbol` read an `underlyingSymbol()` longer than the 31
/// bytes an `IntOrAString` holds. Refused rather than truncated, since a
/// truncated ticker can be another token's.
/// @param token The token read.
/// @param length The ticker's length in bytes.
error UnderlyingSymbolTooLong(address token, uint256 length);

/// @notice `underlying-symbol` input has bits set above the low 160, so it is
/// not an address. Refused rather than truncated, since the truncation is
/// another address.
/// @param input The input as given.
error UnderlyingSymbolNotAnAddress(bytes32 input);

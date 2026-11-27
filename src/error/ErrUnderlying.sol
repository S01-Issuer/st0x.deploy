// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// Thrown when `setUnderlying` is called with a symbol that fails
/// `LibSecurity.tickerWellFormed`, the rule init applies to the listing ticker.
error MalformedUnderlyingSymbol(string symbol);

/// Thrown when `setUnderlying` is called with a name that fails
/// `LibSecurity.nameWellFormed`, the rule init applies to the listing name.
error MalformedUnderlyingName(string name);

/// Thrown when `setUnderlying` is called with an ISIN that fails
/// `LibSecurity.isinWellFormed`, the rule init applies to the asset id.
error MalformedUnderlyingIsin(string isin);

/// Thrown when an underlying snapshot root or shard has no code, or its header
/// or row bytes do not match the snapshot format.
/// @param account The snapshot contract whose code was refused.
error MalformedUnderlyingSnapshot(address account);

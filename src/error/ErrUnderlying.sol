// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// Thrown when `setUnderlying` is called with an empty symbol. The token
/// symbols built from the underlying ticker would otherwise collapse to their
/// bare prefix or suffix.
error EmptyUnderlyingSymbol();

/// Thrown when `setUnderlying` is called with an empty name. The token names
/// built from the underlying name would otherwise be empty.
error EmptyUnderlyingName();

/// Thrown when an underlying snapshot root or shard has no code or its bytes
/// do not match the snapshot format.
/// @param account The snapshot contract whose code was refused.
error MalformedUnderlyingSnapshot(address account);

/// Thrown when a per-token underlying override binding's value is not the
/// canonical `(string,string)` encoding.
/// @param name The registry name of the refused binding.
error NonCanonicalUnderlyingBinding(bytes32 name);

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

/// Thrown when an underlying snapshot root or shard has no code, or its header
/// or row bytes do not match the snapshot format.
/// @param account The snapshot contract whose code was refused.
error MalformedUnderlyingSnapshot(address account);

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// Thrown when scheduling an action with an effective time in the past.
error EffectiveTimeInPast(uint64 effectiveTime, uint256 currentTime);

/// Thrown when trying to cancel an action whose effectiveTime has passed.
error ActionAlreadyComplete(uint256 actionIndex);

/// Thrown when referencing an action that does not exist.
error ActionDoesNotExist(uint256 actionIndex);

/// Thrown when the external type hash has no known bitmap mapping.
/// @param typeHash The unrecognised external identifier.
error UnknownActionType(bytes32 typeHash);

/// Thrown when a traversal getter is called with a mask that contains no
/// currently valid action-type bits — i.e.
/// `mask & VALID_ACTION_TYPES_MASK == 0`. Every node's `actionType` has at
/// least one valid bit set by construction, so such a mask can never match
/// any node. This covers both `mask == 0` and masks that only set bits
/// outside `VALID_ACTION_TYPES_MASK`. Reverting distinguishes a caller input
/// bug from a legitimate "no match found" result for a valid mask.
error InvalidMask();

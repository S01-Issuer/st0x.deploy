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

/// Thrown when accessing head/tail on a list with no scheduled actions.
error NoActionsScheduled();

/// Thrown when a traversal getter is called with `mask == 0`. Every node's
/// `actionType` has at least one bit set by construction (types are single
/// bits `1 << n`), so a zero mask can never match any node. Reverting
/// distinguishes a caller input bug from a legitimate "no match found"
/// result for a valid mask.
error InvalidMask();

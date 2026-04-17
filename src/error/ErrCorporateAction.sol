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

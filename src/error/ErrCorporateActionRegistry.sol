// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// Thrown when an action's effective time is not in the future.
/// @param effectiveTime The effective time that was provided.
/// @param currentTime The current block timestamp.
error EffectiveTimeMustBeFuture(uint256 effectiveTime, uint256 currentTime);

/// Thrown when attempting to execute an action that is not in SCHEDULED state.
/// @param token The token address.
/// @param actionType The action type.
/// @param number The action number.
error ActionNotScheduled(address token, bytes32 actionType, uint256 number);

/// Thrown when attempting to execute an action before its effective time.
/// @param effectiveTime The effective time of the action.
/// @param currentTime The current block timestamp.
error ActionNotYetEffective(uint256 effectiveTime, uint256 currentTime);

/// Thrown when attempting to look up an action that does not exist.
/// @param token The token address.
/// @param actionType The action type.
/// @param number The action number.
error ActionDoesNotExist(address token, bytes32 actionType, uint256 number);

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @notice Thrown when applying a multiplier to a balance that exceeds
/// `type(int256).max`, which would wrap silently to a negative Float coefficient.
/// @param balance The offending balance.
error BalanceExceedsInt256Max(uint256 balance);

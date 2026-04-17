// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Float} from "rain.math.float/lib/LibDecimalFloat.sol";

/// @notice Thrown when a stock split multiplier has a zero or negative coefficient.
error InvalidSplitMultiplier();

/// @notice Thrown when a stock split multiplier is too small to preserve any
/// meaningful balance. Specifically, a multiplier that, when applied to 1e18
/// (a reasonable "meaningful minimum" balance for an 18-decimal token), rounds
/// to zero is rejected. Without this floor, an authorized scheduler could
/// schedule a near-zero multiplier (e.g. `packLossless(1, -30)`) that wipes
/// every holder's balance to 0 at the effective time.
/// @param multiplier The offending multiplier.
error MultiplierTooSmall(Float multiplier);

/// @notice Thrown when a stock split multiplier is large enough to risk
/// overflow when applied sequentially to realistic supplies. The bound is
/// `trunc(1e18 * multiplier) <= 1e36`, corresponding to a 1e18x growth
/// factor — far beyond any plausible real-world corporate action.
/// @param multiplier The offending multiplier.
error MultiplierTooLarge(Float multiplier);

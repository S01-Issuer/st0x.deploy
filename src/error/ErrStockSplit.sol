// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Float} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";

/// @notice Thrown when a stock split multiplier has a zero or negative coefficient.
error InvalidSplitMultiplier();

/// @notice Thrown when a stock split multiplier is too small to preserve a
/// one-whole-token balance. Specifically, a multiplier below 10^-D (D = the
/// vault's asset decimals) — one that, applied to a one-whole-token (10^D-wei)
/// balance, truncates it to zero — is rejected. Without this floor, an
/// authorized scheduler could schedule a near-zero multiplier (e.g.
/// `packLossless(1, -30)`) that wipes holders' balances to 0 at the effective
/// time. Balances below one whole token can still truncate to dust; the floor
/// only bounds the wipe to sub-one-token amounts.
/// @param multiplier The offending multiplier.
error MultiplierTooSmall(Float multiplier);

/// @notice Thrown when a stock split multiplier is large enough to risk
/// overflow when applied sequentially to realistic supplies. The bound is
/// per-vault: the multiplier must be at most 10^D (D = the vault's asset
/// decimals) — a 10^D-x growth factor (1e18x for an 18-decimal vault, 1e6x for
/// a 6-decimal USDC vault) — far beyond any plausible real-world corporate
/// action.
/// @param multiplier The offending multiplier.
error MultiplierTooLarge(Float multiplier);

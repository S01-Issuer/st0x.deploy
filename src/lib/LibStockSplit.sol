// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";

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

/// @title LibStockSplit
/// @notice Validation and encoding for stock split parameters.
library LibStockSplit {
    /// @notice Validate that encoded parameters contain a usable stock split
    /// multiplier.
    ///
    /// Rules:
    /// 1. The unpacked `coefficient` must be strictly positive — rejects
    ///    zero and negative coefficients (`InvalidSplitMultiplier`).
    /// 2. `trunc(1e18 * multiplier)` must be at least `1` — rejects
    ///    near-zero multipliers that would truncate every realistic balance
    ///    to zero on the first rebase pass (`MultiplierTooSmall`).
    /// 3. `trunc(1e18 * multiplier)` must be at most `1e36` — rejects
    ///    near-saturation multipliers that would risk overflow when applied
    ///    sequentially to realistic supplies (`MultiplierTooLarge`).
    ///
    /// The bounds are deliberately conservative. The largest historical real
    /// stock split was roughly 1000x (= 1e3), well inside the ceiling, and
    /// the smallest realistic reverse split would be around 1/1000 (= 1e-3),
    /// well above the floor. An authorized scheduler that wants to apply a
    /// multiplier outside these bounds is almost certainly misconfigured.
    ///
    /// @dev Pathologically large multipliers (e.g. `packLossless(1, 100)`) may
    /// saturate or revert inside `LibDecimalFloat.mul` / `toFixedDecimalLossy`
    /// before reaching the `applied > 1e36` branch. In that case the
    /// user-visible error is the float library's revert, not
    /// `MultiplierTooLarge`. This is acceptable — the scheduler is authorized
    /// and such inputs indicate misconfiguration either way.
    ///
    /// @param parameters ABI-encoded Float.
    function validateParameters(bytes memory parameters) internal pure {
        Float multiplier = abi.decode(parameters, (Float));
        // Only the coefficient is needed for the sign check; the exponent is
        // irrelevant because a negative/zero coefficient is rejected regardless.
        //slither-disable-next-line unused-return
        (int256 coefficient,) = LibDecimalFloat.unpack(multiplier);
        if (coefficient <= 0) revert InvalidSplitMultiplier();

        // Apply `multiplier` to 1e18 and truncate to uint256. Used for both
        // the floor and the ceiling check. The `int256(1e18)` cast is safe
        // because `1e18` is a compile-time constant far below `2^255`.
        // The second return value is the loss flag; we only need the truncated
        // value for bounds comparison.
        // forge-lint: disable-next-line(unsafe-typecast)
        //slither-disable-next-line unused-return
        (uint256 applied,) = LibDecimalFloat.toFixedDecimalLossy(
            LibDecimalFloat.mul(LibDecimalFloat.packLossless(int256(1e18), 0), multiplier), 0
        );
        if (applied == 0) revert MultiplierTooSmall(multiplier);
        if (applied > 1e36) revert MultiplierTooLarge(multiplier);
    }

    /// @notice Decode a stock split multiplier from parameters bytes.
    /// @dev Performs no bounds checking. Callers must only invoke on
    /// parameters that have been validated via `validateParameters` (which
    /// `resolveActionType` guarantees at schedule time). Decoding orphaned or
    /// pre-validation parameters is unsafe if called outside schedule-time
    /// code paths.
    /// @param parameters ABI-encoded Float.
    /// @return multiplier The Rain float multiplier.
    function decodeParameters(bytes memory parameters) internal pure returns (Float) {
        return abi.decode(parameters, (Float));
    }
}

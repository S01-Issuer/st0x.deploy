// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";

/// @title LibRebaseMath
/// @notice Shared primitive for applying a single Rain Float multiplier to a
/// `uint256` balance with rasterize-toward-zero truncation. The result is the
/// canonical "apply one rebase step" operation reused by every consumer of
/// the corporate-actions rebase system (share-side migration, per-cursor
/// totalSupply pots, and — from PR #7 onward — receipt-side migration).
///
/// Having a single helper guarantees that every rebase path uses identical
/// rounding characteristics: any future drift in Rain Float's precision
/// surfaces in one place rather than several, and the per-regression tests
/// (`testSequentialPrecision` across LibRebase / LibTotalSupply / the new
/// LibReceiptRebase) all trip at once if the underlying primitive changes.
library LibRebaseMath {
    /// @notice Apply a single rebase multiplier to a stored balance. Reads as
    /// `trunc(balance × multiplier)` — integer truncation toward zero, same
    /// as a direct `uint256` cast on a positive fixed-point value.
    ///
    /// The `int256(balance)` cast is safe because realistic ERC-20 / ERC-1155
    /// balances are well below `2^255`; `LibStockSplit.validateParameters`
    /// bounds the multiplier so the product cannot overflow the float
    /// library's internal mantissa for realistic inputs.
    ///
    /// @param balance The stored balance in wei.
    /// @param multiplier The Rain Float multiplier to apply.
    /// @return The rasterized balance after a single multiplier step.
    function applyMultiplier(uint256 balance, Float multiplier) internal pure returns (uint256) {
        (uint256 result,) = LibDecimalFloat.toFixedDecimalLossy(
            // forge-lint: disable-next-line(unsafe-typecast)
            LibDecimalFloat.mul(LibDecimalFloat.packLossless(int256(balance), 0), multiplier),
            0
        );
        return result;
    }
}

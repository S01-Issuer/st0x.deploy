// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Float, LibDecimalFloat} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
import {AmountNotRepresentableAsFloat} from "../error/ErrMintCapUnits.sol";

/// @title LibMintCapUnits
/// @notice Converts between *current* rebased tStock units and *genesis*
/// units, using the collapsed cumulative balance multiplier a token reports
/// from `ICorporateActionsV1.cumulativeBalanceMultiplierSinceGenesis()`.
///
/// A genesis unit is what one tStock unit meant before any corporate action
/// completed, and it is the denomination a mint cap is written in: a cap
/// stored in genesis units is rescaled by every rebase for free, with no
/// transaction to sequence behind the action and no window in which the
/// stored number means something other than what governance approved.
///
/// ## Why the collapsed product and not `LibRebase.migratedBalance`
///
/// `migratedBalance` rasterizes to `uint256` with `trunc` after *every*
/// multiplier, so dormant and active accounts converge on identical stored
/// balances. That per-step truncation is a property of balances, not of
/// denominated quantities: a cap is never "migrated" through the intermediate
/// states, it is a single number read at one instant, and truncating it once
/// per historical action would shrink it by an amount that depends on how
/// many actions happened to have occurred. The collapsed `Float` product is
/// the primitive whose own NatSpec names this as its sanctioned use, and the
/// two are not interchangeable in either direction.
///
/// ## Rounding
///
/// Neither direction is symmetric in what it costs if it is wrong, so neither
/// is left to the truncation that falls out of the arithmetic.
///
/// `toGenesis` converts a *consumed* amount, which is charged against a
/// bucket. Rounding it down would hand back headroom nobody earned, so it
/// rounds **up**.
///
/// `toCurrent` converts *available* headroom into the units a caller would
/// pass as `amount`. Rounding it up would name an amount that then does not
/// fit, so it rounds **down**. Down is also the direction that merely tightens
/// a cap, which is the safe way for a cap to be wrong.
library LibMintCapUnits {
    /// @notice Convert an amount in current rebased units into genesis units,
    /// rounding **up**.
    ///
    /// Rounding up is what keeps a bucket from being refunded by rounding:
    /// `toGenesis` is applied to the amount that is charged, so a result below
    /// the exact quotient is headroom granted for free, once per mint, to
    /// whoever splits their mints finely enough.
    ///
    /// Reverts `DivisionByZero` if `multiplierSinceGenesis` is zero and
    /// `NegativeFixedDecimalConversion` if it is negative. Neither is
    /// reachable from a well-formed token — `LibStockSplit` rejects a
    /// non-positive multiplier where an action is scheduled, and the
    /// cumulative product of positive multipliers is positive — and both fail
    /// closed, which is the correct direction for a cap.
    /// @param currentAmount The amount in current rebased tStock units.
    /// @param multiplierSinceGenesis The token's collapsed cumulative balance
    /// multiplier since genesis.
    /// @return The amount in genesis units, rounded up.
    function toGenesis(uint256 currentAmount, Float multiplierSinceGenesis) internal pure returns (uint256) {
        (Float current, bool representable) = LibDecimalFloat.fromFixedDecimalLossyPacked(currentAmount, 0);
        if (!representable) revert AmountNotRepresentableAsFloat(currentAmount);

        // `toFixedDecimalLossy` truncates toward zero and reports whether it
        // had to, which is exactly the predicate "there was a fractional part
        // to round away". Adding one on a lossy conversion is therefore the
        // ceiling, and on a lossless one the value is already the ceiling.
        (uint256 genesisAmount, bool lossless) =
            LibDecimalFloat.toFixedDecimalLossy(LibDecimalFloat.div(current, multiplierSinceGenesis), 0);
        // Checked arithmetic: an amount at the very top of the word reverts
        // rather than wrapping to zero, which would be a free mint.
        return lossless ? genesisAmount : genesisAmount + 1;
    }

    /// @notice Convert an amount in genesis units into current rebased units,
    /// rounding **down**.
    ///
    /// The exact inverse predicate of `toGenesis`: `floor(genesisAmount × m)`
    /// is the largest `currentAmount` whose `toGenesis` still fits
    /// `genesisAmount`, so a headroom reported through here is an amount that
    /// really is accepted rather than one that is one wei too large.
    ///
    /// Reverts `FixedDecimalOverflow` when the product does not fit a
    /// `uint256`. That is a headroom no `amount` could name in the first
    /// place, and a loud refusal is better than an answer that silently means
    /// something else.
    /// @param genesisAmount The amount in genesis units.
    /// @param multiplierSinceGenesis The token's collapsed cumulative balance
    /// multiplier since genesis.
    /// @return The amount in current rebased tStock units, rounded down.
    function toCurrent(uint256 genesisAmount, Float multiplierSinceGenesis) internal pure returns (uint256) {
        (Float genesis, bool representable) = LibDecimalFloat.fromFixedDecimalLossyPacked(genesisAmount, 0);
        if (!representable) revert AmountNotRepresentableAsFloat(genesisAmount);

        // The truncation `toFixedDecimalLossy` already performs IS the floor,
        // so the lossless flag is deliberately discarded here rather than
        // acted on.
        // slither-disable-next-line unused-return
        (uint256 currentAmount,) =
            LibDecimalFloat.toFixedDecimalLossy(LibDecimalFloat.mul(genesis, multiplierSinceGenesis), 0);
        return currentAmount;
    }
}

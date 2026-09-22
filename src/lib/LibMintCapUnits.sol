// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Float, LibDecimalFloat} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
import {AmountNotRepresentableAsFloat, NonPositiveDenomination} from "../error/ErrMintCapUnits.sol";

/// @title LibMintCapUnits
/// @notice Moves an eighteen-decimal tStock quantity between two
/// DENOMINATIONS of the same token.
///
/// ## What a denomination is
///
/// A tStock unit is not a fixed thing: a completed balance-migration
/// corporate action rescales every balance, so "one unit" means something
/// different before and after it. A denomination is therefore an instant, and
/// the thing that identifies that instant is the token's
/// `ICorporateActionsV1.cumulativeBalanceMultiplierSinceGenesis()` as at it —
/// the collapsed product of every balance-migration multiplier completed by
/// then. Call that `m`. A quantity of `v` units at the instant `m` was taken
/// is `v × m' / m` units at an instant whose multiplier is `m'`, because both
/// are the same product measured from the same origin.
///
/// So the whole of this library is one expression, `amount × to / from`, and
/// everything below is about the two things that expression does not say:
/// which way it rounds, and what it refuses.
///
/// The multipliers are only ever handles for instants. Nothing here walks the
/// action list, and nothing here is a balance migration:
/// `LibRebase.migratedBalance` rasterizes to `uint256` with `trunc` after
/// EVERY multiplier so that dormant and active accounts converge on identical
/// stored balances. That per-step truncation is a property of balances, not of
/// denominated quantities. A cap is never "migrated" through the intermediate
/// states — it is one number read at one instant — and truncating it once per
/// historical action would shrink it by an amount that depends on how many
/// actions happened to have occurred. The collapsed product is the primitive
/// whose own NatSpec names this as its sanctioned use, and the two are not
/// interchangeable in either direction.
///
/// ## Rounding
///
/// Neither direction is symmetric in what it costs if it is wrong, so neither
/// is left to the truncation that falls out of the arithmetic.
///
/// `redenominateUp` converts a quantity that is CHARGED against a bucket — a
/// mint amount on its way in, or an outstanding level being carried from one
/// denomination to another. Rounding either down hands back headroom nobody
/// earned, so both round up.
///
/// `redenominateDown` converts AVAILABLE headroom into the units a caller
/// would pass as `amount`. Rounding it up would name an amount that then does
/// not fit, so it rounds down. Down is also the direction that merely tightens
/// a cap, which is the safe way for a cap to be wrong.
library LibMintCapUnits {
    /// @notice Convert `amount` from the denomination `fromDenomination`
    /// identifies into the one `toDenomination` identifies, rounding **up**.
    ///
    /// Rounding up is what keeps a bucket from being refunded by rounding: a
    /// result below the exact value is credit granted for free, once per
    /// conversion, to whoever splits their mints finely enough.
    /// @param amount The quantity, in `fromDenomination`'s units.
    /// @param fromDenomination The cumulative balance multiplier identifying
    /// the denomination `amount` is in.
    /// @param toDenomination The cumulative balance multiplier identifying the
    /// denomination to express it in.
    /// @return The quantity in `toDenomination`'s units, rounded up.
    function redenominateUp(uint256 amount, Float fromDenomination, Float toDenomination)
        internal
        pure
        returns (uint256)
    {
        if (amount == 0) return 0;
        (uint256 converted, bool lossless) = scale(amount, fromDenomination, toDenomination);
        // Checked arithmetic: a quantity at the very top of the word reverts
        // rather than wrapping to zero, which would be a free mint.
        return lossless ? converted : converted + 1;
    }

    /// @notice Convert `amount` from the denomination `fromDenomination`
    /// identifies into the one `toDenomination` identifies, rounding **down**.
    ///
    /// The exact inverse predicate of `redenominateUp`: the floor is the
    /// largest quantity whose round-up conversion back still fits what it came
    /// from, so a headroom reported through here is an amount that really is
    /// accepted rather than one that is one wei too large.
    /// @param amount The quantity, in `fromDenomination`'s units.
    /// @param fromDenomination The cumulative balance multiplier identifying
    /// the denomination `amount` is in.
    /// @param toDenomination The cumulative balance multiplier identifying the
    /// denomination to express it in.
    /// @return The quantity in `toDenomination`'s units, rounded down.
    function redenominateDown(uint256 amount, Float fromDenomination, Float toDenomination)
        internal
        pure
        returns (uint256)
    {
        if (amount == 0) return 0;
        // The truncation `scale` already performs IS the floor, so the
        // lossless flag is deliberately discarded here rather than acted on.
        // slither-disable-next-line unused-return
        (uint256 converted,) = scale(amount, fromDenomination, toDenomination);
        return converted;
    }

    /// @dev `amount × toDenomination / fromDenomination`, truncated toward
    /// zero, with the flag saying whether it had to truncate. That flag is
    /// exactly the predicate "there was a fractional part to round away", so
    /// the two directions above are this plus a decision about it.
    ///
    /// Refuses two inputs outright rather than converting them.
    ///
    /// An `amount` that does not fit the 224-bit signed coefficient is
    /// refused, because rounding is only a deliberate choice while the value
    /// it is applied to is exact: `packLossy` would truncate such an amount
    /// toward zero BEFORE the conversion, which for a charged amount is a
    /// silent discount rather than the round-up this library promises.
    ///
    /// A non-positive denomination is refused on both sides. Zero is what an
    /// unset limit's stored multiplier reads as, and a zero `toDenomination`
    /// would scale any quantity to nothing — a total refund of whatever was
    /// outstanding, granted silently. Negative is unreachable from a
    /// well-formed token (`LibStockSplit` rejects a non-positive multiplier
    /// where an action is scheduled, and a product of positive multipliers is
    /// positive) and is refused on the same terms. Callers are expected to
    /// establish that a limit HAS a denomination before they reach here; this
    /// is the guard that makes forgetting fail closed rather than fail open.
    /// @param amount The quantity to convert. Never zero — both callers return
    /// early for zero, which is the one quantity that is the same in every
    /// denomination, including one that does not exist.
    /// @param fromDenomination The denomination `amount` is in.
    /// @param toDenomination The denomination to express it in.
    /// @return The converted quantity, truncated toward zero.
    /// @return True if the conversion was exact.
    function scale(uint256 amount, Float fromDenomination, Float toDenomination) internal pure returns (uint256, bool) {
        if (LibDecimalFloat.lte(fromDenomination, LibDecimalFloat.FLOAT_ZERO)) {
            revert NonPositiveDenomination(fromDenomination);
        }
        if (LibDecimalFloat.lte(toDenomination, LibDecimalFloat.FLOAT_ZERO)) {
            revert NonPositiveDenomination(toDenomination);
        }

        (Float value, bool representable) = LibDecimalFloat.fromFixedDecimalLossyPacked(amount, 0);
        if (!representable) revert AmountNotRepresentableAsFloat(amount);

        // Same denomination, same number. Returned before the arithmetic
        // rather than through it: a multiply followed by a divide by the same
        // float can only lose digits, and this is the case EVERY token is in
        // until its first corporate action completes, and the case every
        // bucket is in between one governance write and the next.
        // Exact by construction, not by the float path: identical denominations
        // scale by one, and a conversion that never happened cannot be lossy.
        // forge-lint: disable-next-line(boolean-cst)
        if (Float.unwrap(fromDenomination) == Float.unwrap(toDenomination)) return (amount, true);

        // Both halves of the tuple are returned to the caller, who acts on the
        // lossless flag; nothing is discarded here.
        // slither-disable-next-line unused-return
        return LibDecimalFloat.toFixedDecimalLossy(
            LibDecimalFloat.div(LibDecimalFloat.mul(value, toDenomination), fromDenomination), 0
        );
    }
}

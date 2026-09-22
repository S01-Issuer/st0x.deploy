// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Float} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";

/// @notice Thrown when an amount cannot be carried through a `Float` without
/// losing digits, i.e. it does not fit the 224-bit signed coefficient
/// (~2.7e67, or ~2.7e49 whole tokens at eighteen decimals).
///
/// Rounding is only a deliberate choice while the value it is applied to is
/// exact. `packLossy` would truncate such an amount toward zero *before* the
/// conversion, which for a consumed amount is a silent discount rather than
/// the round-up this library promises, so the conversion refuses the amount
/// instead of converting one it has already changed.
/// @param amount The offending amount.
error AmountNotRepresentableAsFloat(uint256 amount);

/// @notice Thrown when a conversion is asked to use a denomination that is not
/// a positive multiplier.
///
/// Zero is what an UNSET mint limit's stored multiplier reads as, and it is
/// not a denomination: a quantity cannot be expressed in units that were never
/// fixed to an instant, and scaling one INTO a zero denomination would refund
/// the whole of it silently. Negative is unreachable from a well-formed token.
/// Both fail closed, which is the correct direction for a cap.
/// @param denomination The offending multiplier.
error NonPositiveDenomination(Float denomination);

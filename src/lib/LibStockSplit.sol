// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "rain.math.float/lib/LibDecimalFloat.sol";

/// @dev The action type identifier for stock splits.
bytes32 constant ACTION_TYPE_STOCK_SPLIT = keccak256("STOCK_SPLIT");

/// Thrown when a stock split ratio has a zero numerator or denominator.
error ZeroSplitComponent();

/// Thrown when a stock split ratio cannot be represented as a Rain float
/// without precision loss. This rejects ratios that would accumulate
/// unpredictable errors through sequential application.
/// @param numerator The numerator of the rejected ratio.
/// @param denominator The denominator of the rejected ratio.
error LossySplitRatio(uint256 numerator, uint256 denominator);

/// @title LibStockSplit
/// @notice Handles stock split ratio validation and multiplier encoding.
/// A stock split ratio (e.g. 3:2 for a 3-for-2 split) is stored as a Rain
/// float multiplier. The ratio must be exactly representable — lossy ratios
/// are rejected at scheduling time to prevent accumulated precision errors.
library LibStockSplit {
    /// @notice Encode split parameters for storage in a corporate action record.
    /// Validates the ratio and packs it as a Rain float.
    /// @param numerator The split numerator (e.g. 3 for a 3-for-2 split).
    /// @param denominator The split denominator (e.g. 2 for a 3-for-2 split).
    /// @return parameters ABI-encoded parameters containing the float multiplier.
    /// @return multiplier The Rain float multiplier for this split.
    //slither-disable-next-line divide-before-multiply
    function encodeSplitParameters(uint256 numerator, uint256 denominator)
        internal
        pure
        returns (bytes memory parameters, Float multiplier)
    {
        if (numerator == 0 || denominator == 0) {
            revert ZeroSplitComponent();
        }

        // Convert numerator and denominator to floats individually, then
        // divide. This preserves exact fractional representation — 1/3 stays
        // as 1/3 rather than becoming 0.333... in fixed point.
        // Safe: numerator and denominator are validated nonzero above and
        // realistic split ratios are small integers. Overflow of int256 max
        // is not a concern for stock split ratios.
        // forge-lint: disable-next-line(unsafe-typecast)
        Float floatNumerator = LibDecimalFloat.packLossless(int256(numerator), 0);
        // forge-lint: disable-next-line(unsafe-typecast)
        Float floatDenominator = LibDecimalFloat.packLossless(int256(denominator), 0);
        multiplier = LibDecimalFloat.div(floatNumerator, floatDenominator);

        // Verify the multiplier round-trips back to the original ratio.
        // If multiplier * denominator != numerator, the ratio has precision
        // loss in float representation and would accumulate unpredictable
        // errors across sequential application.
        Float reconstructed = LibDecimalFloat.mul(multiplier, floatDenominator);
        if (!LibDecimalFloat.eq(reconstructed, floatNumerator)) {
            revert LossySplitRatio(numerator, denominator);
        }

        parameters = abi.encode(multiplier);
    }

    /// @notice Decode the multiplier from stored corporate action parameters.
    /// @param parameters ABI-encoded parameters from the action record.
    /// @return multiplier The Rain float multiplier.
    function decodeMultiplier(bytes memory parameters) internal pure returns (Float multiplier) {
        multiplier = abi.decode(parameters, (Float));
    }
}

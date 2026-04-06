// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";

/// Thrown when a stock split multiplier is invalid (zero or negative).
error InvalidSplitMultiplier();

/// @title LibStockSplit
/// @notice Validation and encoding for stock split parameters.
library LibStockSplit {
    /// @notice Validate that encoded parameters contain a valid stock split
    /// multiplier. The multiplier must be a positive non-zero Rain float.
    /// @param parameters ABI-encoded Float.
    function validateParameters(bytes memory parameters) internal pure {
        Float multiplier = abi.decode(parameters, (Float));
        (int256 coefficient,) = LibDecimalFloat.unpack(multiplier);
        if (coefficient <= 0) revert InvalidSplitMultiplier();
    }

    /// @notice Encode a stock split multiplier as parameters bytes.
    /// @param multiplier The Rain float multiplier.
    /// @return parameters ABI-encoded Float.
    function encodeParameters(Float multiplier) internal pure returns (bytes memory) {
        return abi.encode(multiplier);
    }

    /// @notice Decode a stock split multiplier from parameters bytes.
    /// @param parameters ABI-encoded Float.
    /// @return multiplier The Rain float multiplier.
    function decodeParameters(bytes memory parameters) internal pure returns (Float) {
        return abi.decode(parameters, (Float));
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
import {LibCorporateAction} from "./LibCorporateAction.sol";

/// @title LibRebase
/// @notice Applies sequential rebase multipliers to a balance. Each multiplier
/// is applied independently in order — they are NOT collapsed into a single
/// cumulative multiplier. This preserves deterministic precision behaviour:
/// 100 × (1/3) × 3 × (1/3) × 3 = 99.999... ≠ 100 × 1 = 100.
library LibRebase {
    /// @notice Calculate the effective balance after applying all multipliers
    /// between two rebase versions. Returns the stored balance unchanged if
    /// no rebases are pending.
    /// @param storedBalance The account's raw stored balance.
    /// @param fromRebaseId The account's current rebase version (exclusive).
    /// @param toRebaseId The target rebase version (inclusive).
    /// @return effectiveBalance The balance after sequential multiplier application.
    function effectiveBalance(uint256 storedBalance, uint256 fromRebaseId, uint256 toRebaseId)
        internal
        view
        returns (uint256)
    {
        if (fromRebaseId >= toRebaseId || storedBalance == 0) {
            return storedBalance;
        }

        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        Float result = LibDecimalFloat.packLossless(int256(storedBalance), 0);

        for (uint256 i = fromRebaseId + 1; i <= toRebaseId; i++) {
            result = LibDecimalFloat.mul(result, s.multipliers[i]);
        }

        // Rasterize back to uint256. The result cannot be negative because
        // we started with a non-negative balance and multiplied by positive
        // multipliers.
        // forge-lint: disable-next-line(unsafe-typecast)
        (uint256 rasterized,) = LibDecimalFloat.toFixedDecimalLossy(result, 0);
        return rasterized;
    }
}

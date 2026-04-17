// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
import {LibTOFUTokenDecimals} from "rain.tofu.erc20-decimals/lib/LibTOFUTokenDecimals.sol";
import {InvalidSplitMultiplier, MultiplierTooSmall, MultiplierTooLarge} from "../error/ErrStockSplit.sol";

/// @title LibStockSplit
/// @notice Validation and encoding for stock split parameters.
library LibStockSplit {
    /// @notice Validate that encoded parameters contain a usable stock split
    /// multiplier. Reads the vault's decimals via the TOFU singleton to scale
    /// the bounds per-token. Under delegatecall from the vault, `address(this)`
    /// resolves to the vault.
    ///
    /// Rules:
    /// 1. Multiplier must be strictly positive — rejects zero and negative
    ///    values (`InvalidSplitMultiplier`).
    /// 2. Multiplier must be at least the value of 1 smallest-unit in Float
    ///    terms (`fromFixedDecimal(1, decimals)` = `10^(-decimals)`) — rejects
    ///    multipliers that would truncate a 1-wei balance to zero on the
    ///    first rebase pass (`MultiplierTooSmall`).
    /// 3. Multiplier must be at most the value of 1 whole token represented
    ///    as a raw smallest-unit count (`fromFixedDecimal(10^decimals, 0)`) —
    ///    rejects near-saturation multipliers that risk overflow on
    ///    sequential application (`MultiplierTooLarge`).
    ///
    /// The bounds are deliberately conservative. The largest historical real
    /// stock split was roughly 1000x (= 1e3), well inside the ceiling, and
    /// the smallest realistic reverse split would be around 1/1000 (= 1e-3),
    /// well above the floor.
    ///
    /// @param parameters ABI-encoded Float.
    function validateParameters(bytes memory parameters) internal {
        Float multiplier = abi.decode(parameters, (Float));

        // Reject zero and negative multipliers.
        if (LibDecimalFloat.lte(multiplier, LibDecimalFloat.FLOAT_ZERO)) {
            revert InvalidSplitMultiplier();
        }

        // TOFU the vault's decimals — snapshot on first call, verify
        // consistency on subsequent calls. `address(this)` is the vault
        // under delegatecall.
        uint8 decimals = LibTOFUTokenDecimals.safeDecimalsForToken(address(this));

        // Floor: one smallest-unit balance in Float terms. Below this, a
        // 1-wei balance truncates to zero on rebase.
        Float floor = LibDecimalFloat.fromFixedDecimalLosslessPacked(1, decimals);
        if (LibDecimalFloat.lt(multiplier, floor)) revert MultiplierTooSmall(multiplier);

        // Ceiling: a 1-whole-token balance's raw smallest-unit count in
        // Float terms (i.e. 10^decimals). Above this risks overflow when
        // applied sequentially.
        Float ceiling = LibDecimalFloat.fromFixedDecimalLosslessPacked(10 ** decimals, 0);
        if (LibDecimalFloat.gt(multiplier, ceiling)) revert MultiplierTooLarge(multiplier);
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

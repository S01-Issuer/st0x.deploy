// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
import {LibTOFUTokenDecimals} from "rain.tofu.erc20-decimals/lib/LibTOFUTokenDecimals.sol";
import {InvalidSplitMultiplier, MultiplierTooSmall, MultiplierTooLarge} from "../error/ErrStockSplit.sol";

/// @title LibStockSplit
/// @notice Validation and parameter codec for stock split actions.
///
/// The `parameters` field on a `CorporateActionNode` is a type-erased `bytes`
/// payload whose schema is chosen per-action-type. This library is the single
/// canonical place where the stock-split schema lives: validators,
/// schedulers, readers, and tests all round-trip through `encodeParametersV1` /
/// `decodeParametersV1` rather than calling `abi.encode` / `abi.decode` at the
/// call site. Two reasons for the centralisation:
///
/// 1. **Decode type safety.** There is no ambient type-checking on
///    `abi.decode(bytes, (T))` — you get whatever schema you ask for, and if
///    the caller picks the wrong one the arithmetic silently corrupts.
///    Routing every decode through `LibStockSplit.decodeParametersV1` makes the
///    call site a single line that cannot mis-specify the schema, and pairs
///    it with the validator that enforces the bounds on the same type.
/// 2. **Schema evolution.** If the stock-split parameter shape ever needs to
///    change (e.g. a new multiplier representation, a bundled record date,
///    etc.), there is exactly one pair of functions to update. Inlining
///    `abi.encode(multiplier)` / `abi.decode(params, (Float))` at each call
///    site would scatter the schema across the codebase and make a coherent
///    schema change a multi-file refactor.
///
/// If a future action type needs its own parameter schema, it gets its own
/// library (e.g. `LibDividend`) with its own `encodeParametersV1` /
/// `decodeParametersV1` / validator trio. The dispatch in
/// `LibCorporateAction.resolveActionType` and the decode in
/// `LibRebase.migratedBalance` route to the right library by action-type bit.
library LibStockSplit {
    /// @notice Validate a stock split multiplier. Reads the vault's decimals
    /// via the TOFU singleton to scale the bounds per-token. Under delegatecall
    /// from the vault, `address(this)` resolves to the vault.
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
    /// @param multiplier The stock split multiplier as a Float.
    function validateMultiplierV1(Float multiplier) internal {
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

    /// @notice Encode a V1 stock split multiplier as the `parameters` payload
    /// for a `CorporateActionNode`. Callers writing to the linked list MUST
    /// route through here rather than calling `abi.encode` directly — see
    /// the library NatSpec for the reason.
    /// @param multiplier The Rain Float multiplier.
    /// @return The ABI-encoded bytes to store as the node's `parameters`.
    function encodeParametersV1(Float multiplier) internal pure returns (bytes memory) {
        return abi.encode(multiplier);
    }

    /// @notice Decode a V1 stock split multiplier from a `parameters` payload.
    /// Callers reading from the linked list MUST route through here rather
    /// than calling `abi.decode` directly — this is the single source of
    /// truth for the V1 stock-split parameter schema.
    /// @param parameters ABI-encoded bytes from a node's `parameters` field.
    /// @return The Rain Float multiplier.
    function decodeParametersV1(bytes memory parameters) internal pure returns (Float) {
        return abi.decode(parameters, (Float));
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {TokenConfig} from "./LibProdTokenConfig.sol";
import {ST0X_NAME_SUFFIX} from "./LibSecurity.sol";

/// @notice The state a production token's ERC-20 metadata is in.
/// - `Initialized`: the receipt vault holds the `TokenConfig.name` /
///   `TokenConfig.symbol` it was initialized with, and the wrapper derives
///   `"Wrapped " + name` / `"w" + symbol` (e.g. `wtNVDA`).
/// - `Listed`: the receipt vault was initialized with `StoxTokenConfigV1`, so
///   it reads `listingName + " (ST0x)"` / `"t" + listingTicker`, and the
///   wrapper reads the receipt vault's name / `listingTicker + "s"`.
/// - `Renamed`: after `setUnderlying(underlying, underlyingName)`, the
///   receipt vault reads `underlyingName + " (ST0x)"` / `"t" + underlying`,
///   and the wrapper reads `underlyingName + " (ST0x)"` /
///   `underlying + "s"` (e.g. `NVDAs`).
enum TokenMetadataState {
    Initialized,
    Listed,
    Renamed
}

/// @title LibTokenMetadata
/// @notice The ERC-20 metadata a production token's receipt vault and
/// wrapper carry, in each `TokenMetadataState`.
library LibTokenMetadata {
    /// @notice The receipt vault's decimals: its asset is offchain
    /// (`address(0)`), so `ReceiptVault.decimals()` falls back to the ERC-20
    /// default.
    uint8 internal constant RECEIPT_VAULT_DECIMALS = 18;

    /// @notice The wrapper's decimals: ERC-4626 adds a zero
    /// `_decimalsOffset()` to its asset's, the receipt vault.
    uint8 internal constant WRAPPED_TOKEN_VAULT_DECIMALS = RECEIPT_VAULT_DECIMALS;

    /// @notice The receipt vault's and the wrapper's name once renamed.
    /// @param config The token's row.
    /// @return The renamed name.
    function renamedName(TokenConfig memory config) internal pure returns (string memory) {
        return string.concat(config.underlyingName, ST0X_NAME_SUFFIX);
    }

    /// @notice The wrapper's symbol once renamed.
    /// @param config The token's row.
    /// @return The renamed wrapper symbol.
    function renamedWrappedSymbol(TokenConfig memory config) internal pure returns (string memory) {
        return string.concat(config.underlying, "s");
    }

    /// @notice The receipt vault's name in the given state.
    /// @param config The token's row.
    /// @param state The token's metadata state.
    /// @return The vault name.
    function vaultName(TokenConfig memory config, TokenMetadataState state) internal pure returns (string memory) {
        if (state == TokenMetadataState.Renamed) return renamedName(config);
        if (state == TokenMetadataState.Listed) return string.concat(config.listingName, ST0X_NAME_SUFFIX);
        return config.name;
    }

    /// @notice The receipt vault's symbol in the given state.
    /// @param config The token's row.
    /// @param state The token's metadata state.
    /// @return The vault symbol.
    function vaultSymbol(TokenConfig memory config, TokenMetadataState state) internal pure returns (string memory) {
        if (state == TokenMetadataState.Renamed) return string.concat("t", config.underlying);
        if (state == TokenMetadataState.Listed) return string.concat("t", config.listingTicker);
        return config.symbol;
    }

    /// @notice The wrapper's name in the given state.
    /// @param config The token's row.
    /// @param state The token's metadata state.
    /// @return The wrapper name.
    function wrappedName(TokenConfig memory config, TokenMetadataState state) internal pure returns (string memory) {
        if (state == TokenMetadataState.Initialized) return string.concat("Wrapped ", config.name);
        return vaultName(config, state);
    }

    /// @notice The wrapper's symbol in the given state.
    /// @param config The token's row.
    /// @param state The token's metadata state.
    /// @return The wrapper symbol.
    function wrappedSymbol(TokenConfig memory config, TokenMetadataState state) internal pure returns (string memory) {
        if (state == TokenMetadataState.Renamed) return renamedWrappedSymbol(config);
        if (state == TokenMetadataState.Listed) return string.concat(config.listingTicker, "s");
        return string.concat("w", config.symbol);
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {TokenConfig} from "./LibProdTokenConfig.sol";
import {ST0X_NAME_SUFFIX} from "./LibUnderlying.sol";

/// @title LibTokenMetadata
/// @notice The ERC-20 metadata a production token's receipt vault and
/// wrapper carry, in either of its two states.
///
/// - **Initialized**: the receipt vault holds the `TokenConfig.name` /
///   `TokenConfig.symbol` it was initialized with, and the wrapper derives
///   `"Wrapped " + name` / `"w" + symbol` (e.g. `wtNVDA`).
/// - **Renamed**: after `setUnderlying(underlying, underlyingName)`, the
///   receipt vault reads `underlyingName + " (ST0x)"` / `"t" + underlying`,
///   and the wrapper reads `underlyingName + " (ST0x)"` /
///   `underlying + "s"` (e.g. `NVDAs`).
///
/// The receipt vault's symbol is `"t" + underlying` in both states.
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
    /// @param renamed Whether the token is renamed.
    /// @return The vault name.
    function vaultName(TokenConfig memory config, bool renamed) internal pure returns (string memory) {
        return renamed ? renamedName(config) : config.name;
    }

    /// @notice The wrapper's name in the given state.
    /// @param config The token's row.
    /// @param renamed Whether the token is renamed.
    /// @return The wrapper name.
    function wrappedName(TokenConfig memory config, bool renamed) internal pure returns (string memory) {
        return renamed ? renamedName(config) : string.concat("Wrapped ", config.name);
    }

    /// @notice The wrapper's symbol in the given state.
    /// @param config The token's row.
    /// @param renamed Whether the token is renamed.
    /// @return The wrapper symbol.
    function wrappedSymbol(TokenConfig memory config, bool renamed) internal pure returns (string memory) {
        return renamed ? renamedWrappedSymbol(config) : string.concat("w", config.symbol);
    }

    /// @notice Whether the receipt vault's name is the renamed one. In the
    /// initialized state it is `TokenConfig.name`, which never equals the
    /// renamed name: it carries the `" ST0x"` suffix, not `" (ST0x)"`.
    /// @param config The token's row.
    /// @param liveVaultName The receipt vault's live `name()`.
    /// @return Whether the vault is renamed.
    function vaultRenamed(TokenConfig memory config, string memory liveVaultName) internal pure returns (bool) {
        return eq(liveVaultName, renamedName(config));
    }

    /// @notice Whether the four live values are exactly one of the two
    /// states, with the receipt vault and the wrapper in the same state.
    /// @param config The token's row.
    /// @param liveVaultName The receipt vault's live `name()`.
    /// @param liveVaultSymbol The receipt vault's live `symbol()`.
    /// @param liveWrappedName The wrapper's live `name()`.
    /// @param liveWrappedSymbol The wrapper's live `symbol()`.
    /// @return Whether the metadata is consistent.
    function consistent(
        TokenConfig memory config,
        string memory liveVaultName,
        string memory liveVaultSymbol,
        string memory liveWrappedName,
        string memory liveWrappedSymbol
    ) internal pure returns (bool) {
        if (!eq(liveVaultSymbol, config.symbol)) return false;
        bool renamed = vaultRenamed(config, liveVaultName);
        return eq(liveVaultName, vaultName(config, renamed)) && eq(liveWrappedName, wrappedName(config, renamed))
            && eq(liveWrappedSymbol, wrappedSymbol(config, renamed));
    }

    /// @notice String equality.
    /// @param a A string.
    /// @param b Another string.
    /// @return Whether they are equal.
    function eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {ST0X_NAME_SUFFIX} from "../../src/lib/LibUnderlying.sol";

/// @title LibTestTokenMetadata
/// @notice The two ERC-20 metadata states a production token can be in on a
/// live chain, for the live-fork pins. The underlying-naming rollout renames
/// one chain at a time, so a live fork can show either state, and a chain can
/// be renamed while another is not.
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
library LibTestTokenMetadata {
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

    /// @notice Whether the receipt vault's name is the renamed one. In the
    /// initialized state it is `TokenConfig.name`, which never equals the
    /// renamed name: it carries the `" ST0x"` suffix, not `" (ST0x)"`.
    /// @param config The token's row.
    /// @param vaultName The receipt vault's live `name()`.
    /// @return Whether the vault is renamed.
    function vaultRenamed(TokenConfig memory config, string memory vaultName) internal pure returns (bool) {
        return eq(vaultName, renamedName(config));
    }

    /// @notice Whether the four live values are exactly one of the two
    /// states, with the receipt vault and the wrapper in the same state.
    /// @param config The token's row.
    /// @param vaultName The receipt vault's live `name()`.
    /// @param vaultSymbol The receipt vault's live `symbol()`.
    /// @param wrappedName The wrapper's live `name()`.
    /// @param wrappedSymbol The wrapper's live `symbol()`.
    /// @return Whether the metadata is consistent.
    function consistent(
        TokenConfig memory config,
        string memory vaultName,
        string memory vaultSymbol,
        string memory wrappedName,
        string memory wrappedSymbol
    ) internal pure returns (bool) {
        if (!eq(vaultSymbol, config.symbol)) return false;
        if (vaultRenamed(config, vaultName)) {
            return eq(wrappedName, renamedName(config)) && eq(wrappedSymbol, renamedWrappedSymbol(config));
        }
        return eq(vaultName, config.name) && eq(wrappedName, string.concat("Wrapped ", config.name))
            && eq(wrappedSymbol, string.concat("w", config.symbol));
    }

    /// @notice String equality.
    /// @param a A string.
    /// @param b Another string.
    /// @return Whether they are equal.
    function eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}

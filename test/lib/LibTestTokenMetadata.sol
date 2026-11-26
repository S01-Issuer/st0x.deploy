// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {LibTokenMetadata, TokenMetadataState} from "../../src/lib/LibTokenMetadata.sol";

/// @title LibTestTokenMetadata
/// @notice Judges live name/symbol values against the states
/// `LibTokenMetadata` derives.
library LibTestTokenMetadata {
    /// @notice Whether the receipt vault's name is the renamed one. In the
    /// initialized state it is `TokenConfig.name`, which never equals the
    /// renamed name: it carries the `" ST0x"` suffix, not `" (ST0x)"`.
    /// @param config The token's row.
    /// @param liveVaultName The receipt vault's live `name()`.
    /// @return Whether the vault is renamed.
    function vaultRenamed(TokenConfig memory config, string memory liveVaultName) internal pure returns (bool) {
        return eq(liveVaultName, LibTokenMetadata.renamedName(config));
    }

    /// @notice Whether the four live values are one
    /// `TokenMetadataState`, with the receipt vault and the wrapper in the
    /// same state.
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
        for (uint256 stateIndex = 0; stateIndex <= uint256(type(TokenMetadataState).max); stateIndex++) {
            TokenMetadataState state = TokenMetadataState(stateIndex);
            if (
                eq(liveVaultName, LibTokenMetadata.vaultName(config, state))
                    && eq(liveVaultSymbol, LibTokenMetadata.vaultSymbol(config, state))
                    && eq(liveWrappedName, LibTokenMetadata.wrappedName(config, state))
                    && eq(liveWrappedSymbol, LibTokenMetadata.wrappedSymbol(config, state))
            ) return true;
        }
        return false;
    }

    /// @notice String equality.
    /// @param a A string.
    /// @param b Another string.
    /// @return Whether they are equal.
    function eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}

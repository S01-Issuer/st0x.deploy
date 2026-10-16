// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev ERC-7201 namespaced storage location for the underlying asset's
/// identity, derived in-source from the spec formula rather than hardcoded.
/// Evaluated at compile time, zero runtime cost.
bytes32 constant UNDERLYING_STORAGE_LOCATION =
    keccak256(abi.encode(uint256(keccak256("rain.storage.underlying.1")) - 1)) & ~bytes32(uint256(0xff));

/// @dev Appended to the underlying name to form the ERC-20 `name()` of every
/// ST0x token built from it, e.g. "NVIDIA Corporation" + " (ST0x)".
string constant ST0X_NAME_SUFFIX = " (ST0x)";

/// @title LibUnderlying
/// @notice Storage for the ticker and name of the off-chain asset a
/// `StoxReceiptVault` tokenizes. The vault's own ERC-20 `symbol()` / `name()`
/// and the wrapping `StoxWrappedTokenVault`'s `symbol()` / `name()` are all
/// built from these two values, so neither is ever recovered by trimming
/// another token's string.
library LibUnderlying {
    /// @custom:storage-location erc7201:rain.storage.underlying.1
    /// @dev **DO NOT REORDER — APPEND ONLY.** This struct lives at a fixed
    /// ERC-7201 namespaced slot inside an upgradeable beacon-proxy vault, so
    /// field offsets are positional. New state may only be added at the end
    /// of the struct.
    /// @param symbol The underlying ticker, e.g. "NVDA". Empty when unset.
    /// @param name The underlying asset's name, e.g. "NVIDIA Corporation".
    /// Empty when unset.
    struct UnderlyingStorage {
        string symbol;
        string name;
    }

    /// @notice Accessor for the underlying identity storage.
    /// @return s Storage reference to the `UnderlyingStorage` struct.
    function getStorage() internal pure returns (UnderlyingStorage storage s) {
        bytes32 position = UNDERLYING_STORAGE_LOCATION;
        assembly ("memory-safe") {
            s.slot := position
        }
    }
}

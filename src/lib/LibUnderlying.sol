// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev ERC-7201 namespaced storage location for the underlying asset's
/// identity, derived in-source from the spec formula rather than hardcoded.
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

    /// @notice Whether `ticker` is 1 to 16 bytes of `A-Z`, `0-9` and `.`.
    /// @param ticker The ticker.
    /// @return Whether it is well formed.
    function tickerWellFormed(bytes memory ticker) internal pure returns (bool) {
        if (ticker.length == 0 || ticker.length > 16) return false;
        for (uint256 i = 0; i < ticker.length; i++) {
            bytes1 c = ticker[i];
            if (!((c >= "A" && c <= "Z") || (c >= "0" && c <= "9") || c == ".")) return false;
        }
        return true;
    }

    /// @notice Whether `name` is non-empty, has no `"`, `\` or control byte,
    /// and does not end in "ST0x" or "(ST0x)".
    /// @param name The underlying name.
    /// @return Whether it is well formed.
    function nameWellFormed(bytes memory name) internal pure returns (bool) {
        if (name.length == 0) return false;
        for (uint256 i = 0; i < name.length; i++) {
            bytes1 c = name[i];
            if (c < 0x20 || c == 0x7f || c == '"' || c == "\\") return false;
        }
        return !endsWith(name, "ST0x") && !endsWith(name, "(ST0x)");
    }

    /// @notice Whether `value` ends with `suffix`.
    /// @param value The value.
    /// @param suffix The suffix.
    /// @return Whether it does.
    function endsWith(bytes memory value, bytes memory suffix) internal pure returns (bool) {
        if (value.length < suffix.length) return false;
        uint256 offset = value.length - suffix.length;
        for (uint256 i = 0; i < suffix.length; i++) {
            if (value[offset + i] != suffix[i]) return false;
        }
        return true;
    }
}

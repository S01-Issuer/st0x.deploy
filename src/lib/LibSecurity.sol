// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibAffix} from "rain-string-0.3.11/src/lib/affix/LibAffix.sol";
import {LibParseChar} from "rain-string-0.3.11/src/lib/parse/LibParseChar.sol";
import {
    CMASK_ASCII,
    CMASK_BACKSLASH,
    CMASK_FULL_STOP,
    CMASK_NUMERIC_0_9,
    CMASK_PRINTABLE,
    CMASK_QUOTATION_MARK,
    CMASK_UPPER_ALPHA_A_Z
} from "rain-string-0.3.11/src/lib/parse/LibParseCMask.sol";
import {LibBytes} from "rain-solmem-0.1.28/src/lib/LibBytes.sol";
import {Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";

/// @dev ERC-7201 namespaced storage location for the underlying asset's
/// identity, derived in-source from the spec formula rather than hardcoded.
bytes32 constant UNDERLYING_STORAGE_LOCATION =
    keccak256(abi.encode(uint256(keccak256("rain.storage.underlying.1")) - 1)) & ~bytes32(uint256(0xff));

/// @dev Appended to the underlying name to form the ERC-20 `name()` of every
/// ST0x token built from it, e.g. "NVIDIA Corporation" + " (ST0x)".
string constant ST0X_NAME_SUFFIX = " (ST0x)";

/// @dev Prepended to the underlying ticker to form the receipt vault's
/// `symbol()`, e.g. "t" + "NVDA".
string constant ST0X_SYMBOL_PREFIX = "t";

/// @title LibSecurity
/// @notice Storage for a token's underlying override: ticker, name, ISIN and
/// the `block.timestamp` it was set at, which
/// `StoxCorporateActionsFacet.resolveUnderlying` weighs against the snapshot.
library LibSecurity {
    /// @custom:storage-location erc7201:rain.storage.underlying.1
    /// @dev **DO NOT REORDER — APPEND ONLY.** This struct lives at a fixed
    /// ERC-7201 namespaced slot inside an upgradeable beacon-proxy vault, so
    /// field offsets are positional. New state may only be added at the end
    /// of the struct.
    /// @param symbol The underlying ticker, e.g. "NVDA". Empty when unset.
    /// @param name The underlying asset's name, e.g. "NVIDIA Corporation".
    /// Empty when unset.
    /// @param isin The underlying asset's current ISIN. Empty when unset.
    /// @param timestamp The `block.timestamp` of the last `setUnderlying`.
    /// Zero when unset.
    struct UnderlyingStorage {
        string symbol;
        string name;
        string isin;
        uint256 timestamp;
    }

    /// @notice Accessor for the underlying identity storage.
    /// @return s Storage reference to the `UnderlyingStorage` struct.
    function getStorage() internal pure returns (UnderlyingStorage storage s) {
        bytes32 position = UNDERLYING_STORAGE_LOCATION;
        assembly ("memory-safe") {
            s.slot := position
        }
    }

    /// @notice The receipt vault's `symbol()` for `ticker`.
    function vaultSymbol(string memory ticker) internal pure returns (string memory) {
        return string.concat(ST0X_SYMBOL_PREFIX, ticker);
    }

    /// @notice The receipt vault's `name()` for `name`.
    function vaultName(string memory name) internal pure returns (string memory) {
        return string.concat(name, ST0X_NAME_SUFFIX);
    }

    /// @notice Whether `ticker` is 1 to 16 bytes of `A-Z`, `0-9` and `.`.
    /// @param ticker The ticker.
    /// @return Whether it is well formed.
    function tickerWellFormed(bytes memory ticker) internal pure returns (bool) {
        if (ticker.length == 0 || ticker.length > 16) return false;
        uint256 end = Pointer.unwrap(LibBytes.endDataPointer(ticker));
        return LibParseChar.skipMask(
            Pointer.unwrap(LibBytes.dataPointer(ticker)),
            end,
            CMASK_UPPER_ALPHA_A_Z | CMASK_NUMERIC_0_9 | CMASK_FULL_STOP
        ) == end;
    }

    /// @notice Whether `name` is non-empty, has no `"`, `\` or control byte,
    /// and does not end in "ST0x" or "(ST0x)".
    /// @param name The underlying name.
    /// @return Whether it is well formed.
    function nameWellFormed(bytes memory name) internal pure returns (bool) {
        if (name.length == 0) return false;
        uint256 end = Pointer.unwrap(LibBytes.endDataPointer(name));
        return LibParseChar.skipMask(
                Pointer.unwrap(LibBytes.dataPointer(name)),
                end,
                ~((CMASK_ASCII & ~CMASK_PRINTABLE) | CMASK_QUOTATION_MARK | CMASK_BACKSLASH)
            ) == end && !LibAffix.endsWith(name, "ST0x") && !LibAffix.endsWith(name, "(ST0x)");
    }

    /// @notice Whether `isin` is 2 of `A-Z`, 9 of `A-Z` and `0-9`, then a
    /// digit that passes the Luhn check over the letters expanded to
    /// `A` = 10 … `Z` = 35.
    /// @param isin The ISIN.
    /// @return Whether it is well formed.
    function isinWellFormed(string memory isin) internal pure returns (bool) {
        bytes memory value = bytes(isin);
        if (value.length != 12) return false;
        uint256 sum = 0;
        bool doubled = false;
        for (uint256 i = value.length; i > 0; i--) {
            uint8 c = uint8(value[i - 1]);
            uint256 code;
            if ((uint256(1) << c) & CMASK_NUMERIC_0_9 != 0) {
                if (i <= 2) return false;
                code = c - 0x30;
            } else if ((uint256(1) << c) & CMASK_UPPER_ALPHA_A_Z != 0) {
                if (i == value.length) return false;
                code = c - 0x41 + 10;
            } else {
                return false;
            }
            do {
                uint256 digit = code % 10;
                code /= 10;
                if (doubled) {
                    digit *= 2;
                    if (digit > 9) digit -= 9;
                }
                sum += digit;
                doubled = !doubled;
            } while (code > 0);
        }
        return sum % 10 == 0;
    }
}

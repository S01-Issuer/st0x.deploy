// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Bytes} from "@openzeppelin-contracts-5.7.0/utils/Bytes.sol";
import {Strings} from "@openzeppelin-contracts-5.7.0/utils/Strings.sol";
import {LibSafeInvariants} from "./LibSafeInvariants.sol";
import {LibUtcDate} from "./LibUtcDate.sol";

/// @notice The metadata file has no `primary_ticker`.
error MissingPrimaryTicker();

/// @notice `primary_ticker` holds a character other than an ASCII letter,
/// digit, `.` or `-`. The symbol names the launch's files and is passed to the
/// workflow's shell, so nothing else is accepted.
error InvalidTicker(string ticker);

/// @notice `asset_type` is neither `Equity` nor `ETF`.
error UnsupportedAssetType(string assetType);

/// @notice The metadata file has no `name`.
error MissingName();

/// @notice `name` holds Unicode whitespace, which JavaScript's `trim()` and
/// `\s` in sft-ops match but this port does not. The name is permanent once
/// deployed, so it is refused rather than normalised differently.
error UnicodeWhitespaceInName(string name);

/// @notice `name` is the ticker or the token symbol, not the asset name: the
/// tQQQM/tVWO/tARKK redeploys.
error NameIsTicker(string name);

/// @notice `country.iso` is not a two-letter upper-case code.
error InvalidCountryIso(string iso);

/// @notice The ISIN is missing or malformed.
error InvalidIsin(string isin);

/// @notice `offchain_counterparties` is neither the US set nor the non-US set.
/// Files written before 2026-08-19 carry the retired set and are not
/// backfilled.
error InvalidCounterparties();

/// @notice The production owner Safe is not allowlisted with role `owner`.
error OwnerNotAllowlisted(address owner);

/// @notice A dedicated-authoriser pin names a chain other than Base.
error DedicatedPinWrongChain(string symbol, uint256 chainId);

/// @notice The pinned dedicated authoriser is missing, malformed, mis-checksummed
/// or the zero placeholder.
error DedicatedAuthoriserUnset(string symbol, string authoriser);

/// @notice The pinned dedicated authoriser is the shared authoriser.
error DedicatedAuthoriserIsShared(string symbol);

/// @notice The pinned dedicated minter is missing, malformed, mis-checksummed or
/// zero.
error DedicatedMinterUnset(string symbol, string minter);

/// @notice The pin has no positive integer `deployBlock`, so the role history
/// of the dedicated authoriser cannot be replayed.
error DedicatedDeployBlockUnset(string symbol);

/// @notice The pinned dedicated authoriser is not allowlisted with role
/// `authorizer` on Base.
error DedicatedAuthoriserNotAllowlisted(string symbol, address authoriser);

/// @notice The asset class, which selects the schema the vault is described
/// with.
enum AssetType {
    Equity,
    Etf
}

/// @notice The fields of a `launch/metadata/<ticker>.json` file the plan reads.
/// A missing field is the empty string.
struct LaunchMetadata {
    string primaryTicker;
    string assetType;
    string name;
    string countryIso;
    string isin;
    string[] counterparties;
}

/// @notice One row of `launch/dedicated-authorisers.json`. Addresses stay
/// strings so their checksum can be validated. `deployBlock` is zero when the
/// field is missing or not a positive integer.
struct DedicatedPin {
    string symbol;
    uint256 chainId;
    string authoriser;
    string minter;
    uint256 deployBlock;
    bool minterGrantPending;
}

/// @notice Everything outside the metadata file that the plan depends on.
/// @param shippedSymbols Lower-cased symbols that must not be launched again.
/// @param allowlistedOwners Addresses allowlisted with role `owner`, any chain.
/// @param allowlistedAuthorisers Addresses allowlisted with role `authorizer`
/// on Base.
/// @param pins The dedicated-authoriser pins.
/// @param ownerSafe The production owner every token is handed to.
/// @param sharedAuthoriser The authoriser an unpinned token lands on.
/// @param now Unix seconds the certification year is counted from.
struct PlanContext {
    string[] shippedSymbols;
    address[] allowlistedOwners;
    address[] allowlistedAuthorisers;
    DedicatedPin[] pins;
    address ownerSafe;
    address sharedAuthoriser;
    uint256 now;
}

/// @notice The launch arguments derived from one metadata file.
struct TokenPlan {
    string metadataFile;
    string symbol;
    string name;
    AssetType assetType;
    uint256 certifyUntil;
    address intendedOwner;
    address landingAuthoriser;
    bool dedicated;
    address dedicatedMinter;
    uint256 dedicatedDeployBlock;
    bool dedicatedMinterGrantPending;
}

/// @title LibLaunchPlan
/// @notice The checks sft-ops `cd-plan` makes before a Base token launch, and
/// the launch arguments it derives from a metadata file.
library LibLaunchPlan {
    uint256 internal constant CERTIFY_YEARS = 1;

    /// @notice Plan one metadata file.
    /// @param metadataFile The path the metadata was read from.
    /// @param metadata The fields read from that file.
    /// @param ctx The ledger, allowlist, pins, owner and clock.
    /// @return skipped True when the symbol has already shipped or was retired:
    /// editing the metadata of a live token must never launch it again.
    /// @return plan The derived launch arguments; only `symbol` is set when
    /// skipped.
    function planOne(string memory metadataFile, LaunchMetadata memory metadata, PlanContext memory ctx)
        internal
        pure
        returns (bool skipped, TokenPlan memory plan)
    {
        string memory ticker = trim(metadata.primaryTicker);
        if (bytes(ticker).length == 0) revert MissingPrimaryTicker();
        if (!isTicker(ticker)) revert InvalidTicker(ticker);

        plan.symbol = string.concat("t", toUpper(ticker));
        skipped = contains(ctx.shippedSymbols, toLower(plan.symbol));
        if (skipped) return (skipped, plan);

        plan.assetType = parseAssetType(metadata.assetType);
        plan.name = string.concat(normaliseAdrName(checkName(metadata.name, ticker, plan.symbol)), " ST0x");

        string memory iso = trim(metadata.countryIso);
        if (!isCountryIso(iso)) revert InvalidCountryIso(iso);

        string memory isin = toUpper(trim(metadata.isin));
        if (!isIsin(isin)) revert InvalidIsin(isin);

        if (!isAllowedCounterpartySet(metadata.counterparties)) revert InvalidCounterparties();

        if (!containsAddress(ctx.allowlistedOwners, ctx.ownerSafe)) revert OwnerNotAllowlisted(ctx.ownerSafe);

        plan.metadataFile = metadataFile;
        plan.certifyUntil = LibUtcDate.addYearsUtc(ctx.now, CERTIFY_YEARS);
        plan.intendedOwner = ctx.ownerSafe;
        plan.landingAuthoriser = ctx.sharedAuthoriser;

        (bool pinned, DedicatedPin memory pin) = findPin(ctx.pins, plan.symbol);
        if (pinned) {
            (plan.landingAuthoriser, plan.dedicatedMinter) = checkPin(pin, plan.symbol, ctx);
            plan.dedicated = true;
            plan.dedicatedDeployBlock = pin.deployBlock;
            plan.dedicatedMinterGrantPending = pin.minterGrantPending;
        }
    }

    /// @notice The asset class named by `asset_type`, which must be exactly
    /// `Equity` or `ETF` after trimming.
    /// @param assetType The `asset_type` field.
    /// @return The asset class.
    function parseAssetType(string memory assetType) internal pure returns (AssetType) {
        string memory trimmed = trim(assetType);
        if (Strings.equal(trimmed, "Equity")) return AssetType.Equity;
        if (Strings.equal(trimmed, "ETF")) return AssetType.Etf;
        revert UnsupportedAssetType(trimmed);
    }

    /// @notice The trimmed name, which must be present, must hold no Unicode
    /// whitespace and must not be the ticker or the symbol.
    /// @param name The `name` field.
    /// @param ticker The trimmed ticker.
    /// @param symbol The derived symbol.
    /// @return The trimmed name.
    function checkName(string memory name, string memory ticker, string memory symbol)
        internal
        pure
        returns (string memory)
    {
        string memory trimmed = trim(name);
        if (bytes(trimmed).length == 0) revert MissingName();
        if (_hasUnicodeSpace(bytes(trimmed))) revert UnicodeWhitespaceInName(trimmed);
        string memory lowered = toLower(trimmed);
        if (Strings.equal(lowered, toLower(symbol)) || Strings.equal(lowered, toLower(ticker))) {
            revert NameIsTicker(trimmed);
        }
        return trimmed;
    }

    /// @notice A pinned token lands only on its own allowlisted authoriser.
    /// Every failure is a refusal, never a fall-back to the shared authoriser.
    /// @param pin The pin found for `symbol`.
    /// @param symbol The derived symbol.
    /// @param ctx The shared authoriser and the authoriser allowlist.
    /// @return authoriser The dedicated authoriser.
    /// @return minter The dedicated minter.
    function checkPin(DedicatedPin memory pin, string memory symbol, PlanContext memory ctx)
        internal
        pure
        returns (address authoriser, address minter)
    {
        if (pin.chainId != LibSafeInvariants.BASE_CHAIN_ID) revert DedicatedPinWrongChain(symbol, pin.chainId);

        bool authoriserSet;
        (authoriserSet, authoriser) = parseSetAddress(pin.authoriser);
        if (!authoriserSet) revert DedicatedAuthoriserUnset(symbol, pin.authoriser);
        if (authoriser == ctx.sharedAuthoriser) revert DedicatedAuthoriserIsShared(symbol);

        bool minterSet;
        (minterSet, minter) = parseSetAddress(pin.minter);
        if (!minterSet) revert DedicatedMinterUnset(symbol, pin.minter);

        if (pin.deployBlock == 0) revert DedicatedDeployBlockUnset(symbol);

        if (!containsAddress(ctx.allowlistedAuthorisers, authoriser)) {
            revert DedicatedAuthoriserNotAllowlisted(symbol, authoriser);
        }
    }

    /// @notice The first pin whose key matches `symbol` case-insensitively.
    /// @param pins The dedicated-authoriser pins.
    /// @param symbol The derived symbol.
    /// @return found Whether a pin matched.
    /// @return pin The matching pin, empty when none matched.
    function findPin(DedicatedPin[] memory pins, string memory symbol)
        internal
        pure
        returns (bool found, DedicatedPin memory pin)
    {
        string memory target = toLower(symbol);
        for (uint256 i = 0; i < pins.length && !found; i++) {
            found = Strings.equal(toLower(pins[i].symbol), target);
            if (found) pin = pins[i];
        }
    }

    /// @notice Parse a `0x`-prefixed address the way viem's `isAddress` accepts
    /// it: forty hex digits, either all lower case or exactly EIP-55. The zero
    /// address counts as unset.
    /// @param value The address text.
    /// @return ok Whether `value` is a set, well-formed address.
    /// @return parsed The address, zero when not set.
    function parseSetAddress(string memory value) internal pure returns (bool ok, address parsed) {
        // `tryParseAddress` takes 42 bytes only with a lower-case `0x` prefix.
        if (bytes(value).length != 42) return (ok, parsed);
        (ok, parsed) = Strings.tryParseAddress(value);
        ok = ok && parsed != address(0)
            && (Strings.equal(toLower(value), value) || Strings.equal(Strings.toChecksumHexString(parsed), value));
        if (!ok) parsed = address(0);
    }

    /// @notice `(ADR)` and `(ADS)` become `ADR` and `ADS`, runs of two or more
    /// whitespace characters become one space, and the ends are trimmed: both
    /// `Foo Limited (ADR)` and `Foo Limited ADR` name the same token.
    /// @param name The trimmed name.
    /// @return The normalised name.
    function normaliseAdrName(string memory name) internal pure returns (string memory) {
        bytes memory nameBytes = bytes(name);
        bytes memory unwrapped = new bytes(nameBytes.length);
        uint256 unwrappedLength = 0;
        for (uint256 i = 0; i < nameBytes.length; i++) {
            if (
                nameBytes[i] == "(" && i + 4 < nameBytes.length && nameBytes[i + 4] == ")"
                    && _isAdrOrAds(nameBytes, i + 1)
            ) {
                unwrapped[unwrappedLength++] = nameBytes[i + 1];
                unwrapped[unwrappedLength++] = nameBytes[i + 2];
                unwrapped[unwrappedLength++] = nameBytes[i + 3];
                i += 4;
            } else {
                unwrapped[unwrappedLength++] = nameBytes[i];
            }
        }

        bytes memory collapsed = new bytes(unwrappedLength);
        uint256 collapsedLength = 0;
        for (uint256 i = 0; i < unwrappedLength; i++) {
            if (_isSpace(unwrapped[i]) && i + 1 < unwrappedLength && _isSpace(unwrapped[i + 1])) {
                while (i + 1 < unwrappedLength && _isSpace(unwrapped[i + 1])) {
                    i++;
                }
                collapsed[collapsedLength++] = " ";
            } else {
                collapsed[collapsedLength++] = unwrapped[i];
            }
        }
        assembly ("memory-safe") {
            mstore(collapsed, collapsedLength)
        }
        return trim(string(collapsed));
    }

    /// @notice The counterparty names, in any order, are exactly the US set
    /// (`AlpacaDB Inc`, `Clear Street LLC`) or the non-US set, which adds
    /// `Freedom Finance`.
    /// @param names The counterparty names.
    /// @return Whether the names form one of the two sets.
    function isAllowedCounterpartySet(string[] memory names) internal pure returns (bool) {
        string[] memory sorted = sortStrings(names);
        if (sorted.length == 2) {
            return Strings.equal(sorted[0], "AlpacaDB Inc") && Strings.equal(sorted[1], "Clear Street LLC");
        }
        if (sorted.length == 3) {
            return Strings.equal(sorted[0], "AlpacaDB Inc") && Strings.equal(sorted[1], "Clear Street LLC")
                && Strings.equal(sorted[2], "Freedom Finance");
        }
        return false;
    }

    /// @notice Only ASCII letters, digits, `.` and `-`.
    /// @param ticker The trimmed ticker.
    /// @return Whether every character is allowed.
    function isTicker(string memory ticker) internal pure returns (bool) {
        bytes memory tickerBytes = bytes(ticker);
        for (uint256 i = 0; i < tickerBytes.length; i++) {
            bytes1 char = tickerBytes[i];
            if (!_isUpper(char) && !_isLower(char) && !_isDigit(char) && char != "." && char != "-") return false;
        }
        return true;
    }

    /// @notice Two upper-case ASCII letters.
    /// @param iso The trimmed `country.iso`.
    /// @return Whether `iso` is a country code.
    function isCountryIso(string memory iso) internal pure returns (bool) {
        bytes memory isoBytes = bytes(iso);
        return isoBytes.length == 2 && _isUpper(isoBytes[0]) && _isUpper(isoBytes[1]);
    }

    /// @notice `^[A-Z]{2}[A-Z0-9]{9}[0-9]$`.
    /// @param isin The trimmed, upper-cased ISIN.
    /// @return Whether `isin` has the ISIN shape.
    function isIsin(string memory isin) internal pure returns (bool) {
        bytes memory isinBytes = bytes(isin);
        if (isinBytes.length != 12 || !_isUpper(isinBytes[0]) || !_isUpper(isinBytes[1]) || !_isDigit(isinBytes[11])) {
            return false;
        }
        for (uint256 i = 2; i < 11; i++) {
            if (!_isUpper(isinBytes[i]) && !_isDigit(isinBytes[i])) return false;
        }
        return true;
    }

    /// @notice Exact, case-sensitive membership.
    /// @param values The strings to search.
    /// @param value The string to find.
    /// @return Whether `values` holds `value`.
    function contains(string[] memory values, string memory value) internal pure returns (bool) {
        for (uint256 i = 0; i < values.length; i++) {
            if (Strings.equal(values[i], value)) return true;
        }
        return false;
    }

    /// @notice Exact membership.
    /// @param values The addresses to search.
    /// @param value The address to find.
    /// @return Whether `values` holds `value`.
    function containsAddress(address[] memory values, address value) internal pure returns (bool) {
        for (uint256 i = 0; i < values.length; i++) {
            if (values[i] == value) return true;
        }
        return false;
    }

    /// @notice A sorted copy, by byte order: JavaScript's default sort for the
    /// ASCII names compared here.
    /// @param values The strings to sort.
    /// @return The sorted copy.
    function sortStrings(string[] memory values) internal pure returns (string[] memory) {
        string[] memory sorted = new string[](values.length);
        for (uint256 i = 0; i < values.length; i++) {
            sorted[i] = values[i];
            for (uint256 j = i; j > 0 && _lessThan(sorted[j], sorted[j - 1]); j--) {
                (sorted[j], sorted[j - 1]) = (sorted[j - 1], sorted[j]);
            }
        }
        return sorted;
    }

    /// @notice ASCII whitespace stripped from both ends.
    /// @param value The text to trim.
    /// @return The trimmed copy.
    function trim(string memory value) internal pure returns (string memory) {
        bytes memory valueBytes = bytes(value);
        uint256 start = 0;
        uint256 end = valueBytes.length;
        while (start < end && _isSpace(valueBytes[start])) {
            start++;
        }
        while (end > start && _isSpace(valueBytes[end - 1])) {
            end--;
        }
        return string(Bytes.slice(valueBytes, start, end));
    }

    /// @notice ASCII-only lower-casing; bytes outside `A-Z` are copied
    /// unchanged.
    /// @param value The text to lower-case.
    /// @return The lower-cased copy.
    function toLower(string memory value) internal pure returns (string memory) {
        bytes memory lowered = bytes(string.concat(value));
        for (uint256 i = 0; i < lowered.length; i++) {
            if (_isUpper(lowered[i])) lowered[i] = bytes1(uint8(lowered[i]) + 32);
        }
        return string(lowered);
    }

    /// @notice ASCII-only upper-casing; bytes outside `a-z` are copied
    /// unchanged.
    /// @param value The text to upper-case.
    /// @return The upper-cased copy.
    function toUpper(string memory value) internal pure returns (string memory) {
        bytes memory raised = bytes(string.concat(value));
        for (uint256 i = 0; i < raised.length; i++) {
            raised[i] = _upper(raised[i]);
        }
        return string(raised);
    }

    /// @notice Whether `text` holds the UTF-8 encoding of a Unicode whitespace
    /// character: U+0085, U+00A0, U+1680, U+2000 to U+200A, U+2028, U+2029,
    /// U+202F, U+205F, U+3000 or U+FEFF.
    function _hasUnicodeSpace(bytes memory text) private pure returns (bool) {
        for (uint256 i = 0; i + 1 < text.length; i++) {
            bytes1 lead = text[i];
            bytes1 next = text[i + 1];
            if (lead == 0xC2 && (next == 0x85 || next == 0xA0)) return true;
            if (i + 2 >= text.length) continue;
            bytes1 last = text[i + 2];
            if (lead == 0xE1 && next == 0x9A && last == 0x80) return true;
            if (
                lead == 0xE2 && next == 0x80
                    && ((last >= 0x80 && last <= 0x8A) || last == 0xA8 || last == 0xA9 || last == 0xAF)
            ) {
                return true;
            }
            if (lead == 0xE2 && next == 0x81 && last == 0x9F) return true;
            if (lead == 0xE3 && next == 0x80 && last == 0x80) return true;
            if (lead == 0xEF && next == 0xBB && last == 0xBF) return true;
        }
        return false;
    }

    function _isAdrOrAds(bytes memory name, uint256 at) private pure returns (bool) {
        bytes1 last = _upper(name[at + 2]);
        return _upper(name[at]) == "A" && _upper(name[at + 1]) == "D" && (last == "R" || last == "S");
    }

    function _upper(bytes1 char) private pure returns (bytes1) {
        return _isLower(char) ? bytes1(uint8(char) - 32) : char;
    }

    function _isUpper(bytes1 char) private pure returns (bool) {
        return char >= "A" && char <= "Z";
    }

    function _isLower(bytes1 char) private pure returns (bool) {
        return char >= "a" && char <= "z";
    }

    function _isDigit(bytes1 char) private pure returns (bool) {
        return char >= "0" && char <= "9";
    }

    function _isSpace(bytes1 char) private pure returns (bool) {
        return char == " " || char == "\t" || char == "\n" || char == "\r" || char == 0x0b || char == 0x0c;
    }

    function _lessThan(string memory left, string memory right) private pure returns (bool) {
        bytes memory leftBytes = bytes(left);
        bytes memory rightBytes = bytes(right);
        uint256 shorter = leftBytes.length < rightBytes.length ? leftBytes.length : rightBytes.length;
        for (uint256 i = 0; i < shorter; i++) {
            if (leftBytes[i] != rightBytes[i]) return leftBytes[i] < rightBytes[i];
        }
        return leftBytes.length < rightBytes.length;
    }
}

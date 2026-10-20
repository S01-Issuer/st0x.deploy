// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Strings} from "@openzeppelin-contracts-5.7.0/utils/Strings.sol";
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
    uint256 internal constant BASE_CHAIN_ID = 8453;
    uint256 internal constant CERTIFY_YEARS = 1;

    /// @notice Plan one metadata file.
    /// @return skipped True when the symbol has already shipped or was retired:
    /// editing the metadata of a live token must never launch it again.
    /// @return plan The derived launch arguments, empty when skipped.
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

    function parseAssetType(string memory assetType) internal pure returns (AssetType) {
        string memory trimmed = trim(assetType);
        if (Strings.equal(trimmed, "Equity")) return AssetType.Equity;
        if (Strings.equal(trimmed, "ETF")) return AssetType.Etf;
        revert UnsupportedAssetType(trimmed);
    }

    /// @notice The trimmed name, which must be present and must not be the
    /// ticker or the symbol.
    function checkName(string memory name, string memory ticker, string memory symbol)
        internal
        pure
        returns (string memory rawName)
    {
        rawName = trim(name);
        if (bytes(rawName).length == 0) revert MissingName();
        string memory lowered = toLower(rawName);
        if (Strings.equal(lowered, toLower(symbol)) || Strings.equal(lowered, toLower(ticker))) {
            revert NameIsTicker(rawName);
        }
    }

    /// @notice A pinned token lands only on its own allowlisted authoriser.
    /// Every failure is a refusal, never a fall-back to the shared authoriser.
    function checkPin(DedicatedPin memory pin, string memory symbol, PlanContext memory ctx)
        internal
        pure
        returns (address authoriser, address minter)
    {
        if (pin.chainId != BASE_CHAIN_ID) revert DedicatedPinWrongChain(symbol, pin.chainId);

        bool ok;
        (ok, authoriser) = parseSetAddress(pin.authoriser);
        if (!ok) revert DedicatedAuthoriserUnset(symbol, pin.authoriser);
        if (authoriser == ctx.sharedAuthoriser) revert DedicatedAuthoriserIsShared(symbol);

        (ok, minter) = parseSetAddress(pin.minter);
        if (!ok) revert DedicatedMinterUnset(symbol, pin.minter);

        if (pin.deployBlock == 0) revert DedicatedDeployBlockUnset(symbol);

        if (!containsAddress(ctx.allowlistedAuthorisers, authoriser)) {
            revert DedicatedAuthoriserNotAllowlisted(symbol, authoriser);
        }
    }

    /// @notice The pin for `symbol`, matched case-insensitively.
    function findPin(DedicatedPin[] memory pins, string memory symbol)
        internal
        pure
        returns (bool found, DedicatedPin memory pin)
    {
        string memory target = toLower(symbol);
        for (uint256 i = 0; i < pins.length; i++) {
            found = Strings.equal(toLower(pins[i].symbol), target);
            if (found) return (found, pins[i]);
        }
    }

    /// @notice Parse a `0x`-prefixed address the way viem's `isAddress` accepts
    /// it: forty hex digits, either all lower case or exactly EIP-55. The zero
    /// address counts as unset.
    function parseSetAddress(string memory value) internal pure returns (bool ok, address parsed) {
        bytes memory raw = bytes(value);
        if (raw.length != 42 || raw[0] != "0" || raw[1] != "x") return (ok, parsed);
        (ok, parsed) = Strings.tryParseAddress(value);
        ok = ok && parsed != address(0)
            && (Strings.equal(toLower(value), value) || Strings.equal(Strings.toChecksumHexString(parsed), value));
        if (!ok) parsed = address(0);
    }

    /// @notice `(ADR)` and `(ADS)` become `ADR` and `ADS`, runs of two or more
    /// whitespace characters become one space, and the ends are trimmed: both
    /// `Foo Limited (ADR)` and `Foo Limited ADR` name the same token.
    function normaliseAdrName(string memory name) internal pure returns (string memory) {
        bytes memory src = bytes(name);
        bytes memory unwrapped = new bytes(src.length);
        uint256 n = 0;
        for (uint256 i = 0; i < src.length; i++) {
            if (src[i] == "(" && i + 4 < src.length && src[i + 4] == ")" && _isAdrOrAds(src, i + 1)) {
                unwrapped[n++] = src[i + 1];
                unwrapped[n++] = src[i + 2];
                unwrapped[n++] = src[i + 3];
                i += 4;
            } else {
                unwrapped[n++] = src[i];
            }
        }

        bytes memory collapsed = new bytes(n);
        uint256 m = 0;
        for (uint256 i = 0; i < n; i++) {
            if (_isSpace(unwrapped[i]) && i + 1 < n && _isSpace(unwrapped[i + 1])) {
                while (i + 1 < n && _isSpace(unwrapped[i + 1])) {
                    i++;
                }
                collapsed[m++] = " ";
            } else {
                collapsed[m++] = unwrapped[i];
            }
        }
        assembly ("memory-safe") {
            mstore(collapsed, m)
        }
        return trim(string(collapsed));
    }

    /// @notice The counterparty names, in any order, are exactly the US set
    /// (`AlpacaDB Inc`, `Clear Street LLC`) or the non-US set, which adds
    /// `Freedom Finance`.
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

    function isTicker(string memory ticker) internal pure returns (bool) {
        bytes memory b = bytes(ticker);
        for (uint256 i = 0; i < b.length; i++) {
            bytes1 c = b[i];
            if (!_isUpper(c) && !(c >= "a" && c <= "z") && !_isDigit(c) && c != "." && c != "-") return false;
        }
        return true;
    }

    /// @notice Two upper-case ASCII letters.
    function isCountryIso(string memory iso) internal pure returns (bool) {
        bytes memory b = bytes(iso);
        return b.length == 2 && _isUpper(b[0]) && _isUpper(b[1]);
    }

    /// @notice `^[A-Z]{2}[A-Z0-9]{9}[0-9]$`.
    function isIsin(string memory isin) internal pure returns (bool) {
        bytes memory b = bytes(isin);
        if (b.length != 12 || !_isUpper(b[0]) || !_isUpper(b[1]) || !_isDigit(b[11])) return false;
        for (uint256 i = 2; i < 11; i++) {
            if (!_isUpper(b[i]) && !_isDigit(b[i])) return false;
        }
        return true;
    }

    function contains(string[] memory values, string memory value) internal pure returns (bool) {
        for (uint256 i = 0; i < values.length; i++) {
            if (Strings.equal(values[i], value)) return true;
        }
        return false;
    }

    function containsAddress(address[] memory values, address value) internal pure returns (bool) {
        for (uint256 i = 0; i < values.length; i++) {
            if (values[i] == value) return true;
        }
        return false;
    }

    /// @notice A sorted copy, by byte order: JavaScript's default sort for the
    /// ASCII names compared here.
    function sortStrings(string[] memory values) internal pure returns (string[] memory sorted) {
        sorted = new string[](values.length);
        for (uint256 i = 0; i < values.length; i++) {
            sorted[i] = values[i];
            for (uint256 j = i; j > 0 && _lessThan(sorted[j], sorted[j - 1]); j--) {
                (sorted[j], sorted[j - 1]) = (sorted[j - 1], sorted[j]);
            }
        }
    }

    /// @notice ASCII whitespace stripped from both ends.
    function trim(string memory value) internal pure returns (string memory) {
        bytes memory b = bytes(value);
        uint256 start = 0;
        uint256 end = b.length;
        while (start < end && _isSpace(b[start])) {
            start++;
        }
        while (end > start && _isSpace(b[end - 1])) {
            end--;
        }
        bytes memory out = new bytes(end - start);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = b[start + i];
        }
        return string(out);
    }

    function toLower(string memory value) internal pure returns (string memory) {
        bytes memory out = bytes(string.concat(value));
        for (uint256 i = 0; i < out.length; i++) {
            if (_isUpper(out[i])) out[i] = bytes1(uint8(out[i]) + 32);
        }
        return string(out);
    }

    function toUpper(string memory value) internal pure returns (string memory) {
        bytes memory out = bytes(string.concat(value));
        for (uint256 i = 0; i < out.length; i++) {
            if (out[i] >= "a" && out[i] <= "z") out[i] = bytes1(uint8(out[i]) - 32);
        }
        return string(out);
    }

    function _isAdrOrAds(bytes memory b, uint256 at) private pure returns (bool) {
        bytes1 a = _upper(b[at]);
        bytes1 d = _upper(b[at + 1]);
        bytes1 last = _upper(b[at + 2]);
        return a == "A" && d == "D" && (last == "R" || last == "S");
    }

    function _upper(bytes1 c) private pure returns (bytes1) {
        return c >= "a" && c <= "z" ? bytes1(uint8(c) - 32) : c;
    }

    function _isUpper(bytes1 c) private pure returns (bool) {
        return c >= "A" && c <= "Z";
    }

    function _isDigit(bytes1 c) private pure returns (bool) {
        return c >= "0" && c <= "9";
    }

    function _isSpace(bytes1 c) private pure returns (bool) {
        return c == " " || c == "\t" || c == "\n" || c == "\r" || c == 0x0b || c == 0x0c;
    }

    function _lessThan(string memory a, string memory b) private pure returns (bool) {
        bytes memory x = bytes(a);
        bytes memory y = bytes(b);
        uint256 n = x.length < y.length ? x.length : y.length;
        for (uint256 i = 0; i < n; i++) {
            if (x[i] != y[i]) return x[i] < y[i];
        }
        return x.length < y.length;
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {Strings} from "@openzeppelin-contracts-5.7.0/utils/Strings.sol";
import {LibLaunchPlan, LaunchMetadata, DedicatedPin} from "../../src/lib/LibLaunchPlan.sol";

/// @title LibLaunchInputs
/// @notice Reads the launch inputs under `launch/` (metadata files, the ledger,
/// the dedicated-authoriser pins and the allowlist) into the shapes
/// `LibLaunchPlan` checks. A text field that is missing, null, an array or an
/// object reads as the empty string; a number or boolean reads as its decimal
/// or `true`/`false` text, as sft-ops `String(x ?? '')` gives. For an array or
/// object JavaScript gives non-empty text where this reads empty, so the field
/// is refused as missing. A numeric field counts only as a JSON non-negative
/// integer and reads as zero otherwise.
library LibLaunchInputs {
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Whether `file` is a deploy input: `launch/metadata/<name>.json`,
    /// with no directory in between. `published/` never counts.
    /// @param file A repository-relative path.
    /// @return Whether the path is a deploy input.
    function isMetadataFile(string memory file) internal pure returns (bool) {
        bytes memory path = bytes(file);
        return _endsWith(path, ".json") && _directlyUnder(path, "launch/metadata/");
    }

    /// @notice The fields of one metadata file the plan reads.
    /// @param path The metadata file.
    /// @return metadata The fields, each empty when missing.
    function readMetadata(string memory path) internal view returns (LaunchMetadata memory metadata) {
        string memory json = VM.readFile(path);
        metadata.primaryTicker = _string(json, ".primary_ticker");
        metadata.assetType = _string(json, ".asset_type");
        metadata.name = _string(json, ".name");
        metadata.countryIso = _string(json, ".country.iso");
        metadata.isin = _string(json, ".isin");

        uint256 count = _arrayLength(json, ".offchain_counterparties");
        metadata.counterparties = new string[](count);
        for (uint256 i = 0; i < count; i++) {
            metadata.counterparties[i] =
                _string(json, string.concat(".offchain_counterparties[", VM.toString(i), "].name"));
        }
    }

    /// @notice Lower-cased symbols the planner must never launch again: every
    /// live ledger row, plus every row whose deprecation is marked `retired`.
    /// A deprecation without `retired` is a bad deploy whose symbol is meant to
    /// be launched again.
    /// @param ledgerPath The launch ledger.
    /// @return symbols The lower-cased symbols, in ledger order.
    function readShippedSymbols(string memory ledgerPath) internal view returns (string[] memory symbols) {
        string memory json = VM.readFile(ledgerPath);
        uint256 count = _arrayLength(json, "$");
        string[] memory shipped = new string[](count);
        uint256 shippedCount = 0;
        for (uint256 i = 0; i < count; i++) {
            string memory row = string.concat("$[", VM.toString(i), "]");
            string memory symbol = _string(json, string.concat(row, ".symbol"));
            if (bytes(symbol).length == 0) continue;
            string memory retiredKey = string.concat(row, ".deprecated.retired");
            bool deprecated = _present(json, string.concat(row, ".deprecated"));
            // `{"retired": false}` encodes as a zero word, so `_present` on the
            // object is false. The key itself is what decides.
            bool retiredKeyExists = VM.keyExistsJson(json, retiredKey);
            if (!deprecated && !retiredKeyExists) {
                shipped[shippedCount++] = LibLaunchPlan.toLower(symbol);
                continue;
            }
            if (!retiredKeyExists || !_retired(json, retiredKey)) continue;
            shipped[shippedCount++] = LibLaunchPlan.toLower(symbol);
        }
        symbols = new string[](shippedCount);
        for (uint256 i = 0; i < shippedCount; i++) {
            symbols[i] = shipped[i];
        }
    }

    /// @notice Every pin in the dedicated-authoriser file, keyed by symbol as
    /// written. `minterGrantPending` is true only for JSON `true`.
    /// @param pinsPath The dedicated-authoriser pin file.
    /// @return pins The pins, in key order.
    function readPins(string memory pinsPath) internal view returns (DedicatedPin[] memory pins) {
        string memory json = VM.readFile(pinsPath);
        string[] memory symbols = VM.parseJsonKeys(json, "$");
        pins = new DedicatedPin[](symbols.length);
        for (uint256 i = 0; i < symbols.length; i++) {
            string memory key = string.concat("$['", symbols[i], "']");
            pins[i].symbol = symbols[i];
            pins[i].chainId = _uint(json, string.concat(key, ".chainId"));
            pins[i].authoriser = _string(json, string.concat(key, ".authorizer"));
            pins[i].minter = _string(json, string.concat(key, ".minter"));
            pins[i].deployBlock = _uint(json, string.concat(key, ".deployBlock"));
            pins[i].minterGrantPending = _bool(json, string.concat(key, ".minterGrantPending"));
        }
    }

    /// @notice Addresses allowlisted with `role`. With `chainId` non-zero, only
    /// entries for that chain count; sft-ops checks owners on any chain and
    /// authorisers on Base only.
    /// @param allowlistPath The allowlist file.
    /// @param role The role an entry must list.
    /// @param chainId The chain an entry must name, or zero for any chain.
    /// @return addresses The matching addresses, in file order.
    function readAllowlisted(string memory allowlistPath, string memory role, uint256 chainId)
        internal
        view
        returns (address[] memory addresses)
    {
        string memory json = VM.readFile(allowlistPath);
        uint256 count = _arrayLength(json, "$");
        address[] memory matched = new address[](count);
        uint256 matchedCount = 0;
        for (uint256 i = 0; i < count; i++) {
            string memory entry = string.concat("$[", VM.toString(i), "]");
            if (chainId != 0 && _uint(json, string.concat(entry, ".chainId")) != chainId) continue;
            string[] memory roles = _strings(json, string.concat(entry, ".roles"));
            if (!LibLaunchPlan.contains(roles, role)) continue;
            matched[matchedCount++] = VM.parseJsonAddress(json, string.concat(entry, ".address"));
        }
        addresses = new address[](matchedCount);
        for (uint256 i = 0; i < matchedCount; i++) {
            addresses[i] = matched[i];
        }
    }

    function _present(string memory json, string memory key) private view returns (bool) {
        if (!VM.keyExistsJson(json, key)) return false;
        bytes memory raw = VM.parseJson(json, key);
        return raw.length != 0 && keccak256(raw) != keccak256(abi.encode(bytes32(0)));
    }

    /// @notice Foundry reads JSON `null` as the text `null`; it is the zero
    /// word, which the string `"null"` never is.
    function _string(string memory json, string memory key) private view returns (string memory) {
        if (!VM.keyExistsJson(json, key)) return "";
        try VM.parseJsonString(json, key) returns (string memory value) {
            if (_jsonZero(json, key) && Strings.equal(value, "null")) return "";
            return value;
        } catch {
            return "";
        }
    }

    /// @notice `parseJsonUint` also accepts decimal and hex strings, and an
    /// address-shaped string is a single word. A JSON number is the only value
    /// that reads back as its own decimal text.
    function _uint(string memory json, string memory key) private view returns (uint256) {
        if (!VM.keyExistsJson(json, key)) return 0;
        try VM.parseJsonUint(json, key) returns (uint256 value) {
            bool number = _jsonWord(json, key) && Strings.equal(VM.parseJsonString(json, key), VM.toString(value));
            return number ? value : 0;
        } catch {
            return 0;
        }
    }

    /// @notice A deprecation with no `retired` flag is a bad deploy and stays
    /// plannable. JSON `false`, `0` and `null` do too: Foundry encodes all three
    /// as the zero word. Any other present value fails closed and counts as
    /// retired, including `""`, which JavaScript treats as false.
    function _retired(string memory json, string memory key) private view returns (bool) {
        return VM.keyExistsJson(json, key) && !_jsonZero(json, key);
    }

    /// @notice JSON `true` only, as cd-plan's `=== true`. `parseJsonBool` also
    /// accepts `"true"` and `1`, and JSON `1` and `{"a":1}` encode as the same
    /// word as `true`; only `true` reads back as the text `true`.
    function _bool(string memory json, string memory key) private view returns (bool) {
        if (!VM.keyExistsJson(json, key)) return false;
        if (keccak256(VM.parseJson(json, key)) != keccak256(abi.encode(true))) return false;
        try VM.parseJsonString(json, key) returns (string memory value) {
            return Strings.equal(value, "true");
        } catch {
            return false;
        }
    }

    function _jsonWord(string memory json, string memory key) private pure returns (bool) {
        return VM.parseJson(json, key).length == 32;
    }

    function _jsonZero(string memory json, string memory key) private pure returns (bool) {
        return keccak256(VM.parseJson(json, key)) == keccak256(abi.encode(false));
    }

    function _strings(string memory json, string memory key) private view returns (string[] memory) {
        if (!VM.keyExistsJson(json, key)) return new string[](0);
        try VM.parseJsonStringArray(json, key) returns (string[] memory values) {
            return values;
        } catch {
            return new string[](0);
        }
    }

    function _endsWith(bytes memory path, bytes memory suffix) private pure returns (bool) {
        if (path.length < suffix.length) return false;
        for (uint256 i = 0; i < suffix.length; i++) {
            if (path[path.length - suffix.length + i] != suffix[i]) return false;
        }
        return true;
    }

    /// @notice `prefix` plus a file name, with no further slash.
    function _directlyUnder(bytes memory path, bytes memory prefix) private pure returns (bool) {
        if (path.length <= prefix.length) return false;
        for (uint256 i = 0; i < prefix.length; i++) {
            if (path[i] != prefix[i]) return false;
        }
        for (uint256 i = prefix.length; i < path.length; i++) {
            if (path[i] == "/") return false;
        }
        return true;
    }

    function _arrayLength(string memory json, string memory key) private view returns (uint256 count) {
        while (VM.keyExistsJson(json, string.concat(key, "[", VM.toString(count), "]"))) {
            count++;
        }
    }
}

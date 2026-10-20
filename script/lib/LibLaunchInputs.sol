// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibLaunchPlan, LaunchMetadata, DedicatedPin} from "../../src/lib/LibLaunchPlan.sol";

/// @title LibLaunchInputs
/// @notice Reads the launch inputs under `launch/` (metadata files, the ledger,
/// the dedicated-authoriser pins and the allowlist) into the shapes
/// `LibLaunchPlan` checks. A field that is missing, null or not a string reads
/// as the empty string, as `String(x ?? '')` does in sft-ops.
library LibLaunchInputs {
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Whether `file` is a deploy input: `launch/metadata/<name>.json`,
    /// with no directory in between. `published/` never counts. Tests may stage
    /// the same shape under `out/`.
    function isMetadataFile(string memory file) internal pure returns (bool) {
        bytes memory b = bytes(file);
        if (!_endsWith(b, ".json")) return false;
        if (_directlyUnder(b, "launch/metadata/")) return true;
        return _startsWith(b, "out/") && _parentIs(b, "metadata");
    }

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
    function readShippedSymbols(string memory ledgerPath) internal view returns (string[] memory symbols) {
        string memory json = VM.readFile(ledgerPath);
        uint256 count = _arrayLength(json, "$");
        string[] memory found = new string[](count);
        uint256 n = 0;
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
                found[n++] = LibLaunchPlan.toLower(symbol);
                continue;
            }
            if (!retiredKeyExists || !_retired(json, retiredKey)) continue;
            found[n++] = LibLaunchPlan.toLower(symbol);
        }
        symbols = new string[](n);
        for (uint256 i = 0; i < n; i++) {
            symbols[i] = found[i];
        }
    }

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
    function readAllowlisted(string memory allowlistPath, string memory role, uint256 chainId)
        internal
        view
        returns (address[] memory addresses)
    {
        string memory json = VM.readFile(allowlistPath);
        uint256 count = _arrayLength(json, "$");
        address[] memory found = new address[](count);
        uint256 n = 0;
        for (uint256 i = 0; i < count; i++) {
            string memory entry = string.concat("$[", VM.toString(i), "]");
            if (chainId != 0 && _uint(json, string.concat(entry, ".chainId")) != chainId) continue;
            string[] memory roles = _strings(json, string.concat(entry, ".roles"));
            if (!LibLaunchPlan.contains(roles, role)) continue;
            found[n++] = VM.parseJsonAddress(json, string.concat(entry, ".address"));
        }
        addresses = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            addresses[i] = found[i];
        }
    }

    function _present(string memory json, string memory key) private view returns (bool) {
        if (!VM.keyExistsJson(json, key)) return false;
        bytes memory raw = VM.parseJson(json, key);
        return raw.length != 0 && keccak256(raw) != keccak256(abi.encode(bytes32(0)));
    }

    function _string(string memory json, string memory key) private view returns (string memory) {
        if (!VM.keyExistsJson(json, key)) return "";
        try VM.parseJsonString(json, key) returns (string memory value) {
            return value;
        } catch {
            return "";
        }
    }

    function _uint(string memory json, string memory key) private view returns (uint256) {
        if (!VM.keyExistsJson(json, key)) return 0;
        try VM.parseJsonUint(json, key) returns (uint256 value) {
            return value;
        } catch {
            return 0;
        }
    }

    /// @notice A deprecation with no `retired` flag is a bad deploy and stays
    /// plannable. JSON `false` does too. Any other present value fails closed
    /// and counts as retired. JSON `0` is the exception: Foundry encodes it as
    /// the same zero word as `false`, so it stays plannable.
    function _retired(string memory json, string memory key) private view returns (bool) {
        if (!VM.keyExistsJson(json, key)) return false;
        return _jsonTrue(json, key) || !_jsonWord(json, key);
    }

    /// @notice JSON `true` only. `parseJsonBool` also accepts `"true"` and `1`,
    /// which cd-plan's `=== true` rejects. JSON `1` encodes as the same word as
    /// `true`, so it still counts.
    function _bool(string memory json, string memory key) private view returns (bool) {
        if (!VM.keyExistsJson(json, key)) return false;
        return _jsonTrue(json, key);
    }

    function _jsonWord(string memory json, string memory key) private pure returns (bool) {
        return VM.parseJson(json, key).length == 32;
    }

    function _jsonTrue(string memory json, string memory key) private pure returns (bool) {
        bytes memory raw = VM.parseJson(json, key);
        return raw.length == 32 && keccak256(raw) == keccak256(abi.encode(true));
    }

    function _strings(string memory json, string memory key) private view returns (string[] memory) {
        if (!VM.keyExistsJson(json, key)) return new string[](0);
        try VM.parseJsonStringArray(json, key) returns (string[] memory values) {
            return values;
        } catch {
            return new string[](0);
        }
    }

    function _endsWith(bytes memory b, bytes memory suffix) private pure returns (bool) {
        if (b.length < suffix.length) return false;
        for (uint256 i = 0; i < suffix.length; i++) {
            if (b[b.length - suffix.length + i] != suffix[i]) return false;
        }
        return true;
    }

    function _startsWith(bytes memory b, bytes memory prefix) private pure returns (bool) {
        if (b.length < prefix.length) return false;
        for (uint256 i = 0; i < prefix.length; i++) {
            if (b[i] != prefix[i]) return false;
        }
        return true;
    }

    /// @notice `prefix` plus a file name, with no further slash.
    function _directlyUnder(bytes memory b, bytes memory prefix) private pure returns (bool) {
        if (!_startsWith(b, prefix) || b.length == prefix.length) return false;
        for (uint256 i = prefix.length; i < b.length; i++) {
            if (b[i] == "/") return false;
        }
        return true;
    }

    function _parentIs(bytes memory b, bytes memory dir) private pure returns (bool) {
        uint256 slash = type(uint256).max;
        for (uint256 i = b.length; i > 0; i--) {
            if (b[i - 1] == "/") {
                slash = i - 1;
                break;
            }
        }
        if (slash == type(uint256).max || slash < dir.length) return false;
        if (slash != dir.length && b[slash - dir.length - 1] != "/") return false;
        for (uint256 i = 0; i < dir.length; i++) {
            if (b[slash - dir.length + i] != dir[i]) return false;
        }
        return true;
    }

    function _arrayLength(string memory json, string memory key) private view returns (uint256 count) {
        while (VM.keyExistsJson(json, string.concat(key, "[", VM.toString(count), "]"))) {
            count++;
        }
    }
}

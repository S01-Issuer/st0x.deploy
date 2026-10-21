// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";

/// @notice The ledger's top level is not a JSON array: its first non-space
/// byte is not `[`, or something other than whitespace follows its last `]`.
error LedgerNotAnArray(string path);

/// @notice The ledger did not read back with the appended rows at its end.
error LedgerAppendFailed(string path);

/// @notice One `launch/launches.json` row, in its key order.
struct LedgerRow {
    string symbol;
    string name;
    address sft;
    address wrapper;
    address authorizer;
    uint256 chainId;
    string deployedAt;
    address deployedBy;
    address intendedOwner;
    address currentOwner;
    string certifyUntil;
}

/// @title LibLedger
/// @notice Appends rows to the launch ledger in the layout sft-ops writes,
/// `JSON.stringify(entries, null, 2)`, so the file only ever grows at its end.
/// `vm.writeJson` would reorder every key in the file.
library LibLedger {
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Append `rows` to the JSON array in `path`, then read it back.
    /// @param path The ledger.
    /// @param rows The rows to append.
    function append(string memory path, LedgerRow[] memory rows) internal {
        if (rows.length == 0) return;
        bytes memory file = bytes(VM.readFile(path));
        uint256 start = 0;
        while (start < file.length && _isSpace(file[start])) {
            start++;
        }
        uint256 end = file.length;
        while (end > start && _isSpace(file[end - 1])) {
            end--;
        }
        if (end - start < 2 || file[start] != "[" || file[end - 1] != "]") revert LedgerNotAnArray(path);
        uint256 existing = _arrayLength(string(file));
        uint256 body = end - 1;
        while (body > 0 && _isSpace(file[body - 1])) {
            body--;
        }
        bool empty = body > 0 && file[body - 1] == "[";

        bytes memory out = new bytes(body);
        for (uint256 i = 0; i < body; i++) {
            out[i] = file[i];
        }
        for (uint256 i = 0; i < rows.length; i++) {
            out = abi.encodePacked(out, empty && i == 0 ? "\n" : ",\n", format(rows[i]));
        }
        VM.writeFile(path, string(abi.encodePacked(out, "\n]\n")));

        string memory written = VM.readFile(path);
        string memory last = string.concat("$[", VM.toString(existing + rows.length - 1), "]");
        if (
            _arrayLength(written) != existing + rows.length
                || keccak256(bytes(VM.parseJsonString(written, string.concat(last, ".symbol"))))
                    != keccak256(bytes(rows[rows.length - 1].symbol))
        ) revert LedgerAppendFailed(path);
    }

    /// @notice A row as `JSON.stringify` prints an array element at indent 2.
    /// @param row The row.
    /// @return out The row's text.
    function format(LedgerRow memory row) internal pure returns (string memory out) {
        out = string.concat("  {\n", _field("symbol", quote(row.symbol)), _field("name", quote(row.name)));
        out = string.concat(out, _address("sft", row.sft), _address("wrapper", row.wrapper));
        out = string.concat(out, _address("authorizer", row.authorizer), _field("chainId", VM.toString(row.chainId)));
        out = string.concat(out, _field("deployedAt", quote(row.deployedAt)), _address("deployedBy", row.deployedBy));
        out = string.concat(
            out, _address("intendedOwner", row.intendedOwner), _address("currentOwner", row.currentOwner)
        );
        out = string.concat(out, _field("certifyUntil", quote(row.certifyUntil)), _field("smokeTested", "null"));
        out = string.concat(out, "    \"handedOff\": null\n  }");
    }

    function _address(string memory key, address value) private pure returns (string memory) {
        return _field(key, quote(VM.toString(value)));
    }

    /// @notice A JSON string literal escaped the way `JSON.stringify` does.
    /// @param value The text.
    /// @return The literal.
    function quote(string memory value) internal pure returns (string memory) {
        bytes memory valueBytes = bytes(value);
        bytes memory out = "\"";
        for (uint256 i = 0; i < valueBytes.length; i++) {
            bytes1 char = valueBytes[i];
            if (char == "\"") {
                out = abi.encodePacked(out, "\\\"");
            } else if (char == "\\") {
                out = abi.encodePacked(out, "\\\\");
            } else if (char == "\n") {
                out = abi.encodePacked(out, "\\n");
            } else if (char == "\r") {
                out = abi.encodePacked(out, "\\r");
            } else if (char == "\t") {
                out = abi.encodePacked(out, "\\t");
            } else if (char == 0x08) {
                out = abi.encodePacked(out, "\\b");
            } else if (char == 0x0c) {
                out = abi.encodePacked(out, "\\f");
            } else if (uint8(char) < 0x20) {
                out = abi.encodePacked(out, "\\u00", _hex(uint8(char) >> 4), _hex(uint8(char) & 0x0f));
            } else {
                out = abi.encodePacked(out, char);
            }
        }
        return string(abi.encodePacked(out, "\""));
    }

    function _field(string memory key, string memory value) private pure returns (string memory) {
        return string.concat("    \"", key, "\": ", value, ",\n");
    }

    function _hex(uint8 nibble) private pure returns (bytes1) {
        return nibble < 10 ? bytes1(nibble + 0x30) : bytes1(nibble + 0x57);
    }

    function _isSpace(bytes1 char) private pure returns (bool) {
        return char == " " || char == "\n" || char == "\r" || char == "\t";
    }

    function _arrayLength(string memory json) private view returns (uint256 count) {
        while (VM.keyExistsJson(json, string.concat("$[", VM.toString(count), "]"))) {
            count++;
        }
    }
}

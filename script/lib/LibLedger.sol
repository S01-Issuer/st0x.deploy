// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";

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

    /// @notice Append `rows` to the JSON array in `path`.
    function append(string memory path, LedgerRow[] memory rows) internal {
        if (rows.length == 0) return;
        bytes memory file = bytes(VM.readFile(path));
        uint256 end = file.length;
        while (end > 0 && file[end - 1] != "]") {
            end--;
        }
        require(end > 0, "ledger is not a JSON array");
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
    }

    /// @notice A row as `JSON.stringify` prints an array element at indent 2.
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
    function quote(string memory value) internal pure returns (string memory) {
        bytes memory b = bytes(value);
        bytes memory out = "\"";
        for (uint256 i = 0; i < b.length; i++) {
            bytes1 c = b[i];
            if (c == "\"") out = abi.encodePacked(out, "\\\"");
            else if (c == "\\") out = abi.encodePacked(out, "\\\\");
            else if (c == "\n") out = abi.encodePacked(out, "\\n");
            else if (c == "\r") out = abi.encodePacked(out, "\\r");
            else if (c == "\t") out = abi.encodePacked(out, "\\t");
            else if (c == 0x08) out = abi.encodePacked(out, "\\b");
            else if (c == 0x0c) out = abi.encodePacked(out, "\\f");
            else if (uint8(c) < 0x20) out = abi.encodePacked(out, "\\u00", _hex(uint8(c) >> 4), _hex(uint8(c) & 0x0f));
            else out = abi.encodePacked(out, c);
        }
        return string(abi.encodePacked(out, "\""));
    }

    function _field(string memory key, string memory value) private pure returns (string memory) {
        return string.concat("    \"", key, "\": ", value, ",\n");
    }

    function _hex(uint8 nibble) private pure returns (bytes1) {
        return nibble < 10 ? bytes1(nibble + 0x30) : bytes1(nibble + 0x57);
    }

    function _isSpace(bytes1 c) private pure returns (bool) {
        return c == " " || c == "\n" || c == "\r" || c == "\t";
    }
}

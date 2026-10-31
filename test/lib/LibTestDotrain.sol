// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

/// @dev A binding of a name to the literal that replaces it.
struct DotrainBinding {
    string name;
    string value;
}

/// @dev Thrown when the file has no `---` line ending its front matter.
error NoFrontMatterSplitter();

/// @dev Thrown when `name` is declared twice.
error DuplicateBinding(string name);

/// @dev Thrown when the entrypoint `name` is not declared in the file.
error NoEntrypoint(string name);

/// @dev Thrown when the caller binds `name` and the file does not declare it
/// elided: either it is not declared at all, or the file already gives it a
/// value.
error NotElided(string name);

/// @dev Thrown when the file declares `name` elided and the caller did not
/// bind it. Every knob in the file has to be turned by the test.
error Unbound(string name);

/// @title LibTestDotrain
/// @notice The slice of dotrain composition the tests need to run a `.rain`
/// source from this repo through the on-chain parser: pick one entrypoint out
/// of the file and bind its names to literals. The substitution is the one
/// `rain dotrain compose` does — a whole word outside a comment or a string
/// literal is replaced by the literal bound to it — so the text a test parses
/// is the text the CLI produces for the same bindings, without the CLI's
/// leading `/* 0. <entrypoint> */` marker.
///
/// It is not a dotrain implementation. The front matter is skipped, not read;
/// there are no imports, namespaces or quotes; a binding is a literal on the
/// header's line or the body under it, never a fragment referring to other
/// bindings; and one entrypoint is composed at a time. A file that needs more
/// than that needs the CLI.
library LibTestDotrain {
    /// @dev A binding as declared in the file.
    struct Declared {
        string name;
        /// Declared with `!`, so the caller has to bind it.
        bool elided;
        /// The literal on the header's line, or the body under it.
        string value;
    }

    /// @notice Compose `entrypoint` out of `dotrain` with `bindings` for its
    /// elided names. Every elided name in the file must be bound and every
    /// bound name must be elided in the file.
    /// @param dotrain The `.rain` file.
    /// @param entrypoint The name of the binding whose body is composed.
    /// @param bindings Literals for the file's elided bindings.
    /// @return The Rainlang.
    function compose(string memory dotrain, string memory entrypoint, DotrainBinding[] memory bindings)
        internal
        pure
        returns (string memory)
    {
        Declared[] memory declared = declarations(dotrain);

        // The table is the file's defaults plus the caller's bindings for the
        // elided names, less the entrypoint itself.
        DotrainBinding[] memory table = new DotrainBinding[](declared.length);
        uint256 tableLength = 0;
        string memory body;
        bool found = false;
        for (uint256 i = 0; i < declared.length; i++) {
            if (_same(declared[i].name, entrypoint)) {
                body = declared[i].value;
                found = true;
                continue;
            }
            if (declared[i].elided) {
                bool bound = false;
                for (uint256 j = 0; j < bindings.length; j++) {
                    if (_same(bindings[j].name, declared[i].name)) {
                        table[tableLength++] = bindings[j];
                        bound = true;
                        break;
                    }
                }
                if (!bound) revert Unbound(declared[i].name);
            } else {
                table[tableLength++] = DotrainBinding({name: declared[i].name, value: declared[i].value});
            }
        }
        if (!found) revert NoEntrypoint(entrypoint);
        for (uint256 j = 0; j < bindings.length; j++) {
            bool elided = false;
            for (uint256 i = 0; i < declared.length; i++) {
                if (declared[i].elided && _same(declared[i].name, bindings[j].name)) {
                    elided = true;
                    break;
                }
            }
            if (!elided) revert NotElided(bindings[j].name);
        }
        assembly ("memory-safe") {
            mstore(table, tableLength)
        }
        return substitute(body, table);
    }

    /// @notice Every `#name` declared after the front matter, in order.
    /// @param dotrain The `.rain` file.
    /// @return declared The declarations.
    function declarations(string memory dotrain) internal pure returns (Declared[] memory declared) {
        bytes memory data = bytes(dotrain);
        uint256 cursor = _afterFrontMatter(data);

        // Two passes over the same scan: count, then fill.
        uint256 count = 0;
        for (uint256 c = cursor; c < data.length; c = _nextLine(data, c)) {
            if (data[c] == "#") count++;
        }
        declared = new Declared[](count);

        // A header with nothing on its line has its body below it, running
        // to the next header or the end of the file.
        uint256 n = 0;
        bool open = false;
        uint256 bodyStart = 0;
        while (cursor < data.length) {
            uint256 next = _nextLine(data, cursor);
            if (data[cursor] == "#") {
                if (open) {
                    declared[n - 1].value = string(_slice(data, bodyStart, cursor));
                    open = false;
                }
                declared[n] = _header(data, cursor + 1, next);
                for (uint256 i = 0; i < n; i++) {
                    if (_same(declared[i].name, declared[n].name)) revert DuplicateBinding(declared[n].name);
                }
                if (bytes(declared[n].value).length == 0 && !declared[n].elided) {
                    open = true;
                    bodyStart = next;
                }
                n++;
            }
            cursor = next;
        }
        if (open) {
            declared[n - 1].value = string(_slice(data, bodyStart, data.length));
        }
    }

    /// @notice Replace every whole word in `body` that is a name in `table`
    /// with its value, leaving comments and string literals alone.
    /// @param body Rainlang with names in it.
    /// @param table The names and their literals.
    /// @return The Rainlang with the literals in place of the names.
    function substitute(string memory body, DotrainBinding[] memory table) internal pure returns (string memory) {
        bytes memory data = bytes(body);
        bytes memory out;
        uint256 cursor = 0;
        while (cursor < data.length) {
            bytes1 char = data[cursor];
            if (char == "/" && cursor + 1 < data.length && data[cursor + 1] == "*") {
                uint256 end = cursor + 2;
                while (end + 1 < data.length && !(data[end] == "*" && data[end + 1] == "/")) {
                    end++;
                }
                end = end + 2 > data.length ? data.length : end + 2;
                out = bytes.concat(out, _slice(data, cursor, end));
                cursor = end;
            } else if (char == "\"") {
                uint256 end = cursor + 1;
                while (end < data.length && data[end] != "\"") {
                    end++;
                }
                end = end < data.length ? end + 1 : end;
                out = bytes.concat(out, _slice(data, cursor, end));
                cursor = end;
            } else if (_isWordChar(char)) {
                uint256 end = cursor;
                while (end < data.length && _isWordChar(data[end])) {
                    end++;
                }
                bytes memory word = _slice(data, cursor, end);
                bool replaced = false;
                for (uint256 i = 0; i < table.length; i++) {
                    if (_same(string(word), table[i].name)) {
                        out = bytes.concat(out, bytes(table[i].value));
                        replaced = true;
                        break;
                    }
                }
                if (!replaced) out = bytes.concat(out, word);
                cursor = end;
            } else {
                out = bytes.concat(out, char);
                cursor++;
            }
        }
        return string(out);
    }

    /// The offset of the first line after the `---` line that ends the front
    /// matter.
    function _afterFrontMatter(bytes memory data) private pure returns (uint256) {
        uint256 cursor = 0;
        while (cursor < data.length) {
            uint256 next = _nextLine(data, cursor);
            uint256 end = next;
            if (end > cursor && data[end - 1] == "\n") end--;
            if (end - cursor == 3 && data[cursor] == "-" && data[cursor + 1] == "-" && data[cursor + 2] == "-") {
                return next;
            }
            cursor = next;
        }
        revert NoFrontMatterSplitter();
    }

    /// A header at `cursor` (just past the `#`) ending at `end` (just past
    /// its newline, or the end of the data). The name runs to the first
    /// whitespace; what follows, trimmed, is `!` for an elided binding or the
    /// literal.
    function _header(bytes memory data, uint256 cursor, uint256 end) private pure returns (Declared memory) {
        uint256 nameEnd = cursor;
        while (nameEnd < end && !_isWhitespace(data[nameEnd])) {
            nameEnd++;
        }
        uint256 restStart = nameEnd;
        while (restStart < end && _isWhitespace(data[restStart])) {
            restStart++;
        }
        uint256 restEnd = end;
        while (restEnd > restStart && _isWhitespace(data[restEnd - 1])) {
            restEnd--;
        }
        bool elided = restStart < restEnd && data[restStart] == "!";
        return Declared({
            name: string(_slice(data, cursor, nameEnd)),
            elided: elided,
            value: elided ? "" : string(_slice(data, restStart, restEnd))
        });
    }

    /// The offset just past the newline that ends the line at `cursor`, or
    /// the end of the data.
    function _nextLine(bytes memory data, uint256 cursor) private pure returns (uint256) {
        while (cursor < data.length) {
            if (data[cursor] == "\n") return cursor + 1;
            cursor++;
        }
        return cursor;
    }

    function _slice(bytes memory data, uint256 start, uint256 end) private pure returns (bytes memory) {
        bytes memory out = new bytes(end - start);
        for (uint256 i = start; i < end; i++) {
            out[i - start] = data[i];
        }
        return out;
    }

    function _same(string memory a, string memory b) private pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _isWhitespace(bytes1 char) private pure returns (bool) {
        return char == " " || char == "\t" || char == "\n" || char == "\r";
    }

    /// The characters a word is made of, wide enough that a name never
    /// matches a run inside a longer word.
    function _isWordChar(bytes1 char) private pure returns (bool) {
        return (char >= "a" && char <= "z") || (char >= "A" && char <= "Z") || (char >= "0" && char <= "9")
            || char == "-" || char == "_";
    }
}

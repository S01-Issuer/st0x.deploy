// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {OperandV2} from "rainlang-0.2.30/src/interface/IInterpreterV4.sol";
import {IInterpreterExternV4, StackItem} from "rainlang-0.2.30/src/interface/IInterpreterExternV4.sol";
import {LibSubParse} from "rainlang-0.2.30/src/lib/parse/LibSubParse.sol";
import {
    IntOrAString,
    LibIntOrAString,
    LENGTH_MASK_V3,
    TRUTHY_BITS_V3
} from "rain-intorastring-0.1.4/src/lib/LibIntOrAString.sol";

import {NotAString, Utf8HashNoInputs} from "../../error/ErrUtf8Hash.sol";

/// @dev Index of `utf8-hash` in the extern's opcode tables.
uint256 constant OP_INDEX_UTF8_HASH = 0;

/// @title LibOpUtf8Hash
/// @notice `utf8-hash`: keccak256 of the UTF-8 bytes of its IntOrAString string
/// inputs, concatenated in order. Takes one or more inputs, outputs one.
library LibOpUtf8Hash {
    using LibIntOrAString for IntOrAString;

    /// @notice Whether `value` is an IntOrAString built by `fromStringV3`: the
    /// truthy bits set and nothing above the string's bytes.
    /// @param value The value to check.
    /// @return Whether it is an IntOrAString string.
    function isIntOrAStringV3(bytes32 value) internal pure returns (bool) {
        uint256 raw = uint256(value);
        uint256 length = raw & LENGTH_MASK_V3;
        return (raw & TRUTHY_BITS_V3) == TRUTHY_BITS_V3 && (raw >> ((length + 1) * 8)) == 0;
    }

    /// @notice Hashes the concatenated strings of `inputs`.
    /// @param inputs IntOrAString strings, in source order.
    /// @return One output, the keccak256 of the concatenation.
    //slither-disable-next-line dead-code
    function run(OperandV2, StackItem[] memory inputs) internal pure returns (StackItem[] memory) {
        bytes memory joined;
        for (uint256 i = 0; i < inputs.length; i++) {
            bytes32 value = StackItem.unwrap(inputs[i]);
            if (!isIntOrAStringV3(value)) {
                revert NotAString(i, value);
            }
            joined = bytes.concat(joined, bytes(IntOrAString.wrap(uint256(value)).toStringV3()));
        }
        StackItem[] memory outputs = new StackItem[](1);
        outputs[0] = StackItem.wrap(keccak256(joined));
        return outputs;
    }

    /// @notice One or more inputs, one output.
    /// @param inputs The number of inputs the expression gives.
    /// @return The number of inputs, unchanged.
    /// @return One output.
    //slither-disable-next-line dead-code
    function integrity(OperandV2, uint256 inputs, uint256) internal pure returns (uint256, uint256) {
        if (inputs == 0) {
            revert Utf8HashNoInputs();
        }
        return (inputs, 1);
    }

    /// @notice Compiles `utf8-hash` to an extern call into this contract.
    /// @return Whether the sub parse succeeded.
    /// @return The bytecode for the extern opcode.
    /// @return The constants for the extern opcode.
    //slither-disable-next-line dead-code
    function subParser(uint256 constantsHeight, uint256 ioByte, OperandV2 operand)
        internal
        view
        returns (bool, bytes memory, bytes32[] memory)
    {
        //slither-disable-next-line unused-return
        return LibSubParse.subParserExtern(
            IInterpreterExternV4(address(this)), constantsHeight, ioByte, operand, OP_INDEX_UTF8_HASH
        );
    }
}

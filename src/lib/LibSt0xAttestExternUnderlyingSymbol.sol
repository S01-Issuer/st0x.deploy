// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {OperandV2} from "rainlang-0.2.41/src/interface/IInterpreterV4.sol";
import {IInterpreterExternV4, StackItem} from "rainlang-0.2.41/src/interface/IInterpreterExternV4.sol";
import {LibSubParse} from "rainlang-0.2.41/src/lib/parse/LibSubParse.sol";
import {LibIntOrAString, IntOrAString, LENGTH_MASK_V3} from "rain-intorastring-0.1.5/src/lib/LibIntOrAString.sol";

import {IStoxUnderlyingV1} from "../interface/IStoxUnderlyingV1.sol";
import {UnderlyingSymbolEmpty, UnderlyingSymbolTooLong} from "../error/ErrSt0xAttest.sol";

/// @dev Index of `underlying-symbol` in the extern opcode table.
uint256 constant EXTERN_OP_UNDERLYING_SYMBOL = 0;

/// @title LibSt0xAttestExternUnderlyingSymbol
/// @notice `underlying-symbol`: one input, a token address; one output, its
/// `IStoxUnderlyingV1.underlyingSymbol()` as an IntOrAString bytes32.
library LibSt0xAttestExternUnderlyingSymbol {
    //slither-disable-next-line dead-code
    function run(OperandV2, StackItem[] memory inputs) internal view returns (StackItem[] memory) {
        address token = address(uint160(uint256(StackItem.unwrap(inputs[0]))));
        string memory symbol = IStoxUnderlyingV1(token).underlyingSymbol();
        if (bytes(symbol).length == 0) revert UnderlyingSymbolEmpty(token);
        // `fromStringV3` keeps the length mod 32, so a longer ticker would alias a shorter one.
        if (bytes(symbol).length > LENGTH_MASK_V3) revert UnderlyingSymbolTooLong(token, bytes(symbol).length);
        StackItem[] memory outputs = new StackItem[](1);
        outputs[0] = StackItem.wrap(bytes32(IntOrAString.unwrap(LibIntOrAString.fromStringV3(symbol))));
        return outputs;
    }

    //slither-disable-next-line dead-code
    function integrity(OperandV2, uint256, uint256) internal pure returns (uint256, uint256) {
        return (1, 1);
    }

    //slither-disable-next-line dead-code
    function subParser(uint256 constantsHeight, uint256 ioByte, OperandV2 operand)
        internal
        view
        returns (bool, bytes memory, bytes32[] memory)
    {
        //slither-disable-next-line unused-return
        return LibSubParse.subParserExtern(
            IInterpreterExternV4(address(this)), constantsHeight, ioByte, operand, EXTERN_OP_UNDERLYING_SYMBOL
        );
    }
}

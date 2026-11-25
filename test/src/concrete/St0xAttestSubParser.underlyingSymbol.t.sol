// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";
import {SignedContextV2} from "rainlang-0.2.41/src/interface/IInterpreterCallerV5.sol";
import {
    EvalV4,
    SourceIndexV2,
    StackItem,
    FullyQualifiedNamespace,
    OperandV2
} from "rainlang-0.2.41/src/interface/IInterpreterV4.sol";
import {ExternOpcodeOutOfRange} from "rainlang-0.2.41/src/error/ErrExtern.sol";
import {LibExtern} from "rainlang-0.2.41/src/lib/extern/LibExtern.sol";
import {LibIntOrAString, IntOrAString} from "rain-intorastring-0.1.5/src/lib/LibIntOrAString.sol";

import {St0xAttestSubParserTest} from "test/src/concrete/St0xAttestSubParserTest.sol";
import {MockERC20} from "test/concrete/MockERC20.sol";
import {LibSt0xAttestContext} from "src/lib/LibSt0xAttestContext.sol";
import {EXTERN_OPCODES_LENGTH} from "src/lib/LibSt0xAttestSubParser.sol";
import {EXTERN_OP_UNDERLYING_SYMBOL} from "src/lib/LibSt0xAttestExternUnderlyingSymbol.sol";
import {UnderlyingSymbolEmpty, UnderlyingSymbolTooLong} from "src/error/ErrSt0xAttest.sol";

/// `underlying-symbol(token)` reads `token`'s `underlyingSymbol()` at eval, as
/// the string a Rainlang literal of the ticker parses to.
contract St0xAttestSubParserUnderlyingSymbolTest is St0xAttestSubParserTest {
    string internal constant WORD = "underlying-symbol(mint-token())";

    function mintGrid(address token) internal view returns (bytes32[][] memory) {
        return LibSt0xAttestContext.build(tokenWord(token), float(1), new SignedContextV2[](0));
    }

    function repeated(bytes1 fill, uint256 length) internal pure returns (string memory) {
        bytes memory out = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            out[i] = fill;
        }
        return string(out);
    }

    function evalExternal(bytes memory bytecode, bytes32[][] memory context) external view {
        I_INTERPRETER.eval4(
            EvalV4({
                store: I_STORE,
                namespace: FullyQualifiedNamespace.wrap(0),
                bytecode: bytecode,
                sourceIndex: SourceIndexV2.wrap(0),
                context: context,
                inputs: new StackItem[](0),
                stateOverlay: new bytes32[](0)
            })
        );
    }

    function testTheTickerReadsAsItsStringLiteral() external {
        address token = underlyingToken("AAPL");
        bytes32[][] memory context = mintGrid(token);
        checkWord(WORD, context, symbol("AAPL"));
        parseAndEval(
            bytes(
                string.concat(
                    usingWords(), ":ensure(binary-equal-to(underlying-symbol(mint-token()) \"AAPL\") \"ticker\");"
                )
            ),
            context
        );
    }

    function testATickerOfOneTo31BytesReadsBack(bytes32 seed, uint256 length) external {
        length = bound(length, 1, 31);
        bytes memory ticker = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            ticker[i] = seed[i];
        }
        address token = underlyingToken(string(ticker));
        bytes32 read = evalWord(WORD, mintGrid(token));
        assertEq(read, symbol(string(ticker)), "ticker");
        assertEq(LibIntOrAString.toStringV3(IntOrAString.wrap(uint256(read))), string(ticker), "round trip");
    }

    function testA31ByteTickerReadsBack() external {
        string memory ticker = repeated("A", 31);
        address token = underlyingToken(ticker);
        checkWord(WORD, mintGrid(token), symbol(ticker));
    }

    function testReadsTheUnderlyingSymbolNotTheSymbol() external {
        address token = underlyingToken("AAPL");
        assertEq(IERC20Metadata(token).symbol(), "tAAPL", "premise: the token's symbol");
        bytes32 read = evalWord(WORD, mintGrid(token));
        assertEq(read, symbol("AAPL"), "underlying symbol");
        assertNotEq(read, symbol("tAAPL"), "not the symbol");
    }

    function testAnEmptyTickerReverts() external {
        address token = underlyingToken("");
        checkWordReverts(WORD, mintGrid(token), abi.encodeWithSelector(UnderlyingSymbolEmpty.selector, token));
    }

    function testA32ByteTickerReverts() external {
        address token = underlyingToken(repeated("A", 32));
        checkWordReverts(WORD, mintGrid(token), abi.encodeWithSelector(UnderlyingSymbolTooLong.selector, token, 32));
    }

    function testATickerOver31BytesReverts(uint256 length) external {
        length = bound(length, 32, 4096);
        address token = underlyingToken(repeated("A", length));
        checkWordReverts(WORD, mintGrid(token), abi.encodeWithSelector(UnderlyingSymbolTooLong.selector, token, length));
    }

    function testATokenWithoutAnUnderlyingSymbolRevertsWithNoReason() external {
        address token = address(new MockERC20());
        bytes memory bytecode = I_COMPILER.parse2(bytes(string.concat(usingWords(), "_: ", WORD, ";")));
        try this.evalExternal(bytecode, mintGrid(token)) {
            revert("the eval was expected to revert");
        } catch (bytes memory reason) {
            assertEq(reason.length, 0, "no reason");
        }
    }

    function testExternIntegrityIsOneInputOneOutput(uint16 operand, uint256 expectedInputs, uint256 expectedOutputs)
        external
        view
    {
        (uint256 inputs, uint256 outputs) = I_SUB_PARSER.externIntegrity(
            LibExtern.encodeExternDispatch(EXTERN_OP_UNDERLYING_SYMBOL, OperandV2.wrap(bytes32(uint256(operand)))),
            expectedInputs,
            expectedOutputs
        );
        assertEq(inputs, 1, "inputs");
        assertEq(outputs, 1, "outputs");
    }

    function testExternIntegrityOutOfRangeOpcodeReverts(uint16 opcode) external {
        opcode = uint16(bound(opcode, EXTERN_OPCODES_LENGTH, type(uint16).max));
        vm.expectRevert(abi.encodeWithSelector(ExternOpcodeOutOfRange.selector, opcode, EXTERN_OPCODES_LENGTH));
        I_SUB_PARSER.externIntegrity(LibExtern.encodeExternDispatch(opcode, OperandV2.wrap(0)), 1, 1);
    }
}

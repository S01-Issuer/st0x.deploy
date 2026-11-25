// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {stdError} from "forge-std-1.17.0/src/StdError.sol";
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
import {
    UnderlyingSymbolEmpty,
    UnderlyingSymbolTooLong,
    UnderlyingSymbolNotAnAddress
} from "src/error/ErrSt0xAttest.sol";
import {IStoxUnderlyingV1} from "src/interface/IStoxUnderlyingV1.sol";

/// `underlying-symbol(token)` reads `token`'s `underlyingSymbol()` at eval, as
/// the string a Rainlang literal of the ticker parses to.
contract St0xAttestSubParserUnderlyingSymbolTest is St0xAttestSubParserTest {
    string internal constant WORD = "underlying-symbol(mint-token())";

    function mintGrid(address token) internal view returns (bytes32[][] memory) {
        return mintGrid(tokenWord(token));
    }

    function mintGrid(bytes32 mintToken) internal view returns (bytes32[][] memory) {
        return LibSt0xAttestContext.build(mintToken, float(1), new SignedContextV2[](0));
    }

    /// `token` with `high` in the bits above its 160.
    function dirty(address token, uint256 high) internal pure returns (bytes32) {
        return bytes32((high << 160) | uint256(uint160(token)));
    }

    function one(bytes32 input) internal pure returns (StackItem[] memory) {
        StackItem[] memory inputs = new StackItem[](1);
        inputs[0] = StackItem.wrap(input);
        return inputs;
    }

    function externCall(uint256 opcode, uint16 operand, StackItem[] memory inputs)
        internal
        view
        returns (StackItem[] memory)
    {
        return I_SUB_PARSER.extern(
            LibExtern.encodeExternDispatch(opcode, OperandV2.wrap(bytes32(uint256(operand)))), inputs
        );
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

    function testExternReadsTheTicker(uint16 operand) external {
        address token = underlyingToken("AAPL");
        StackItem[] memory outputs = externCall(EXTERN_OP_UNDERLYING_SYMBOL, operand, one(tokenWord(token)));
        assertEq(outputs.length, 1, "outputs");
        assertEq(StackItem.unwrap(outputs[0]), symbol("AAPL"), "ticker");
    }

    function testExternOpcodesWrapModTheTable(uint16 opcode, uint16 operand) external {
        opcode = uint16(bound(opcode, EXTERN_OPCODES_LENGTH, type(uint16).max));
        vm.assume(opcode % EXTERN_OPCODES_LENGTH == EXTERN_OP_UNDERLYING_SYMBOL);
        address token = underlyingToken("AAPL");
        StackItem[] memory outputs = externCall(opcode, operand, one(tokenWord(token)));
        assertEq(outputs.length, 1, "outputs");
        assertEq(StackItem.unwrap(outputs[0]), symbol("AAPL"), "ticker");
    }

    function testExternWithNoInputsPanics() external {
        vm.expectRevert(stdError.indexOOBError);
        externCall(EXTERN_OP_UNDERLYING_SYMBOL, 0, new StackItem[](0));
    }

    function testExternRefusesAnInputWithBitsAboveAnAddress(uint256 high) external {
        high = bound(high, 1, type(uint96).max);
        bytes32 input = dirty(underlyingToken("AAPL"), high);
        vm.expectRevert(abi.encodeWithSelector(UnderlyingSymbolNotAnAddress.selector, input));
        externCall(EXTERN_OP_UNDERLYING_SYMBOL, 0, one(input));
    }

    function testAMintTokenWithBitsAboveAnAddressReverts(uint256 high) external {
        high = bound(high, 1, type(uint96).max);
        bytes32 input = dirty(underlyingToken("AAPL"), high);
        checkWordReverts(WORD, mintGrid(input), abi.encodeWithSelector(UnderlyingSymbolNotAnAddress.selector, input));
    }

    /// Bit 160 alone and bit 255 alone, over a token whose ticker the low 160
    /// bits alone read.
    function testTheLowestAndHighestBitAboveAnAddressEachRevert() external {
        address token = underlyingToken("AAPL");
        checkWord(WORD, mintGrid(token), symbol("AAPL"));
        uint256[2] memory highs = [uint256(1), uint256(1) << 95];
        for (uint256 i = 0; i < highs.length; i++) {
            bytes32 input = dirty(token, highs[i]);
            checkWordReverts(
                WORD, mintGrid(input), abi.encodeWithSelector(UnderlyingSymbolNotAnAddress.selector, input)
            );
        }
    }

    function testTheHighestAddressReadsItsTicker() external {
        address token = address(type(uint160).max);
        vm.etch(token, hex"00");
        vm.mockCall(token, abi.encodeWithSelector(IStoxUnderlyingV1.underlyingSymbol.selector), abi.encode("AAPL"));
        checkWord(WORD, mintGrid(token), symbol("AAPL"));
    }
}

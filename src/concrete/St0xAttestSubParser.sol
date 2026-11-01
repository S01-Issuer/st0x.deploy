// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    BaseRainlangSubParser,
    IParserToolingV1,
    ISubParserToolingV1,
    OperandV2
} from "rainlang-0.2.30/src/abstract/BaseRainlangSubParser.sol";
import {BaseRainlangExtern} from "rainlang-0.2.30/src/abstract/BaseRainlangExtern.sol";
import {StackItem} from "rainlang-0.2.30/src/interface/IInterpreterExternV4.sol";
import {IOpcodeToolingV1} from "rain-sol-codegen-0.1.39/src/interface/IOpcodeToolingV1.sol";
import {IIntegrityToolingV1} from "rain-sol-codegen-0.1.39/src/interface/IIntegrityToolingV1.sol";
import {LibParseOperand} from "rainlang-0.2.30/src/lib/parse/LibParseOperand.sol";
import {BadDynamicLength} from "rainlang-0.2.30/src/error/ErrOpList.sol";
import {LibConvert} from "rain-lib-typecast-0.1.4/src/LibConvert.sol";
import {IDescribedByMetaV1} from "rain-metadata-0.1.43/src/interface/IDescribedByMetaV1.sol";

import {LibSt0xAttestSubParser, SUB_PARSER_WORD_PARSERS_LENGTH} from "../lib/LibSt0xAttestSubParser.sol";
import {LibOpUtf8Hash} from "../lib/op/LibOpUtf8Hash.sol";
import {
    DESCRIBED_BY_META_HASH,
    PARSE_META as SUB_PARSER_PARSE_META,
    SUB_PARSER_WORD_PARSERS,
    OPERAND_HANDLER_FUNCTION_POINTERS as SUB_PARSER_OPERAND_HANDLERS,
    OPCODE_FUNCTION_POINTERS,
    INTEGRITY_FUNCTION_POINTERS
} from "../generated/St0xAttestSubParserPointers.sol";

/// @title St0xAttestSubParser
/// @notice Registered in an expression with `using-words-from`, provides
/// `lead`, `attestor<N>`, `lead-symbol`, `lead-price`, `lead-time`,
/// `attested-symbol<N>`, `attested-price<N>`, `attested-time<N>`,
/// `mint-symbol`, `mint-amount`, `lead-domain`, `attestor-domain<N>`,
/// `lead-source`, `lead-currency`, `attested-source<N>` and
/// `attested-currency<N>`, each of which compiles to a `context` read of the
/// grid in `LibSt0xAttestContext`, and `utf8-hash`, which compiles to an
/// extern call into this contract.
///
/// Every table the base contract dispatches on is a constant from
/// `src/generated/St0xAttestSubParserPointers.sol`, which
/// `script/BuildPointers.sol` regenerates from the `build*` functions below.
/// @dev The number of extern opcodes. Only `utf8-hash` runs in the extern.
uint256 constant OPCODE_FUNCTION_POINTERS_LENGTH = 1;

contract St0xAttestSubParser is BaseRainlangSubParser, BaseRainlangExtern {
    /// @inheritdoc IDescribedByMetaV1
    function describedByMetaV1() external pure returns (bytes32) {
        return DESCRIBED_BY_META_HASH;
    }

    /// @inheritdoc BaseRainlangSubParser
    function subParserParseMeta() internal pure virtual override returns (bytes memory) {
        return SUB_PARSER_PARSE_META;
    }

    /// @inheritdoc BaseRainlangSubParser
    function subParserWordParsers() internal pure virtual override returns (bytes memory) {
        return SUB_PARSER_WORD_PARSERS;
    }

    /// @inheritdoc BaseRainlangSubParser
    function subParserOperandHandlers() internal pure virtual override returns (bytes memory) {
        return SUB_PARSER_OPERAND_HANDLERS;
    }

    /// @inheritdoc BaseRainlangExtern
    function opcodeFunctionPointers() internal pure virtual override returns (bytes memory) {
        return OPCODE_FUNCTION_POINTERS;
    }

    /// @inheritdoc BaseRainlangExtern
    function integrityFunctionPointers() internal pure virtual override returns (bytes memory) {
        return INTEGRITY_FUNCTION_POINTERS;
    }

    /// @notice No literals. Every value an expression needs is a context cell
    /// named by a word, or a standard Rainlang literal.
    /// @inheritdoc IParserToolingV1
    function buildLiteralParserFunctionPointers() external pure override returns (bytes memory) {
        return "";
    }

    /// @notice One handler per word, in word index order. The words with an
    /// `<N>` take exactly one operand; the rest take none.
    /// @inheritdoc IParserToolingV1
    function buildOperandHandlerFunctionPointers() external pure override returns (bytes memory) {
        unchecked {
            function(bytes32[] memory) internal pure returns (OperandV2) lengthPointer;
            uint256 length = SUB_PARSER_WORD_PARSERS_LENGTH;
            assembly ("memory-safe") {
                lengthPointer := length
            }
            function(bytes32[] memory) internal pure returns (OperandV2)[SUB_PARSER_WORD_PARSERS_LENGTH + 1] memory
                handlersFixed = [
                    lengthPointer,
                    // lead
                    LibParseOperand.handleOperandDisallowed,
                    // attestor<N>
                    LibParseOperand.handleOperandSingleFullNoDefault,
                    // lead-symbol
                    LibParseOperand.handleOperandDisallowed,
                    // lead-price
                    LibParseOperand.handleOperandDisallowed,
                    // lead-time
                    LibParseOperand.handleOperandDisallowed,
                    // attested-symbol<N>
                    LibParseOperand.handleOperandSingleFullNoDefault,
                    // attested-price<N>
                    LibParseOperand.handleOperandSingleFullNoDefault,
                    // attested-time<N>
                    LibParseOperand.handleOperandSingleFullNoDefault,
                    // mint-symbol
                    LibParseOperand.handleOperandDisallowed,
                    // mint-amount
                    LibParseOperand.handleOperandDisallowed,
                    // lead-domain
                    LibParseOperand.handleOperandDisallowed,
                    // attestor-domain<N>
                    LibParseOperand.handleOperandSingleFullNoDefault,
                    // lead-source
                    LibParseOperand.handleOperandDisallowed,
                    // lead-currency
                    LibParseOperand.handleOperandDisallowed,
                    // attested-source<N>
                    LibParseOperand.handleOperandSingleFullNoDefault,
                    // attested-currency<N>
                    LibParseOperand.handleOperandSingleFullNoDefault,
                    // utf8-hash
                    LibParseOperand.handleOperandDisallowed
                ];
            uint256[] memory handlersDynamic;
            assembly ("memory-safe") {
                handlersDynamic := handlersFixed
            }
            if (handlersDynamic.length != length) {
                revert BadDynamicLength(handlersDynamic.length, length);
            }
            return LibConvert.unsafeTo16BitBytes(handlersDynamic);
        }
    }

    /// @notice One parser per word, in word index order.
    /// @inheritdoc ISubParserToolingV1
    function buildSubParserWordParsers() external pure override returns (bytes memory) {
        unchecked {
            function(uint256, uint256, OperandV2) internal view returns (bool, bytes memory, bytes32[] memory)
                lengthPointer;
            uint256 length = SUB_PARSER_WORD_PARSERS_LENGTH;
            assembly ("memory-safe") {
                lengthPointer := length
            }
            function(uint256, uint256, OperandV2)
                internal
                view returns (bool, bytes memory, bytes32[] memory)[SUB_PARSER_WORD_PARSERS_LENGTH + 1] memory
                parsersFixed = [
                    lengthPointer,
                    LibSt0xAttestSubParser.subParserLead,
                    LibSt0xAttestSubParser.subParserAttestor,
                    LibSt0xAttestSubParser.subParserLeadSymbol,
                    LibSt0xAttestSubParser.subParserLeadPrice,
                    LibSt0xAttestSubParser.subParserLeadTime,
                    LibSt0xAttestSubParser.subParserAttestedSymbol,
                    LibSt0xAttestSubParser.subParserAttestedPrice,
                    LibSt0xAttestSubParser.subParserAttestedTime,
                    LibSt0xAttestSubParser.subParserMintSymbol,
                    LibSt0xAttestSubParser.subParserMintAmount,
                    LibSt0xAttestSubParser.subParserLeadDomain,
                    LibSt0xAttestSubParser.subParserAttestorDomain,
                    LibSt0xAttestSubParser.subParserLeadSource,
                    LibSt0xAttestSubParser.subParserLeadCurrency,
                    LibSt0xAttestSubParser.subParserAttestedSource,
                    LibSt0xAttestSubParser.subParserAttestedCurrency,
                    LibOpUtf8Hash.subParser
                ];
            uint256[] memory parsersDynamic;
            assembly ("memory-safe") {
                parsersDynamic := parsersFixed
            }
            if (parsersDynamic.length != length) {
                revert BadDynamicLength(parsersDynamic.length, length);
            }
            return LibConvert.unsafeTo16BitBytes(parsersDynamic);
        }
    }

    /// @notice One opcode, `utf8-hash`.
    /// @inheritdoc IOpcodeToolingV1
    function buildOpcodeFunctionPointers() external pure override returns (bytes memory) {
        unchecked {
            function(OperandV2, StackItem[] memory) internal view returns (StackItem[] memory) lengthPointer;
            uint256 length = OPCODE_FUNCTION_POINTERS_LENGTH;
            assembly ("memory-safe") {
                lengthPointer := length
            }
            function(OperandV2, StackItem[] memory)
                internal
                view returns (StackItem[] memory)[OPCODE_FUNCTION_POINTERS_LENGTH + 1] memory
                pointersFixed = [lengthPointer, LibOpUtf8Hash.run];
            uint256[] memory pointersDynamic;
            assembly ("memory-safe") {
                pointersDynamic := pointersFixed
            }
            if (pointersDynamic.length != length) {
                revert BadDynamicLength(pointersDynamic.length, length);
            }
            return LibConvert.unsafeTo16BitBytes(pointersDynamic);
        }
    }

    /// @notice One integrity check per opcode, in opcode order.
    /// @inheritdoc IIntegrityToolingV1
    function buildIntegrityFunctionPointers() external pure override returns (bytes memory) {
        unchecked {
            function(OperandV2, uint256, uint256) internal pure returns (uint256, uint256) lengthPointer;
            uint256 length = OPCODE_FUNCTION_POINTERS_LENGTH;
            assembly ("memory-safe") {
                lengthPointer := length
            }
            function(OperandV2, uint256, uint256)
                internal
                pure returns (uint256, uint256)[OPCODE_FUNCTION_POINTERS_LENGTH + 1] memory
                pointersFixed = [lengthPointer, LibOpUtf8Hash.integrity];
            uint256[] memory pointersDynamic;
            assembly ("memory-safe") {
                pointersDynamic := pointersFixed
            }
            if (pointersDynamic.length != length) {
                revert BadDynamicLength(pointersDynamic.length, length);
            }
            return LibConvert.unsafeTo16BitBytes(pointersDynamic);
        }
    }

    /// @inheritdoc BaseRainlangSubParser
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(BaseRainlangSubParser, BaseRainlangExtern)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

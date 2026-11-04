// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Strings} from "@openzeppelin-contracts-5.7.0/utils/Strings.sol";
import {MessageHashUtils} from "@openzeppelin-contracts-5.7.0/utils/cryptography/MessageHashUtils.sol";
import {LibRainDeploy} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {SignedContextV2, SIGNED_CONTEXT_V2_TYPEHASH} from "rainlang-0.2.31/src/interface/IInterpreterCallerV5.sol";
import {
    EvalV4,
    SourceIndexV2,
    StackItem,
    FullyQualifiedNamespace
} from "rainlang-0.2.31/src/interface/IInterpreterV4.sol";
import {StateNamespace} from "rainlang-0.2.31/src/interface/IInterpreterStoreV3.sol";
import {LibNamespace} from "rainlang-0.2.31/src/lib/ns/LibNamespace.sol";
import {BaseRainlangStore} from "rainlang-0.2.31/src/abstract/BaseRainlangStore.sol";
import {BaseRainlangParser} from "rainlang-0.2.31/src/abstract/BaseRainlangParser.sol";
import {BaseRainlangInterpreter} from "rainlang-0.2.31/src/abstract/BaseRainlangInterpreter.sol";
import {BaseRainlangCompiler} from "rainlang-0.2.31/src/abstract/BaseRainlangCompiler.sol";
import {
    LibTestInterpreterDeploy,
    TEST_PARSER_ADDRESS,
    TEST_STORE_ADDRESS,
    TEST_INTERPRETER_ADDRESS,
    TEST_COMPILER_ADDRESS
} from "rainlang-0.2.31/test/lib/deploy/LibTestInterpreterDeploy.sol";
import {
    CREATION_CODE as DECIMAL_FLOAT_CREATION_CODE,
    DEPLOYED_ADDRESS as DECIMAL_FLOAT_ADDRESS,
    BYTECODE_HASH as DECIMAL_FLOAT_BYTECODE_HASH
} from "rain-math-float-deploy-0.1.9/src/generated/0_1_6/DecimalFloat.sol";
import {LibDecimalFloat, Float} from "rain-math-float-0.3.11/src/lib/LibDecimalFloat.sol";
import {LibIntOrAString, IntOrAString} from "rain-intorastring-0.1.4/src/lib/LibIntOrAString.sol";

import {St0xAttestSubParser} from "src/concrete/St0xAttestSubParser.sol";
import {LibSt0xAttestContext, CONTEXT_ATTESTATION_ROWS} from "src/lib/LibSt0xAttestContext.sol";
import {LibProdDeployV4} from "src/generated/LibProdDeployV4.sol";
import {LibTestTofu} from "test/lib/LibTestTofu.sol";
import {BuildWeightingBindings} from "script/BuildWeightingBindings.sol";

/// @title St0xAttestSubParserTest
/// @notice Binds a `St0xAttestSubParser` beside the test Rainlang etched at
/// its fixed addresses, and signs attestations the way a caller would, so the
/// tests parse and eval real expressions over a real grid.
abstract contract St0xAttestSubParserTest is Test, BuildWeightingBindings {
    using Strings for address;

    //solhint-disable-next-line private-vars-leading-underscore
    BaseRainlangCompiler internal immutable I_COMPILER;
    //solhint-disable-next-line private-vars-leading-underscore
    BaseRainlangInterpreter internal immutable I_INTERPRETER;
    //solhint-disable-next-line private-vars-leading-underscore
    BaseRainlangStore internal immutable I_STORE;
    //solhint-disable-next-line private-vars-leading-underscore
    BaseRainlangParser internal immutable I_PARSER;
    //solhint-disable-next-line private-vars-leading-underscore
    St0xAttestSubParser internal immutable I_SUB_PARSER;

    constructor() {
        LibTestInterpreterDeploy.etchTestRainlang(vm);
        I_PARSER = BaseRainlangParser(TEST_PARSER_ADDRESS);
        I_STORE = BaseRainlangStore(TEST_STORE_ADDRESS);
        I_INTERPRETER = BaseRainlangInterpreter(TEST_INTERPRETER_ADDRESS);
        I_COMPILER = BaseRainlangCompiler(TEST_COMPILER_ADDRESS);

        LibTestTofu.deployTofu(vm);
        if (DECIMAL_FLOAT_ADDRESS.codehash != DECIMAL_FLOAT_BYTECODE_HASH) {
            LibRainDeploy.etchZoltuFactory(vm);
            LibRainDeploy.deployZoltu(DECIMAL_FLOAT_CREATION_CODE);
        }

        I_SUB_PARSER = St0xAttestSubParser(LibRainDeploy.etchAndDeployZoltu(vm, type(St0xAttestSubParser).creationCode));
        require(
            address(I_SUB_PARSER) == LibProdDeployV4.ST0X_ATTEST_SUB_PARSER_CANDIDATE, "sub-parser not at candidate"
        );
    }

    /// Parses `rainString` and evals its first source against `context` in
    /// this contract's namespace.
    function parseAndEval(bytes memory rainString, bytes32[][] memory context)
        internal
        view
        returns (StackItem[] memory, bytes32[] memory)
    {
        return I_INTERPRETER.eval4(
            EvalV4({
                store: I_STORE,
                namespace: LibNamespace.qualifyNamespace(StateNamespace.wrap(0), address(this)),
                bytecode: I_COMPILER.parse2(rainString),
                sourceIndex: SourceIndexV2.wrap(0),
                context: context,
                inputs: new StackItem[](0),
                stateOverlay: new bytes32[](0)
            })
        );
    }

    /// Asserts that parsing `rainString` reverts with `err`.
    function checkUnhappyParse2(bytes memory rainString, bytes memory err) internal {
        vm.expectRevert(err);
        I_COMPILER.parse2(rainString);
    }

    /// The `using-words-from` pragma for the subparser under test.
    function usingWords() internal view returns (string memory) {
        return string.concat("using-words-from ", address(I_SUB_PARSER).toHexString(), "\n");
    }

    /// A symbol as the grid holds it and as a Rainlang string literal parses.
    function symbol(string memory s) internal pure returns (bytes32) {
        return bytes32(IntOrAString.unwrap(LibIntOrAString.fromStringV3(s)));
    }

    /// An integer as a Rain Float.
    function float(int256 value) internal pure returns (bytes32) {
        return Float.unwrap(LibDecimalFloat.packLossless(value, 0));
    }

    /// The signers column encoding of an address.
    function signer(address account) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(account)));
    }

    function priceDomain() internal pure returns (bytes32) {
        return
            MessageHashUtils.toDomainSeparator(bytes1(0x03), string("prices"), string("1"), 0, address(0), bytes32(0));
    }

    /// The EIP-712 digest of a `SignedContextV2` by `account` over `context`
    /// under `domain`, from the typed-data encoding rather than `LibContext`.
    function digest(bytes32 domain, address account, bytes32[] memory context) internal pure returns (bytes32) {
        bytes32 structHash =
            keccak256(abi.encode(SIGNED_CONTEXT_V2_TYPEHASH, account, keccak256(abi.encodePacked(context))));
        return keccak256(abi.encodePacked(hex"1901", domain, structHash));
    }

    /// An attestation column `[symbol, price, time]`.
    function attestation(bytes32 attestedSymbol, bytes32 price, bytes32 time) internal pure returns (bytes32[] memory) {
        bytes32[] memory context = new bytes32[](CONTEXT_ATTESTATION_ROWS);
        context[0] = attestedSymbol;
        context[1] = price;
        context[2] = time;
        return context;
    }

    /// An attestation of `[symbol, price, time]` signed by `key` under
    /// `priceDomain()`.
    function attest(uint256 key, bytes32 attestedSymbol, bytes32 price, bytes32 time)
        internal
        pure
        returns (SignedContextV2 memory)
    {
        return attestUnder(key, priceDomain(), attestedSymbol, price, time);
    }

    /// An attestation of `[symbol, price, time]` signed by `key` under
    /// `domain`.
    function attestUnder(uint256 key, bytes32 domain, bytes32 attestedSymbol, bytes32 price, bytes32 time)
        internal
        pure
        returns (SignedContextV2 memory)
    {
        return signUnder(key, domain, attestation(attestedSymbol, price, time));
    }

    /// Signs an arbitrary column as an attestation under `priceDomain()`, for
    /// the tests that need a malformed one.
    function sign(uint256 key, bytes32[] memory context) internal pure returns (SignedContextV2 memory) {
        return signUnder(key, priceDomain(), context);
    }

    /// Signs `context` by `key`'s own account under `domain`.
    function signUnder(uint256 key, bytes32 domain, bytes32[] memory context)
        internal
        pure
        returns (SignedContextV2 memory)
    {
        return signFor(vm.addr(key), key, domain, context);
    }

    /// A `SignedContextV2` naming `account` as its signer, with `key`'s ECDSA
    /// signature over the digest for `account`.
    function signFor(address account, uint256 key, bytes32 domain, bytes32[] memory context)
        internal
        pure
        returns (SignedContextV2 memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest(domain, account, context));
        return SignedContextV2({
            signer: account, domainSeparator: domain, context: context, signature: abi.encodePacked(r, s, v)
        });
    }

    /// Evals `word` as the only stack item against `context`.
    function evalWord(string memory word, bytes32[][] memory context) internal view returns (bytes32) {
        (StackItem[] memory stack,) = parseAndEval(bytes(string.concat(usingWords(), "_: ", word, ";")), context);
        assertEq(stack.length, 1, word);
        return StackItem.unwrap(stack[0]);
    }

    /// Asserts `word` evals to `expected` against `context`.
    function checkWord(string memory word, bytes32[][] memory context, bytes32 expected) internal view {
        assertEq(evalWord(word, context), expected, word);
    }

    /// Asserts that evaluating `rainlang` against `context` reverts with
    /// `err`. Parsing is expected to succeed.
    function checkEvalReverts(bytes memory rainlang, bytes32[][] memory context, bytes memory err) internal {
        bytes memory bytecode = I_COMPILER.parse2(rainlang);
        vm.expectRevert(err);
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

    /// Asserts that evaluating `word` against `context` reverts with `err`.
    function checkWordReverts(string memory word, bytes32[][] memory context, bytes memory err) internal {
        checkEvalReverts(bytes(string.concat(usingWords(), "_: ", word, ";")), context, err);
    }

    /// A grid with the lead and `poolSize` pool attestors all attesting the
    /// same `[symbol, price, time]`, and the given mint.
    function uniformGrid(
        bytes32 mintSymbol,
        bytes32 mintAmount,
        bytes32 attestedSymbol,
        bytes32 price,
        bytes32 time,
        uint256 poolSize
    ) internal view returns (bytes32[][] memory) {
        SignedContextV2[] memory attestations = new SignedContextV2[](poolSize + 1);
        attestations[0] = attest(LEAD_KEY, attestedSymbol, price, time);
        for (uint256 i = 0; i < poolSize; i++) {
            attestations[i + 1] = attest(OPERATOR_KEY_0 + i, attestedSymbol, price, time);
        }
        return LibSt0xAttestContext.build(mintSymbol, mintAmount, attestations);
    }
}

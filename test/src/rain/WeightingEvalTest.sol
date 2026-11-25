// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Float, LibDecimalFloat} from "rain-math-float-0.3.13/src/lib/LibDecimalFloat.sol";
import {SignedContextV2} from "rainlang-0.2.41/src/interface/IInterpreterCallerV5.sol";
import {EvalV4, SourceIndexV2, StackItem} from "rainlang-0.2.41/src/interface/IInterpreterV4.sol";
import {StateNamespace} from "rainlang-0.2.41/src/interface/IInterpreterStoreV3.sol";
import {LibNamespace} from "rainlang-0.2.41/src/lib/ns/LibNamespace.sol";

import {
    LibSt0xAttestContext,
    CONTEXT_LEAD_COLUMN,
    CONTEXT_ATTESTATION_ROWS,
    CONTEXT_ATTESTATION_ROW_SYMBOL,
    CONTEXT_ATTESTATION_ROW_PRICE,
    CONTEXT_ATTESTATION_ROW_TIME,
    CONTEXT_ATTESTATION_ROW_SOURCE,
    CONTEXT_ATTESTATION_ROW_CURRENCY
} from "src/lib/LibSt0xAttestContext.sol";
import {IStoxUnderlyingV1} from "src/interface/IStoxUnderlyingV1.sol";
import {St0xAttestSubParserTest} from "test/src/concrete/St0xAttestSubParserTest.sol";

abstract contract WeightingEvalTest is St0xAttestSubParserTest {
    using LibDecimalFloat for Float;

    struct Attestation {
        uint256 key;
        bytes32 domain;
        bytes32 attestedSymbol;
        Float price;
        Float time;
        bytes32 priceSource;
        bytes32 currency;
    }

    bytes32 internal constant OTHER_DOMAIN = keccak256("st0x.test.other-domain");

    string internal constant VAULT_SYMBOL = "tMSTR";
    string internal constant TICKER = "MSTR";
    string internal constant OTHER_TICKER = "AAPL";

    int256 internal constant PRICE = 150;
    int256 internal constant AMOUNT = 2;
    int256 internal constant NOW = 1_760_000_000;

    bytes internal bytecode;
    address internal token;
    address internal otherToken;

    function bindingSet() internal pure virtual returns (string memory);

    function setUp() public {
        // forge-lint: disable-next-line(unsafe-typecast)
        vm.warp(uint256(NOW));
        install(bindingSet());
        token = underlyingToken(TICKER);
        otherToken = underlyingToken(OTHER_TICKER);
    }

    function install(string memory set) internal {
        bytecode = I_COMPILER.parse2(bytes(vm.readFile(string.concat(DIR, set, ".rl"))));
    }

    function decimal(int256 coefficient, int256 exponent) internal pure returns (Float) {
        return LibDecimalFloat.packLossless(coefficient, exponent);
    }

    function at(int256 offset) internal pure returns (Float) {
        return decimal(NOW + offset, 0);
    }

    function grid(address mintToken, Float amount, SignedContextV2[] memory signed)
        internal
        view
        returns (bytes32[][] memory)
    {
        return LibSt0xAttestContext.build(tokenWord(mintToken), Float.unwrap(amount), signed);
    }

    function eval(bytes32[][] memory context) internal view returns (StackItem[] memory, bytes32[] memory) {
        return I_INTERPRETER.eval4(
            EvalV4({
                store: I_STORE,
                namespace: LibNamespace.qualifyNamespace(StateNamespace.wrap(0), address(this)),
                bytecode: bytecode,
                sourceIndex: SourceIndexV2.wrap(0),
                context: context,
                inputs: new StackItem[](0),
                stateOverlay: new bytes32[](0)
            })
        );
    }

    function evalReverts(bytes32[][] memory context, bytes memory err) internal {
        vm.expectRevert(err);
        eval(context);
    }

    function ensureError(string memory reason) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("Error(string)", reason);
    }

    function tickerOf(address mintToken) internal view returns (string memory) {
        return IStoxUnderlyingV1(mintToken).underlyingSymbol();
    }

    function leadTimeKey(string memory ticker) internal pure returns (bytes32) {
        return keccak256(abi.encode(symbol("lead-time"), symbol(ticker)));
    }

    function evalAccepted(bytes32[][] memory context, address mintToken, Float value)
        internal
        view
        returns (StackItem[] memory, bytes32[] memory)
    {
        (StackItem[] memory stack, bytes32[] memory writes) = eval(context);
        string memory ticker = tickerOf(mintToken);
        bytes32 key = leadTimeKey(ticker);
        assertEq(writes.length, 2, "writes");
        assertEq(writes[0], key, "lead-time-key write");
        assertEq(writes[1], context[CONTEXT_LEAD_COLUMN][CONTEXT_ATTESTATION_ROW_TIME], "lead-time write");
        assertEq(stack.length, 4, "stack length");
        assertTrue(Float.wrap(StackItem.unwrap(stack[0])).eq(value), "value");
        assertEq(StackItem.unwrap(stack[1]), key, "lead-time-key");
        assertEq(StackItem.unwrap(stack[2]), priceDomain(), "price-domain");
        assertEq(StackItem.unwrap(stack[3]), symbol(ticker), "symbol");
        return (stack, writes);
    }

    function signAll(Attestation[] memory attestations) internal pure returns (SignedContextV2[] memory) {
        SignedContextV2[] memory signed = new SignedContextV2[](attestations.length);
        for (uint256 i = 0; i < attestations.length; i++) {
            bytes32[] memory context = new bytes32[](CONTEXT_ATTESTATION_ROWS);
            context[CONTEXT_ATTESTATION_ROW_SYMBOL] = attestations[i].attestedSymbol;
            context[CONTEXT_ATTESTATION_ROW_PRICE] = Float.unwrap(attestations[i].price);
            context[CONTEXT_ATTESTATION_ROW_TIME] = Float.unwrap(attestations[i].time);
            context[CONTEXT_ATTESTATION_ROW_SOURCE] = attestations[i].priceSource;
            context[CONTEXT_ATTESTATION_ROW_CURRENCY] = attestations[i].currency;
            signed[i] = signUnder(attestations[i].key, attestations[i].domain, context);
        }
        return signed;
    }

    function accepted(address mintToken, Float amount, SignedContextV2[] memory signed, Float value) internal view {
        evalAccepted(grid(mintToken, amount, signed), mintToken, value);
    }

    function signedAt(string memory ticker, Float time) internal view virtual returns (SignedContextV2[] memory);

    function mintGrid(address mintToken, Float time) internal view returns (bytes32[][] memory) {
        return grid(mintToken, decimal(AMOUNT, 0), signedAt(tickerOf(mintToken), time));
    }

    function mintAt(address mintToken, Float time) internal {
        (, bytes32[] memory writes) = evalAccepted(mintGrid(mintToken, time), mintToken, decimal(AMOUNT * PRICE, 0));
        I_STORE.set(StateNamespace.wrap(0), writes);
    }

    function mintRefusedAt(address mintToken, Float time) internal {
        evalReverts(mintGrid(mintToken, time), ensureError("Lead time went backwards"));
    }

    function storedLeadTime(string memory ticker) internal view returns (bytes32) {
        return I_STORE.get(LibNamespace.qualifyNamespace(StateNamespace.wrap(0), address(this)), leadTimeKey(ticker));
    }

    function testTheFirstMintOfATickerIsAcceptedAndStoresItsLeadTime() external {
        assertEq(storedLeadTime(TICKER), bytes32(0), "unset");
        mintAt(token, at(-MAX_TIME_SPREAD));
        assertEq(storedLeadTime(TICKER), Float.unwrap(at(-MAX_TIME_SPREAD)), "stored");
    }

    function testAMintBeforeTheStoredLeadTimeIsRefused() external {
        mintAt(token, at(0));
        mintRefusedAt(token, at(-1));
        mintRefusedAt(token, decimal(NOW * 10 - 1, -1));
        mintRefusedAt(token, at(-MAX_TIME_SPREAD));
        assertEq(storedLeadTime(TICKER), Float.unwrap(at(0)), "unchanged");
    }

    function testAMintAtTheStoredLeadTimeIsAccepted() external {
        mintAt(token, at(0));
        mintAt(token, at(0));
        mintAt(token, decimal(NOW * 10, -1));
        assertTrue(Float.wrap(storedLeadTime(TICKER)).eq(at(0)), "stored");
    }

    function testAMintAfterTheStoredLeadTimeMovesItForward() external {
        mintAt(token, at(-1));
        mintAt(token, at(0));
        assertEq(storedLeadTime(TICKER), Float.unwrap(at(0)), "moved");
        mintRefusedAt(token, at(-1));
    }

    function testEachTickerHasItsOwnLeadTime() external {
        mintAt(token, at(0));
        mintAt(otherToken, at(-1));
        assertEq(storedLeadTime(TICKER), Float.unwrap(at(0)), "ticker");
        assertEq(storedLeadTime(OTHER_TICKER), Float.unwrap(at(-1)), "other ticker");
        mintRefusedAt(token, at(-1));
        mintAt(otherToken, at(-1));
        mintRefusedAt(otherToken, at(-2));
    }

    function testASecondMintIsAcceptedIffItsLeadTimeIsNotBeforeTheFirst(int256 first, int256 second) external {
        first = bound(first, -MAX_TIME_SPREAD, MAX_TIME_SPREAD);
        second = bound(second, -MAX_TIME_SPREAD, MAX_TIME_SPREAD);
        mintAt(token, at(first));
        if (second >= first) {
            mintAt(token, at(second));
            assertEq(storedLeadTime(TICKER), Float.unwrap(at(second)), "stored");
        } else {
            mintRefusedAt(token, at(second));
        }
    }
}

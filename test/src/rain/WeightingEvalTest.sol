// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Float, LibDecimalFloat} from "rain-math-float-0.3.11/src/lib/LibDecimalFloat.sol";
import {SignedContextV2} from "rainlang-0.2.33/src/interface/IInterpreterCallerV5.sol";
import {EvalV4, SourceIndexV2, StackItem} from "rainlang-0.2.33/src/interface/IInterpreterV4.sol";
import {StateNamespace} from "rainlang-0.2.33/src/interface/IInterpreterStoreV3.sol";
import {LibNamespace} from "rainlang-0.2.33/src/lib/ns/LibNamespace.sol";

import {
    LibSt0xAttestContext,
    CONTEXT_LEAD_COLUMN,
    CONTEXT_ATTESTATION_ROW_TIME
} from "src/lib/LibSt0xAttestContext.sol";
import {St0xAttestSubParserTest} from "test/src/concrete/St0xAttestSubParserTest.sol";

abstract contract WeightingEvalTest is St0xAttestSubParserTest {
    using LibDecimalFloat for Float;

    string internal constant VAULT_SYMBOL = "tMSTR";
    string internal constant TICKER = "MSTR";
    string internal constant OTHER_VAULT_SYMBOL = "tAAPL";
    string internal constant OTHER_TICKER = "AAPL";

    int256 internal constant PRICE = 150;
    int256 internal constant AMOUNT = 2;
    int256 internal constant NOW = 1_760_000_000;

    bytes internal bytecode;

    function bindingSet() internal pure virtual returns (string memory);

    function setUp() public {
        // forge-lint: disable-next-line(unsafe-typecast)
        vm.warp(uint256(NOW));
        install(bindingSet());
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

    function grid(string memory vaultSymbol, Float amount, SignedContextV2[] memory signed)
        internal
        view
        returns (bytes32[][] memory)
    {
        return LibSt0xAttestContext.build(symbol(vaultSymbol), Float.unwrap(amount), signed);
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

    function tickerOf(string memory vaultSymbol) internal pure returns (string memory) {
        bytes memory vault = bytes(vaultSymbol);
        bytes memory ticker = new bytes(vault.length - 1);
        for (uint256 i = 1; i < vault.length; i++) {
            ticker[i - 1] = vault[i];
        }
        return string(ticker);
    }

    function leadTimeKey(string memory ticker) internal pure returns (bytes32) {
        return keccak256(abi.encode(symbol("lead-time"), symbol(ticker)));
    }

    function evalAccepted(bytes32[][] memory context, string memory vaultSymbol, Float value)
        internal
        view
        returns (StackItem[] memory, bytes32[] memory)
    {
        (StackItem[] memory stack, bytes32[] memory writes) = eval(context);
        bytes32 key = leadTimeKey(tickerOf(vaultSymbol));
        assertEq(writes.length, 2, "writes");
        assertEq(writes[0], key, "lead-time-key write");
        assertEq(writes[1], context[CONTEXT_LEAD_COLUMN][CONTEXT_ATTESTATION_ROW_TIME], "lead-time write");
        assertEq(stack.length, 7, "stack length");
        assertTrue(Float.wrap(StackItem.unwrap(stack[0])).eq(value), "value");
        assertEq(StackItem.unwrap(stack[1]), key, "lead-time-key");
        assertEq(StackItem.unwrap(stack[2]), symbol(tickerOf(vaultSymbol)), "ticker");
        assertEq(StackItem.unwrap(stack[3]), bytes32(uint256(uint8(bytes(vaultSymbol)[0]))), "symbol-first");
        assertEq(StackItem.unwrap(stack[4]), bytes32(uint256(1) << (8 * bytes(vaultSymbol).length)), "symbol-scale");
        assertEq(StackItem.unwrap(stack[5]), symbol(vaultSymbol), "vault-symbol");
        assertEq(StackItem.unwrap(stack[6]), priceDomain(), "price-domain");
        return (stack, writes);
    }

    function signedAt(string memory ticker, Float time) internal view virtual returns (SignedContextV2[] memory);

    function mintGrid(string memory vaultSymbol, Float time) internal view returns (bytes32[][] memory) {
        return grid(vaultSymbol, decimal(AMOUNT, 0), signedAt(tickerOf(vaultSymbol), time));
    }

    function mintAt(string memory vaultSymbol, Float time) internal {
        (, bytes32[] memory writes) = evalAccepted(mintGrid(vaultSymbol, time), vaultSymbol, decimal(AMOUNT * PRICE, 0));
        I_STORE.set(StateNamespace.wrap(0), writes);
    }

    function mintRefusedAt(string memory vaultSymbol, Float time) internal {
        evalReverts(mintGrid(vaultSymbol, time), ensureError("Lead time went backwards"));
    }

    function storedLeadTime(string memory ticker) internal view returns (bytes32) {
        return I_STORE.get(LibNamespace.qualifyNamespace(StateNamespace.wrap(0), address(this)), leadTimeKey(ticker));
    }

    function testTheFirstMintOfATickerIsAcceptedAndStoresItsLeadTime() external {
        assertEq(storedLeadTime(TICKER), bytes32(0), "unset");
        mintAt(VAULT_SYMBOL, at(-MAX_TIME_SPREAD));
        assertEq(storedLeadTime(TICKER), Float.unwrap(at(-MAX_TIME_SPREAD)), "stored");
    }

    function testAMintBeforeTheStoredLeadTimeIsRefused() external {
        mintAt(VAULT_SYMBOL, at(0));
        mintRefusedAt(VAULT_SYMBOL, at(-1));
        mintRefusedAt(VAULT_SYMBOL, decimal(NOW * 10 - 1, -1));
        mintRefusedAt(VAULT_SYMBOL, at(-MAX_TIME_SPREAD));
        assertEq(storedLeadTime(TICKER), Float.unwrap(at(0)), "unchanged");
    }

    function testAMintAtTheStoredLeadTimeIsAccepted() external {
        mintAt(VAULT_SYMBOL, at(0));
        mintAt(VAULT_SYMBOL, at(0));
        mintAt(VAULT_SYMBOL, decimal(NOW * 10, -1));
        assertTrue(Float.wrap(storedLeadTime(TICKER)).eq(at(0)), "stored");
    }

    function testAMintAfterTheStoredLeadTimeMovesItForward() external {
        mintAt(VAULT_SYMBOL, at(-1));
        mintAt(VAULT_SYMBOL, at(0));
        assertEq(storedLeadTime(TICKER), Float.unwrap(at(0)), "moved");
        mintRefusedAt(VAULT_SYMBOL, at(-1));
    }

    function testEachTickerHasItsOwnLeadTime() external {
        mintAt(VAULT_SYMBOL, at(0));
        mintAt(OTHER_VAULT_SYMBOL, at(-1));
        assertEq(storedLeadTime(TICKER), Float.unwrap(at(0)), "ticker");
        assertEq(storedLeadTime(OTHER_TICKER), Float.unwrap(at(-1)), "other ticker");
        mintRefusedAt(VAULT_SYMBOL, at(-1));
        mintAt(OTHER_VAULT_SYMBOL, at(-1));
        mintRefusedAt(OTHER_VAULT_SYMBOL, at(-2));
    }

    function testASecondMintIsAcceptedIffItsLeadTimeIsNotBeforeTheFirst(int256 first, int256 second) external {
        first = bound(first, -MAX_TIME_SPREAD, MAX_TIME_SPREAD);
        second = bound(second, -MAX_TIME_SPREAD, MAX_TIME_SPREAD);
        mintAt(VAULT_SYMBOL, at(first));
        if (second >= first) {
            mintAt(VAULT_SYMBOL, at(second));
            assertEq(storedLeadTime(TICKER), Float.unwrap(at(second)), "stored");
        } else {
            mintRefusedAt(VAULT_SYMBOL, at(second));
        }
    }
}

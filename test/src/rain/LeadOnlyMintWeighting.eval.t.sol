// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Strings} from "@openzeppelin-contracts-5.7.0/utils/Strings.sol";
import {stdError} from "forge-std-1.17.0/src/StdError.sol";
import {Float} from "rain-math-float-0.3.11/src/lib/LibDecimalFloat.sol";
import {SignedContextV2} from "rainlang-0.2.31/src/interface/IInterpreterCallerV5.sol";
import {StackItem} from "rainlang-0.2.31/src/interface/IInterpreterV4.sol";
import {LibIntOrAString, IntOrAString} from "rain-intorastring-0.1.4/src/lib/LibIntOrAString.sol";

import {
    CONTEXT_ATTESTATION_ROWS,
    CONTEXT_ATTESTATION_ROW_SYMBOL,
    CONTEXT_ATTESTATION_ROW_PRICE,
    CONTEXT_ATTESTATION_ROW_TIME,
    CONTEXT_ATTESTATION_ROW_SOURCE,
    CONTEXT_ATTESTATION_ROW_CURRENCY
} from "src/lib/LibSt0xAttestContext.sol";
import {DotrainBinding} from "test/lib/LibTestDotrain.sol";
import {WeightingEvalTest} from "test/src/rain/WeightingEvalTest.sol";

/// @title LeadOnlyMintWeightingEvalTest
/// @notice `src/rain/lead-only-mint-weighting.rain` evaluated directly over a
/// grid: its stack, and each of its refusals.
contract LeadOnlyMintWeightingEvalTest is WeightingEvalTest {
    using Strings for address;

    struct Attestation {
        uint256 key;
        bytes32 domain;
        bytes32 attestedSymbol;
        Float price;
        Float time;
        bytes32 priceSource;
        bytes32 currency;
    }

    uint256 internal constant STACK_LENGTH = 6;

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version)");

    function dotrainPath() internal pure override returns (string memory) {
        return "src/rain/lead-only-mint-weighting.rain";
    }

    function bindings() internal view override returns (DotrainBinding[] memory) {
        DotrainBinding[] memory all = new DotrainBinding[](5);
        all[0] = DotrainBinding("st0x-attest-subparser", address(I_SUB_PARSER).toHexString());
        all[1] = DotrainBinding("lead-signer", vm.addr(LEAD_KEY).toHexString());
        all[2] = DotrainBinding("max-time-spread", vm.toString(MAX_TIME_SPREAD));
        all[3] = DotrainBinding("min-price", vm.toString(MIN_PRICE));
        all[4] = DotrainBinding("max-price", vm.toString(MAX_PRICE));
        return all;
    }

    function eip712Domain(bytes32 typehash, string memory name, string memory version) internal pure returns (bytes32) {
        return keccak256(abi.encode(typehash, keccak256(bytes(name)), keccak256(bytes(version))));
    }

    function leadDomainName(bytes32 priceSource, bytes32 currency) internal pure returns (string memory) {
        return string.concat(
            "proof-of-reserves.org/prices/",
            LibIntOrAString.toStringV3(IntOrAString.wrap(uint256(priceSource))),
            "/",
            LibIntOrAString.toStringV3(IntOrAString.wrap(uint256(currency)))
        );
    }

    /// The spec's per-source lead domain.
    function leadDomain(bytes32 priceSource, bytes32 currency) internal pure returns (bytes32) {
        return eip712Domain(EIP712_DOMAIN_TYPEHASH, leadDomainName(priceSource, currency), "1");
    }

    function lead() internal pure returns (Attestation memory) {
        bytes32 priceSource = symbol("alpaca");
        bytes32 currency = symbol("USD");
        return Attestation({
            key: LEAD_KEY,
            domain: leadDomain(priceSource, currency),
            attestedSymbol: symbol(TICKER),
            price: decimal(PRICE, 0),
            time: at(0),
            priceSource: priceSource,
            currency: currency
        });
    }

    function only(Attestation memory attestation) internal pure returns (Attestation[] memory) {
        Attestation[] memory attestations = new Attestation[](1);
        attestations[0] = attestation;
        return attestations;
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

    function accepted(string memory vaultSymbol, Float amount, SignedContextV2[] memory signed, Float value)
        internal
        view
    {
        StackItem[] memory stack = evalAccepted(grid(vaultSymbol, amount, signed), STACK_LENGTH, vaultSymbol, value);
        assertEq(StackItem.unwrap(stack[5]), EIP712_DOMAIN_TYPEHASH, "eip712-domain-typehash");
    }

    function accepted(Attestation memory attestation, Float value) internal view {
        accepted(VAULT_SYMBOL, decimal(AMOUNT, 0), signAll(only(attestation)), value);
    }

    function refused(string memory vaultSymbol, Attestation[] memory attestations, bytes memory err) internal {
        evalReverts(grid(vaultSymbol, decimal(AMOUNT, 0), signAll(attestations)), err);
    }

    function refused(Attestation memory attestation, string memory reason) internal {
        refused(VAULT_SYMBOL, only(attestation), ensureError(reason));
    }

    function testLeadAttestationOutputsMintAmountTimesLeadPrice() external view {
        accepted(lead(), decimal(AMOUNT * PRICE, 0));
    }

    function testValueIsMintAmountTimesLeadPrice(int256 amount, int256 amountExponent, int256 priceCents)
        external
        view
    {
        amount = bound(amount, 0, 1e30);
        amountExponent = bound(amountExponent, -18, 0);
        priceCents = bound(priceCents, MIN_PRICE * 100, MAX_PRICE * 100);
        Attestation memory attestation = lead();
        attestation.price = decimal(priceCents, -2);
        accepted(
            VAULT_SYMBOL,
            decimal(amount, amountExponent),
            signAll(only(attestation)),
            decimal(amount * priceCents, amountExponent - 2)
        );
    }

    function testLeadPriceAtTheBoundsIsAccepted() external view {
        int256[2] memory prices = [MIN_PRICE, MAX_PRICE];
        for (uint256 i = 0; i < prices.length; i++) {
            Attestation memory attestation = lead();
            attestation.price = decimal(prices[i], 0);
            accepted(attestation, decimal(AMOUNT * prices[i], 0));
        }
    }

    function testLeadPriceOutsideTheBoundsIsRefused() external {
        Float[6] memory prices = [
            decimal(MIN_PRICE - 1, 0),
            decimal(MIN_PRICE * 100 - 1, -2),
            decimal(MAX_PRICE + 1, 0),
            decimal(MAX_PRICE * 100 + 1, -2),
            decimal(0, 0),
            decimal(-PRICE, 0)
        ];
        for (uint256 i = 0; i < prices.length; i++) {
            Attestation memory attestation = lead();
            attestation.price = prices[i];
            refused(attestation, "Price outside bounds");
        }
    }

    function testLeadPriceIsAcceptedIffWithinTheBounds(int256 priceCents) external {
        priceCents = bound(priceCents, -MAX_PRICE * 100, MAX_PRICE * 200);
        Attestation memory attestation = lead();
        attestation.price = decimal(priceCents, -2);
        if (MIN_PRICE * 100 <= priceCents && priceCents <= MAX_PRICE * 100) {
            accepted(attestation, decimal(AMOUNT * priceCents, -2));
        } else {
            refused(attestation, "Price outside bounds");
        }
    }

    function testLeadTimeWithinTheSpreadEitherSideIsAccepted() external view {
        int256[3] memory offsets = [-MAX_TIME_SPREAD, int256(0), MAX_TIME_SPREAD];
        for (uint256 i = 0; i < offsets.length; i++) {
            Attestation memory attestation = lead();
            attestation.time = at(offsets[i]);
            accepted(attestation, decimal(AMOUNT * PRICE, 0));
        }
    }

    function testLeadTimeBeyondTheSpreadEitherSideIsRefused() external {
        Float[4] memory times = [
            at(-MAX_TIME_SPREAD - 1),
            at(MAX_TIME_SPREAD + 1),
            decimal((NOW - MAX_TIME_SPREAD) * 10 - 5, -1),
            decimal((NOW + MAX_TIME_SPREAD) * 10 + 5, -1)
        ];
        for (uint256 i = 0; i < times.length; i++) {
            Attestation memory attestation = lead();
            attestation.time = times[i];
            refused(attestation, "Times disagree");
        }
    }

    function testLeadTimeIsAcceptedIffWithinTheSpreadOfTheClock(int256 offset) external {
        offset = bound(offset, -3 * MAX_TIME_SPREAD, 3 * MAX_TIME_SPREAD);
        Attestation memory attestation = lead();
        attestation.time = at(offset);
        if (-MAX_TIME_SPREAD <= offset && offset <= MAX_TIME_SPREAD) {
            accepted(attestation, decimal(AMOUNT * PRICE, 0));
        } else {
            refused(attestation, "Times disagree");
        }
    }

    /// Each of these would be refused as the lead.
    function testAttestationsAfterTheLeadAreNotRead() external view {
        Attestation[] memory others = new Attestation[](8);
        for (uint256 i = 0; i < others.length; i++) {
            others[i] = lead();
        }
        others[0].key = OPERATOR_KEY_0;
        others[1].domain = POOL_DOMAIN;
        others[2].attestedSymbol = symbol(OTHER_TICKER);
        others[3].currency = symbol("EUR");
        others[4].time = at(-10 * MAX_TIME_SPREAD);
        others[5].price = decimal(10 * MAX_PRICE, 0);
        others[6].priceSource = symbol("yahoo");
        others[7].price = decimal(2 * PRICE, 0);

        Attestation[] memory all = new Attestation[](1 + others.length);
        all[0] = lead();
        for (uint256 i = 0; i < others.length; i++) {
            Attestation[] memory pair = new Attestation[](2);
            pair[0] = lead();
            pair[1] = others[i];
            accepted(VAULT_SYMBOL, decimal(AMOUNT, 0), signAll(pair), decimal(AMOUNT * PRICE, 0));
            all[1 + i] = others[i];
        }
        accepted(VAULT_SYMBOL, decimal(AMOUNT, 0), signAll(all), decimal(AMOUNT * PRICE, 0));

        SignedContextV2[] memory shortContexts = new SignedContextV2[](3);
        shortContexts[0] = signAll(only(lead()))[0];
        shortContexts[1] = sign(OPERATOR_KEY_0, new bytes32[](1));
        shortContexts[2] = sign(OPERATOR_KEY_0 + 1, new bytes32[](0));
        accepted(VAULT_SYMBOL, decimal(AMOUNT, 0), shortContexts, decimal(AMOUNT * PRICE, 0));
    }

    function testAnySignerButTheLeadSignerIsRefused(uint256 key) external {
        key = boundPrivateKey(key);
        vm.assume(vm.addr(key) != vm.addr(LEAD_KEY));
        Attestation memory attestation = lead();
        attestation.key = key;
        refused(attestation, "Lead attestation missing");
    }

    function testTheLeadBehindAnotherSignerIsRefused() external {
        Attestation[] memory attestations = new Attestation[](2);
        attestations[0] = lead();
        attestations[0].key = OPERATOR_KEY_0;
        attestations[1] = lead();
        refused(VAULT_SYMBOL, attestations, ensureError("Lead attestation missing"));
    }

    function testNoAttestationsRevertsReadingTheLead() external {
        evalReverts(grid(VAULT_SYMBOL, decimal(AMOUNT, 0), new SignedContextV2[](0)), stdError.indexOOBError);
    }

    function testLeadUnderAnyOtherDomainIsRefused(bytes32 other) external {
        Attestation memory attestation = lead();
        vm.assume(other != attestation.domain);
        attestation.domain = other;
        refused(attestation, "Lead domain mismatch");
    }

    function testLeadUnderANeighbouringDomainIsRefused() external {
        bytes32 alpaca = symbol("alpaca");
        bytes32 usd = symbol("USD");
        bytes32[6] memory domains = [
            POOL_DOMAIN,
            LEAD_DOMAIN,
            leadDomain(symbol("yahoo"), usd),
            leadDomain(alpaca, symbol("EUR")),
            eip712Domain(EIP712_DOMAIN_TYPEHASH, leadDomainName(alpaca, usd), "2"),
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId)"),
                    keccak256(bytes(leadDomainName(alpaca, usd))),
                    keccak256("1"),
                    block.chainid
                )
            )
        ];
        for (uint256 i = 0; i < domains.length; i++) {
            Attestation memory attestation = lead();
            attestation.domain = domains[i];
            refused(attestation, "Lead domain mismatch");
        }
    }

    function testAnySourceIsAcceptedUnderItsOwnDomain(bytes32 priceSource) external view {
        Attestation memory attestation = lead();
        attestation.priceSource = priceSource;
        attestation.domain = leadDomain(priceSource, attestation.currency);
        accepted(attestation, decimal(AMOUNT * PRICE, 0));
    }

    function testATickerOfAnyLengthIsAccepted() external view {
        string[6] memory tickers =
            [string("MU"), "TSM", TICKER, OTHER_TICKER, "GOOGL", "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123"];
        for (uint256 i = 0; i < tickers.length; i++) {
            Attestation memory attestation = lead();
            attestation.attestedSymbol = symbol(tickers[i]);
            accepted(
                string.concat("t", tickers[i]),
                decimal(AMOUNT, 0),
                signAll(only(attestation)),
                decimal(AMOUNT * PRICE, 0)
            );
        }
    }

    function testAnotherTokensTickerIsRefused() external {
        Attestation memory attestation = lead();
        attestation.attestedSymbol = symbol(OTHER_TICKER);
        refused(VAULT_SYMBOL, only(attestation), ensureError("Attestation for another token"));
        refused(OTHER_VAULT_SYMBOL, only(lead()), ensureError("Attestation for another token"));
    }

    function testAttestingTheVaultSymbolIsRefused() external {
        Attestation memory attestation = lead();
        attestation.attestedSymbol = symbol(VAULT_SYMBOL);
        refused(attestation, "Attestation for another token");
    }

    function testAnyLeadSymbolButTheTickerIsRefused(bytes32 attestedSymbol) external {
        vm.assume(attestedSymbol != symbol(TICKER));
        Attestation memory attestation = lead();
        attestation.attestedSymbol = attestedSymbol;
        refused(attestation, "Attestation for another token");
    }

    function testAVaultSymbolWithoutTheTPrefixIsRefused() external {
        string[4] memory vaultSymbols = ["MSTR", "xMSTR", "TMSTR", ""];
        string[4] memory tickers = ["STR", "MSTR", "MSTR", ""];
        for (uint256 i = 0; i < vaultSymbols.length; i++) {
            Attestation memory attestation = lead();
            attestation.attestedSymbol = symbol(tickers[i]);
            refused(vaultSymbols[i], only(attestation), ensureError("Vault symbol has no t prefix"));
        }
    }

    function testAnyFirstCharacterButTIsRefused(bytes1 first) external {
        vm.assume(first != "t");
        refused(string(bytes.concat(first, bytes(TICKER))), only(lead()), ensureError("Vault symbol has no t prefix"));
    }

    function testANonUsdCurrencyIsRefused() external {
        bytes32[7] memory currencies =
            [symbol("EUR"), symbol("usd"), symbol("USDT"), symbol("US"), symbol("USD "), symbol(""), bytes32(0)];
        for (uint256 i = 0; i < currencies.length; i++) {
            Attestation memory attestation = lead();
            attestation.currency = currencies[i];
            attestation.domain = leadDomain(attestation.priceSource, currencies[i]);
            refused(attestation, "Price not in USD");
        }
    }

    function testAnyCurrencyButUsdIsRefused(bytes32 currency) external {
        vm.assume(currency != symbol("USD"));
        Attestation memory attestation = lead();
        attestation.currency = currency;
        attestation.domain = leadDomain(attestation.priceSource, currency);
        refused(attestation, "Price not in USD");
    }

    /// Fixing each failure in turn surfaces the next check's refusal.
    function testChecksRefuseInTheirOrder() external {
        Attestation memory attestation = lead();
        attestation.key = OPERATOR_KEY_0;
        attestation.domain = POOL_DOMAIN;
        attestation.attestedSymbol = symbol(OTHER_TICKER);
        attestation.currency = symbol("EUR");
        attestation.time = at(-MAX_TIME_SPREAD - 1);
        attestation.price = decimal(MAX_PRICE + 1, 0);
        string memory vaultSymbol = TICKER;

        refused(vaultSymbol, only(attestation), ensureError("Lead attestation missing"));
        attestation.key = LEAD_KEY;
        refused(vaultSymbol, only(attestation), ensureError("Lead domain mismatch"));
        attestation.domain = leadDomain(attestation.priceSource, attestation.currency);
        refused(vaultSymbol, only(attestation), ensureError("Vault symbol has no t prefix"));
        vaultSymbol = VAULT_SYMBOL;
        refused(vaultSymbol, only(attestation), ensureError("Attestation for another token"));
        attestation.attestedSymbol = symbol(TICKER);
        refused(vaultSymbol, only(attestation), ensureError("Price not in USD"));
        attestation.currency = symbol("USD");
        attestation.domain = leadDomain(attestation.priceSource, attestation.currency);
        refused(vaultSymbol, only(attestation), ensureError("Times disagree"));
        attestation.time = at(0);
        refused(vaultSymbol, only(attestation), ensureError("Price outside bounds"));
        attestation.price = decimal(PRICE, 0);
        accepted(attestation, decimal(AMOUNT * PRICE, 0));
    }
}

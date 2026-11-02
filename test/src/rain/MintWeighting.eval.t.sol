// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {stdError} from "forge-std-1.17.0/src/StdError.sol";
import {Float} from "rain-math-float-0.3.11/src/lib/LibDecimalFloat.sol";
import {SignedContextV2} from "rainlang-0.2.31/src/interface/IInterpreterCallerV5.sol";

import {WeightingEvalTest} from "test/src/rain/WeightingEvalTest.sol";

/// @title MintWeightingEvalTest
/// @notice `src/rain/mint-weighting.rain` evaluated directly over a grid: its
/// stack, and each of its refusals.
contract MintWeightingEvalTest is WeightingEvalTest {
    struct Attestation {
        uint256 key;
        bytes32 domain;
        bytes32 attestedSymbol;
        Float price;
        Float time;
    }

    uint256 internal constant STACK_LENGTH = 5;

    uint256 internal constant UNLISTED_KEY = OPERATOR_KEY_0 + POOL_SIZE;

    function bindingSet() internal pure override returns (string memory) {
        return "mint-weighting";
    }

    function operator(uint256 i) internal pure returns (address) {
        return vm.addr(OPERATOR_KEY_0 + i);
    }

    function attestationBy(uint256 key) internal pure returns (Attestation memory) {
        return Attestation({
            key: key, domain: domainOf(key), attestedSymbol: symbol(TICKER), price: decimal(PRICE, 0), time: at(0)
        });
    }

    function quorum() internal pure returns (Attestation[] memory) {
        Attestation[] memory attestations = new Attestation[](3);
        attestations[0] = attestationBy(LEAD_KEY);
        attestations[1] = attestationBy(OPERATOR_KEY_0);
        attestations[2] = attestationBy(OPERATOR_KEY_0 + 1);
        return attestations;
    }

    function quorumAt(Float price) internal pure returns (Attestation[] memory) {
        Attestation[] memory attestations = quorum();
        for (uint256 i = 0; i < attestations.length; i++) {
            attestations[i].price = price;
        }
        return attestations;
    }

    function signAll(Attestation[] memory attestations) internal pure returns (SignedContextV2[] memory) {
        SignedContextV2[] memory signed = new SignedContextV2[](attestations.length);
        for (uint256 i = 0; i < attestations.length; i++) {
            signed[i] = attestUnder(
                attestations[i].key,
                attestations[i].domain,
                attestations[i].attestedSymbol,
                Float.unwrap(attestations[i].price),
                Float.unwrap(attestations[i].time)
            );
        }
        return signed;
    }

    function accepted(string memory vaultSymbol, Float amount, SignedContextV2[] memory signed, Float value)
        internal
        view
    {
        evalAccepted(grid(vaultSymbol, amount, signed), STACK_LENGTH, vaultSymbol, value);
    }

    function accepted(Attestation[] memory attestations, Float value) internal view {
        accepted(VAULT_SYMBOL, decimal(AMOUNT, 0), signAll(attestations), value);
    }

    function refused(string memory vaultSymbol, SignedContextV2[] memory signed, bytes memory err) internal {
        evalReverts(grid(vaultSymbol, decimal(AMOUNT, 0), signed), err);
    }

    function refused(Attestation[] memory attestations, string memory reason) internal {
        refused(VAULT_SYMBOL, signAll(attestations), ensureError(reason));
    }

    function testQuorumOutputsMintAmountTimesLeadPrice() external view {
        accepted(quorum(), decimal(AMOUNT * PRICE, 0));
    }

    function testValueIsMintAmountTimesTheLeadsPriceNotThePools() external view {
        Attestation[] memory attestations = quorum();
        attestations[1].price = decimal(151, 0);
        attestations[2].price = decimal(1495, -1);
        accepted(attestations, decimal(AMOUNT * PRICE, 0));

        attestations = quorum();
        attestations[0].price = decimal(151, 0);
        accepted(attestations, decimal(AMOUNT * 151, 0));
    }

    function testValueIsMintAmountTimesLeadPrice(int256 amount, int256 amountExponent, int256 priceCents)
        external
        view
    {
        amount = bound(amount, 0, 1e30);
        amountExponent = bound(amountExponent, -18, 0);
        priceCents = bound(priceCents, MIN_PRICE * 100, MAX_PRICE * 100);
        accepted(
            VAULT_SYMBOL,
            decimal(amount, amountExponent),
            signAll(quorumAt(decimal(priceCents, -2))),
            decimal(amount * priceCents, amountExponent - 2)
        );
    }

    function testEveryOrderedPairOfDistinctOperatorsIsAccepted() external view {
        for (uint256 i = 0; i < POOL_SIZE; i++) {
            for (uint256 j = 0; j < POOL_SIZE; j++) {
                if (i == j) continue;
                Attestation[] memory attestations = quorum();
                attestations[1] = attestationBy(OPERATOR_KEY_0 + i);
                attestations[2] = attestationBy(OPERATOR_KEY_0 + j);
                accepted(attestations, decimal(AMOUNT * PRICE, 0));
            }
        }
    }

    /// Each of these would be refused in a seat.
    function testPoolAttestationsPastTheSecondAreNotRead() external view {
        Attestation[] memory others = new Attestation[](7);
        others[0] = attestationBy(UNLISTED_KEY);
        others[1] = attestationBy(LEAD_KEY);
        others[2] = attestationBy(OPERATOR_KEY_0);
        for (uint256 i = 3; i < others.length; i++) {
            others[i] = attestationBy(OPERATOR_KEY_0 + 2);
        }
        others[3].domain = LEAD_DOMAIN;
        others[4].attestedSymbol = symbol(OTHER_TICKER);
        others[5].time = at(-10 * MAX_TIME_SPREAD);
        others[6].price = decimal(2 * PRICE, 0);

        Attestation[] memory all = new Attestation[](3 + others.length);
        Attestation[] memory three = quorum();
        for (uint256 i = 0; i < three.length; i++) {
            all[i] = three[i];
        }
        for (uint256 i = 0; i < others.length; i++) {
            Attestation[] memory four = new Attestation[](4);
            for (uint256 j = 0; j < three.length; j++) {
                four[j] = three[j];
            }
            four[3] = others[i];
            accepted(four, decimal(AMOUNT * PRICE, 0));
            all[3 + i] = others[i];
        }
        accepted(all, decimal(AMOUNT * PRICE, 0));

        SignedContextV2[] memory shortContexts = new SignedContextV2[](5);
        SignedContextV2[] memory signedQuorum = signAll(three);
        for (uint256 i = 0; i < signedQuorum.length; i++) {
            shortContexts[i] = signedQuorum[i];
        }
        shortContexts[3] = sign(OPERATOR_KEY_0 + 2, new bytes32[](1));
        shortContexts[4] = sign(OPERATOR_KEY_0 + 3, new bytes32[](0));
        accepted(VAULT_SYMBOL, decimal(AMOUNT, 0), shortContexts, decimal(AMOUNT * PRICE, 0));
    }

    function testNoLeadIsRefused() external {
        Attestation[] memory attestations = quorum();
        attestations[0] = attestationBy(OPERATOR_KEY_0 + 2);
        refused(attestations, "Lead attestation missing");
    }

    function testTheLeadNotFirstIsRefused() external {
        Attestation[] memory attestations = quorum();
        attestations[0] = attestationBy(OPERATOR_KEY_0);
        attestations[1] = attestationBy(LEAD_KEY);
        refused(attestations, "Lead attestation missing");
    }

    function testAnySignerFirstButTheLeadSignerIsRefused(uint256 key) external {
        key = boundPrivateKey(key);
        vm.assume(vm.addr(key) != vm.addr(LEAD_KEY));
        Attestation[] memory attestations = quorum();
        attestations[0].key = key;
        refused(attestations, "Lead attestation missing");
    }

    function testNoAttestationsRevertsReadingTheLead() external {
        refused(VAULT_SYMBOL, new SignedContextV2[](0), stdError.indexOOBError);
    }

    function testFewerThanTwoPoolAttestationsRevertReadingTheSeat() external {
        Attestation[] memory attestations = quorum();
        for (uint256 length = 1; length < attestations.length; length++) {
            Attestation[] memory fewer = new Attestation[](length);
            for (uint256 i = 0; i < length; i++) {
                fewer[i] = attestations[i];
            }
            refused(VAULT_SYMBOL, signAll(fewer), stdError.indexOOBError);
        }
    }

    function testAnyUnlistedSignerInEitherSeatIsRefused(uint256 key) external {
        key = boundPrivateKey(key);
        vm.assume(vm.addr(key) != vm.addr(LEAD_KEY));
        for (uint256 i = 0; i < POOL_SIZE; i++) {
            vm.assume(vm.addr(key) != operator(i));
        }
        for (uint256 seat = 1; seat < 3; seat++) {
            Attestation[] memory attestations = quorum();
            attestations[seat] = attestationBy(key);
            refused(attestations, "Attestor not allowlisted");
        }
    }

    function testTheLeadInEitherPoolSeatIsRefused() external {
        for (uint256 seat = 1; seat < 3; seat++) {
            Attestation[] memory attestations = quorum();
            attestations[seat] = attestationBy(LEAD_KEY);
            refused(attestations, "Attestor not allowlisted");
        }
    }

    function testTheSameOperatorInBothSeatsIsRefused() external {
        for (uint256 i = 0; i < POOL_SIZE; i++) {
            Attestation[] memory attestations = quorum();
            attestations[1] = attestationBy(OPERATOR_KEY_0 + i);
            attestations[2] = attestationBy(OPERATOR_KEY_0 + i);
            refused(attestations, "Same operator twice");
        }
    }

    function testTheLeadInEitherPoolSeatIsRefusedWhenAllowlisted() external {
        install("mint-weighting-operator-6");
        for (uint256 seat = 1; seat < 3; seat++) {
            Attestation[] memory attestations = quorum();
            attestations[seat] = attestationBy(LEAD_KEY);
            attestations[seat].domain = POOL_DOMAIN;
            refused(attestations, "Same operator twice");
        }
    }

    function testLeadUnderAnyOtherDomainIsRefused(bytes32 other) external {
        vm.assume(other != LEAD_DOMAIN);
        bytes32[2] memory domains = [POOL_DOMAIN, other];
        for (uint256 i = 0; i < domains.length; i++) {
            Attestation[] memory attestations = quorum();
            attestations[0].domain = domains[i];
            refused(attestations, "Lead domain mismatch");
        }
    }

    function testAttestorUnderAnyOtherDomainInEitherSeatIsRefused(bytes32 other) external {
        vm.assume(other != POOL_DOMAIN);
        bytes32[2] memory domains = [LEAD_DOMAIN, other];
        for (uint256 i = 0; i < domains.length; i++) {
            for (uint256 seat = 1; seat < 3; seat++) {
                Attestation[] memory attestations = quorum();
                attestations[seat].domain = domains[i];
                refused(attestations, "Attestor domain mismatch");
            }
            Attestation[] memory both = quorum();
            both[1].domain = domains[i];
            both[2].domain = domains[i];
            refused(both, "Attestor domain mismatch");
        }
    }

    function testATickerOfAnyLengthIsAccepted() external view {
        string[6] memory tickers =
            [string("MU"), "TSM", TICKER, OTHER_TICKER, "GOOGL", "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123"];
        for (uint256 i = 0; i < tickers.length; i++) {
            Attestation[] memory attestations = quorum();
            for (uint256 j = 0; j < attestations.length; j++) {
                attestations[j].attestedSymbol = symbol(tickers[i]);
            }
            accepted(
                string.concat("t", tickers[i]), decimal(AMOUNT, 0), signAll(attestations), decimal(AMOUNT * PRICE, 0)
            );
        }
    }

    function testAnotherTokensTickerInAnySeatIsRefused() external {
        for (uint256 i = 0; i < 3; i++) {
            Attestation[] memory attestations = quorum();
            attestations[i].attestedSymbol = symbol(OTHER_TICKER);
            refused(attestations, "Attestation for another token");
        }
        refused(OTHER_VAULT_SYMBOL, signAll(quorum()), ensureError("Attestation for another token"));
    }

    function testAttestingTheVaultSymbolIsRefused() external {
        Attestation[] memory attestations = quorum();
        for (uint256 i = 0; i < attestations.length; i++) {
            attestations[i].attestedSymbol = symbol(VAULT_SYMBOL);
        }
        refused(attestations, "Attestation for another token");
    }

    function testAVaultSymbolWithoutTheTPrefixIsRefused() external {
        string[4] memory vaultSymbols = ["MSTR", "xMSTR", "TMSTR", ""];
        string[4] memory tickers = ["STR", "MSTR", "MSTR", ""];
        for (uint256 i = 0; i < vaultSymbols.length; i++) {
            Attestation[] memory attestations = quorum();
            for (uint256 j = 0; j < attestations.length; j++) {
                attestations[j].attestedSymbol = symbol(tickers[i]);
            }
            refused(vaultSymbols[i], signAll(attestations), ensureError("Vault symbol has no t prefix"));
        }
    }

    function testAnyFirstCharacterButTIsRefused(bytes1 first) external {
        vm.assume(first != "t");
        refused(
            string(bytes.concat(first, bytes(TICKER))), signAll(quorum()), ensureError("Vault symbol has no t prefix")
        );
    }

    function testTimesWithinTheSpreadOfEachOtherAndTheClockAreAccepted() external view {
        Attestation[] memory attestations = quorum();
        attestations[0].time = at(-MAX_TIME_SPREAD);
        accepted(attestations, decimal(AMOUNT * PRICE, 0));

        attestations = quorum();
        attestations[2].time = at(MAX_TIME_SPREAD);
        accepted(attestations, decimal(AMOUNT * PRICE, 0));

        attestations = quorum();
        attestations[0].time = at(-MAX_TIME_SPREAD / 2);
        attestations[1].time = at(MAX_TIME_SPREAD / 2);
        accepted(attestations, decimal(AMOUNT * PRICE, 0));
    }

    function testATimeBeyondTheSpreadInAnySeatIsRefused() external {
        int256[2] memory offsets = [-MAX_TIME_SPREAD - 1, MAX_TIME_SPREAD + 1];
        for (uint256 t = 0; t < offsets.length; t++) {
            Attestation[] memory all = quorum();
            for (uint256 i = 0; i < 3; i++) {
                Attestation[] memory attestations = quorum();
                attestations[i].time = at(offsets[t]);
                refused(attestations, "Times disagree");
                all[i].time = at(offsets[t]);
            }
            refused(all, "Times disagree");
        }
    }

    /// Each time is within the spread of the clock, but not of the other.
    function testTimesSpreadAcrossTheClockAreRefused() external {
        Attestation[] memory attestations = quorum();
        attestations[0].time = at(-MAX_TIME_SPREAD / 2);
        attestations[1].time = at(MAX_TIME_SPREAD / 2 + 1);
        refused(attestations, "Times disagree");
    }

    function testTimesAgreeIffWithinTheSpreadOfEachOtherAndTheClock(int256 leadOffset, int256 offset0, int256 offset1)
        external
    {
        int256[3] memory offsets = [
            bound(leadOffset, -2 * MAX_TIME_SPREAD, 2 * MAX_TIME_SPREAD),
            bound(offset0, -2 * MAX_TIME_SPREAD, 2 * MAX_TIME_SPREAD),
            bound(offset1, -2 * MAX_TIME_SPREAD, 2 * MAX_TIME_SPREAD)
        ];
        Attestation[] memory attestations = quorum();
        int256 highest = 0;
        int256 lowest = 0;
        for (uint256 i = 0; i < offsets.length; i++) {
            attestations[i].time = at(offsets[i]);
            if (offsets[i] > highest) highest = offsets[i];
            if (offsets[i] < lowest) lowest = offsets[i];
        }
        if (highest - lowest <= MAX_TIME_SPREAD) {
            accepted(attestations, decimal(AMOUNT * PRICE, 0));
        } else {
            refused(attestations, "Times disagree");
        }
    }

    /// 198 is exactly 1% of 200 below it; 202.02 is just within 1% of itself.
    function testPricesWithinMaxDeviationOfTheHighestAreAccepted() external view {
        Attestation[] memory attestations = quorumAt(decimal(200, 0));
        attestations[1].price = decimal(198, 0);
        accepted(attestations, decimal(AMOUNT * 200, 0));

        attestations = quorumAt(decimal(198, 0));
        attestations[2].price = decimal(200, 0);
        accepted(attestations, decimal(AMOUNT * 198, 0));

        attestations = quorumAt(decimal(200, 0));
        attestations[2].price = decimal(20202, -2);
        accepted(attestations, decimal(AMOUNT * 200, 0));
    }

    function testAPriceBeyondMaxDeviationInAnySeatIsRefused() external {
        Float[2] memory prices = [decimal(19799, -2), decimal(20203, -2)];
        for (uint256 p = 0; p < prices.length; p++) {
            for (uint256 i = 0; i < 3; i++) {
                Attestation[] memory attestations = quorumAt(decimal(200, 0));
                attestations[i].price = prices[p];
                refused(attestations, "Attestors disagree");
            }
        }
    }

    function testPricesAgreeIffWithinMaxDeviationOfTheHighest(int256 leadCents, int256 cents0, int256 cents1) external {
        leadCents = bound(leadCents, MIN_PRICE * 100, MAX_PRICE * 100);
        int256[3] memory cents = [
            leadCents,
            bound(cents0, leadCents * 97 / 100, leadCents * 103 / 100),
            bound(cents1, leadCents * 97 / 100, leadCents * 103 / 100)
        ];
        Attestation[] memory attestations = quorum();
        int256 highest = leadCents;
        int256 lowest = leadCents;
        for (uint256 i = 0; i < cents.length; i++) {
            attestations[i].price = decimal(cents[i], -2);
            if (cents[i] > highest) highest = cents[i];
            if (cents[i] < lowest) lowest = cents[i];
        }
        if (100 * (highest - lowest) <= highest) {
            accepted(attestations, decimal(AMOUNT * leadCents, -2));
        } else {
            refused(attestations, "Attestors disagree");
        }
    }

    /// Under a floor of 1 a quorum at 10 is accepted, but 10 and 10.5 are within one whole unit and 5% apart.
    function testThePriceToleranceIsProportionalOnly() external {
        install("mint-weighting-min-price");
        accepted(quorumAt(decimal(10, 0)), decimal(AMOUNT * 10, 0));
        Attestation[] memory attestations = quorumAt(decimal(10, 0));
        attestations[1].price = decimal(105, -1);
        refused(attestations, "Attestors disagree");
    }

    function testLeadPriceAtTheBoundsIsAccepted() external view {
        int256[2] memory prices = [MIN_PRICE, MAX_PRICE];
        for (uint256 i = 0; i < prices.length; i++) {
            accepted(quorumAt(decimal(prices[i], 0)), decimal(AMOUNT * prices[i], 0));
        }
    }

    function testLeadPriceOutsideTheBoundsIsRefused() external {
        Float[6] memory prices = [
            decimal(MIN_PRICE - 1, 0),
            decimal(MIN_PRICE * 10000 - 1, -4),
            decimal(MAX_PRICE + 1, 0),
            decimal(MAX_PRICE * 10000 + 1, -4),
            decimal(0, 0),
            decimal(-PRICE, 0)
        ];
        for (uint256 i = 0; i < prices.length; i++) {
            refused(quorumAt(prices[i]), "Price outside bounds");
        }
    }

    function testTheLeadOverTheCeilingIsRefusedWhateverThePool() external {
        Attestation[] memory attestations = quorumAt(decimal(MAX_PRICE, 0));
        attestations[0].price = decimal(MAX_PRICE + 1, 0);
        refused(attestations, "Price outside bounds");
    }

    function testPoolPricesOutsideTheBoundsAreAccepted() external view {
        Attestation[] memory attestations = quorumAt(decimal(MIN_PRICE, 0));
        attestations[1].price = decimal(MIN_PRICE * 1000 - 5, -3);
        attestations[2].price = decimal(MIN_PRICE * 100 - 1, -2);
        accepted(attestations, decimal(AMOUNT * MIN_PRICE, 0));

        attestations = quorumAt(decimal(MAX_PRICE, 0));
        attestations[1].price = decimal(MAX_PRICE + 5, 0);
        attestations[2].price = decimal(MAX_PRICE + 10, 0);
        accepted(attestations, decimal(AMOUNT * MAX_PRICE, 0));
    }

    /// Fixing each failure in turn surfaces the next check's refusal.
    function testChecksRefuseInTheirOrder() external {
        Attestation[] memory attestations = new Attestation[](3);
        attestations[0] = attestationBy(UNLISTED_KEY);
        attestations[1] = attestationBy(UNLISTED_KEY + 1);
        attestations[2] = attestationBy(UNLISTED_KEY + 2);
        attestations[1].domain = LEAD_DOMAIN;
        attestations[2].domain = LEAD_DOMAIN;
        for (uint256 i = 0; i < attestations.length; i++) {
            attestations[i].attestedSymbol = symbol(OTHER_TICKER);
            attestations[i].price = decimal(MAX_PRICE + 1, 0);
        }
        attestations[1].price = decimal(2 * MAX_PRICE, 0);
        attestations[2].time = at(MAX_TIME_SPREAD + 1);
        string memory vaultSymbol = TICKER;

        refused(vaultSymbol, signAll(attestations), ensureError("Lead attestation missing"));
        attestations[0].key = LEAD_KEY;
        refused(vaultSymbol, signAll(attestations), ensureError("Attestor not allowlisted"));
        attestations[1].key = OPERATOR_KEY_0;
        attestations[2].key = OPERATOR_KEY_0;
        refused(vaultSymbol, signAll(attestations), ensureError("Lead domain mismatch"));
        attestations[0].domain = LEAD_DOMAIN;
        refused(vaultSymbol, signAll(attestations), ensureError("Attestor domain mismatch"));
        attestations[1].domain = POOL_DOMAIN;
        attestations[2].domain = POOL_DOMAIN;
        refused(vaultSymbol, signAll(attestations), ensureError("Same operator twice"));
        attestations[2].key = OPERATOR_KEY_0 + 1;
        refused(vaultSymbol, signAll(attestations), ensureError("Vault symbol has no t prefix"));
        vaultSymbol = VAULT_SYMBOL;
        refused(vaultSymbol, signAll(attestations), ensureError("Attestation for another token"));
        for (uint256 i = 0; i < attestations.length; i++) {
            attestations[i].attestedSymbol = symbol(TICKER);
        }
        refused(vaultSymbol, signAll(attestations), ensureError("Times disagree"));
        attestations[2].time = at(0);
        refused(vaultSymbol, signAll(attestations), ensureError("Attestors disagree"));
        attestations[1].price = decimal(MAX_PRICE + 1, 0);
        refused(vaultSymbol, signAll(attestations), ensureError("Price outside bounds"));
        for (uint256 i = 0; i < attestations.length; i++) {
            attestations[i].price = decimal(PRICE, 0);
        }
        accepted(attestations, decimal(AMOUNT * PRICE, 0));
    }
}
